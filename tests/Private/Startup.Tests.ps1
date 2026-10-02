# Tests for what happens when the application starts: the question about administrator
# rights, the check that starts by itself, and the setting that remembers the answer.
# Nothing here asks Windows for elevation: the restart is always a mock.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param([string]$Elevation = 'Ask', [switch]$RunCheck, [switch]$NoQuestion)

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.Settings = @{ Language = 'en'; Theme = 'System'; MonitorIntervalSeconds = 2; AutoCheckMinutes = 5; StartupElevation = $Elevation }
        $gui.Startup = @{ RunCheck = [bool]$RunCheck; NoQuestion = [bool]$NoQuestion }
        $gui
    }

    function Invoke-TestStartup {
        param($Gui)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui } { Invoke-WindowStartup -Gui $Gui }
    }
}

Describe 'Get-AppSetting: what happens at the start' {
    BeforeAll {
        $appData = Join-Path -Path $TestDrive -ChildPath 'AppData'
        New-Item -Path $appData -ItemType Directory -Force | Out-Null
        $file = Join-Path -Path $appData -ChildPath 'settings.json'
    }

    AfterAll {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }

    It 'asks about administrator rights unless the user chose otherwise' {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).StartupElevation | Should -Be 'Ask'
    }

    It 'reads the remembered answer "<_>"' -ForEach 'Always', 'Never', 'Ask' {
        Set-Content -LiteralPath $file -Value ('{{ "StartupElevation": "{0}" }}' -f $_)
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).StartupElevation | Should -Be $_
    }

    It 'asks again when the file holds something else' {
        Set-Content -LiteralPath $file -Value '{ "StartupElevation": "Sometimes" }'
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).StartupElevation | Should -Be 'Ask'
    }
}

Describe 'Get-LauncherArgument: how the new copy is to start' {
    It 'passes -RunCheck and -NoQuestion on to the launcher script' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
        InModuleScope HelpdeskToolkit { Get-LauncherArgument -RunCheck } | Should -Match '-File ".+\\Start-HelpdeskToolkit\.ps1" -RunCheck$'
        InModuleScope HelpdeskToolkit { Get-LauncherArgument -NoQuestion } | Should -Match '-File ".+\\Start-HelpdeskToolkit\.ps1" -NoQuestion$'
        InModuleScope HelpdeskToolkit { Get-LauncherArgument -RunCheck -NoQuestion } | Should -Match '" -RunCheck -NoQuestion$'
    }

    It 'passes them on to the command when there is no launcher script' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        InModuleScope HelpdeskToolkit { Get-LauncherArgument -RunCheck } | Should -Match 'Show-PCHealthCheck -RunCheck"$'
        InModuleScope HelpdeskToolkit { Get-LauncherArgument } | Should -Match 'Show-PCHealthCheck"$'
    }
}

Describe 'The question at the start' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Invoke-WindowCheck { }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
    }

    Context 'the layout' {
        BeforeAll {
            $gui = New-TestWindow
        }

        It 'exposes the control <_>' -ForEach @('MainLayout', 'StartupOverlay', 'StartupYesButton', 'StartupNoButton', 'StartupRememberBox', 'StartupBox') {
            $gui.Controls[$_] | Should -Not -BeNullOrEmpty
        }

        It 'is hidden until the window decides to ask' {
            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Collapsed'
            $gui.Controls.MainLayout.IsEnabled | Should -BeTrue
        }

        It 'offers "Yes" with the shield of Windows and "No", and does not remember the answer unless asked to' {
            $gui.Controls.StartupYesButton.Content | Should -Be 'Yes, as administrator'
            [int][char]$gui.Controls.StartupYesButton.Tag | Should -Be 0xEA18
            $gui.Controls.StartupNoButton.Content | Should -Be 'No, standard rights'
            $gui.Controls.StartupRememberBox.IsChecked | Should -BeFalse
        }

        It 'is shown in the language of the window' {
            try {
                InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
                $croatian = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
                $croatian.Controls.StartupYesButton.Content | Should -Be 'Da, kao administrator'
                $croatian.Controls.StartupNoButton.Content | Should -Be 'Ne, standardna prava'
            }
            finally {
                InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
            }
        }
    }

    Context 'when the window opens' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Invoke-WindowElevationChoice { }
        }

        It 'asks, and keeps the window behind the question from being used' {
            $gui = New-TestWindow
            Invoke-TestStartup -Gui $gui | Should -Be 'Ask'

            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Visible'
            $gui.Controls.MainLayout.IsEnabled | Should -BeFalse
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly
        }

        It 'asks nothing and starts the check when the window already has administrator rights' {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            $gui = New-TestWindow
            Invoke-TestStartup -Gui $gui | Should -Be 'Check'

            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Collapsed'
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly
        }

        It 'asks nothing and starts the check when it was started to do so' {
            $gui = New-TestWindow -RunCheck
            Invoke-TestStartup -Gui $gui | Should -Be 'Check'

            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Collapsed'
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly
        }

        It 'starts the check with standard rights when the remembered answer is "No"' {
            $gui = New-TestWindow -Elevation 'Never'
            Invoke-TestStartup -Gui $gui | Should -Be 'Check'

            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Collapsed'
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowElevationChoice -Times 0 -Exactly
        }

        It 'goes straight for administrator rights when the remembered answer is "Yes"' {
            $gui = New-TestWindow -Elevation 'Always'
            Invoke-TestStartup -Gui $gui | Should -Be 'Elevate'

            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Collapsed'
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowElevationChoice -Times 1 -Exactly -ParameterFilter { $Elevate }
        }

        It 'neither asks nor checks when the window was started with -NoQuestion' {
            $gui = New-TestWindow -NoQuestion
            Invoke-TestStartup -Gui $gui | Should -Be 'None'

            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Collapsed'
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly
        }

        It 'starts the check without a question when both switches are given' {
            $gui = New-TestWindow -NoQuestion -RunCheck
            Invoke-TestStartup -Gui $gui | Should -Be 'Check'
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly
        }
    }

    Context 'the answer' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Save-AppSetting { $true }
        }

        BeforeEach {
            $gui = New-TestWindow
            Invoke-TestStartup -Gui $gui | Out-Null
        }

        It '"No" starts the check in this window with standard rights' {
            Mock -ModuleName HelpdeskToolkit Invoke-ElevatedRestart { $true }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowElevationChoice -Gui $Gui } | Should -BeTrue

            $gui.Controls.StartupOverlay.Visibility | Should -Be 'Collapsed'
            $gui.Controls.MainLayout.IsEnabled | Should -BeTrue
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-ElevatedRestart -Times 0 -Exactly
        }

        It '"Yes" restarts with administrator rights and tells the new window to run the check' {
            Mock -ModuleName HelpdeskToolkit Invoke-ElevatedRestart { $true }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowElevationChoice -Gui $Gui -Elevate } | Should -BeFalse

            Should -Invoke -ModuleName HelpdeskToolkit Invoke-ElevatedRestart -Times 1 -Exactly -ParameterFilter { $RunCheck }
            # The check runs in the new window, not in this one.
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly
        }

        It 'runs the check with standard rights when the confirmation of Windows is declined' {
            Mock -ModuleName HelpdeskToolkit Invoke-ElevatedRestart { $false }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowElevationChoice -Gui $Gui -Elevate } | Should -BeTrue

            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly
            $gui.Controls.StatusText.Text | Should -Be 'Administrator rights were not granted; the check runs with standard rights.'
            $gui.Controls.MainLayout.IsEnabled | Should -BeTrue
        }

        It 'does not remember the answer unless the box is ticked' {
            Mock -ModuleName HelpdeskToolkit Invoke-ElevatedRestart { $true }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowElevationChoice -Gui $Gui } | Out-Null

            $gui.Settings.StartupElevation | Should -Be 'Ask'
            Should -Invoke -ModuleName HelpdeskToolkit Save-AppSetting -Times 0 -Exactly
        }

        It 'remembers "<Answer>" as "<Expected>" when the box is ticked' -ForEach @(
            @{ Answer = 'No'; Elevate = $false; Expected = 'Never' }
            @{ Answer = 'Yes'; Elevate = $true; Expected = 'Always' }
        ) {
            Mock -ModuleName HelpdeskToolkit Invoke-ElevatedRestart { $true }
            $gui.Controls.StartupRememberBox.IsChecked = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Elevate = $Elevate } { Invoke-WindowElevationChoice -Gui $Gui -Elevate:$Elevate } | Out-Null

            $gui.Settings.StartupElevation | Should -Be $Expected
            Should -Invoke -ModuleName HelpdeskToolkit Save-AppSetting -Times 1 -Exactly -ParameterFilter { $Setting.StartupElevation -eq $Expected }
        }
    }

    Context 'the keyboard' {
        BeforeEach {
            $gui = New-TestWindow
            $script:answers = @()
            $gui.Controls.StartupYesButton.Add_Click({ $script:answers += 'Yes' })
            $gui.Controls.StartupNoButton.Add_Click({ $script:answers += 'No' })
            $script:runs = 0
            $gui.Controls.RunButton.Add_Click({ $script:runs++ })
        }

        It 'answers "Yes" with Enter and "No" with Esc while the question is open' {
            $gui.Controls.StartupOverlay.Visibility = 'Visible'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Return' } | Should -BeTrue
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Escape' } | Should -BeTrue
            $answers | Should -Be @('Yes', 'No')
        }

        It 'has no other shortcut while the question is open' {
            $gui.Controls.StartupOverlay.Visibility = 'Visible'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'F5' } | Should -BeFalse
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'M' -Control } | Should -BeFalse
            $runs | Should -Be 0
        }

        It 'leaves Enter alone once the question is answered' {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Return' } | Should -BeFalse
            $answers.Count | Should -Be 0
        }
    }
}

Describe 'Invoke-ElevatedRestart -RunCheck' -Skip:(-not $isSta) {
    It 'tells the elevated copy to run the check at once' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-ElevatedRestart -Gui $Gui -RunCheck } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter {
            $Verb -eq 'RunAs' -and ($ArgumentList -join ' ') -match ' -RunCheck\b'
        }
    }

    It 'starts the elevated copy without that wish when it is not asked for' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-ElevatedRestart -Gui $Gui } | Out-Null

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -notmatch 'RunCheck' }
    }
}
