# Tests for running in the background: the window that hides next to the clock instead
# of closing, the one running copy, and starting with Windows. The application folder
# and the Startup folder are redirected into the test drive, so nothing of the person
# running the tests is touched.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $appData = Join-Path -Path $TestDrive -ChildPath 'AppData'
    $startup = Join-Path -Path $TestDrive -ChildPath 'Startup'
    InModuleScope HelpdeskToolkit -Parameters @{ AppData = $appData; Startup = $startup } {
        $script:AppDataRoot = $AppData
        $script:AutoStartFolder = $Startup
    }

    function Get-TestWindow {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }

    # Stands in for the icon next to the clock and counts its notifications.
    function Get-TestTrayIcon {
        $icon = [PSCustomObject]@{ Shown = 0; LastText = '' }
        $icon | Add-Member -MemberType ScriptMethod -Name ShowBalloonTip -Value {
            # Called like the real icon: duration, title, text, kind
            $this.Shown++
            $this.LastText = $args[2]
        }
        $icon
    }
}

AfterAll {
    InModuleScope HelpdeskToolkit {
        $script:AppDataRoot = $null
        $script:AutoStartFolder = $null
    }
}

Describe 'The setting KeepInBackground' {
    It 'is off by default' {
        InModuleScope HelpdeskToolkit { (Get-AppSetting).KeepInBackground } | Should -BeFalse
    }

    It 'is remembered' {
        InModuleScope HelpdeskToolkit {
            $settings = Get-AppSetting
            $settings.KeepInBackground = $true
            Save-AppSetting -Setting $settings | Should -BeTrue
            (Get-AppSetting).KeepInBackground | Should -BeTrue
        }
    }

    It 'is off when the file holds something that is not "true"' {
        $file = Join-Path -Path $appData -ChildPath 'settings.json'
        Set-Content -LiteralPath $file -Value '{ "KeepInBackground": "maybe" }' -Encoding UTF8
        InModuleScope HelpdeskToolkit { (Get-AppSetting).KeepInBackground } | Should -BeFalse
    }
}

Describe 'Lock-AppInstance' {
    It 'lets the first copy in and keeps a second one out until the first is gone' {
        InModuleScope HelpdeskToolkit {
            $first = Lock-AppInstance
            try {
                $first | Should -BeOfType [System.IO.FileStream]
                Test-Path -LiteralPath (Get-AppDataPath -ChildPath 'instance.lock') | Should -BeTrue

                Lock-AppInstance | Should -BeNullOrEmpty
            }
            finally {
                $first.Dispose()
            }

            # The file goes with the copy that held it.
            Test-Path -LiteralPath (Get-AppDataPath -ChildPath 'instance.lock') | Should -BeFalse
            $next = Lock-AppInstance
            try {
                $next | Should -BeOfType [System.IO.FileStream]
            }
            finally {
                $next.Dispose()
            }
        }
    }

    It 'lets the application start when the file cannot be opened for another reason' {
        InModuleScope HelpdeskToolkit {
            # A folder with the name of the file: opening it fails, but not because it is in use.
            $blocked = Join-Path -Path $TestDrive -ChildPath 'Blocked'
            New-Item -Path (Join-Path -Path $blocked -ChildPath 'instance.lock') -ItemType Directory -Force | Out-Null
            $previous = $script:AppDataRoot
            $script:AppDataRoot = $blocked
            try {
                $stream = Lock-AppInstance
                $stream | Should -BeOfType [System.IO.MemoryStream]
            }
            finally {
                $script:AppDataRoot = $previous
            }
        }
    }
}

Describe 'A second start of the application' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Show-WindowFromTray { }
    }

    It 'has nothing to do while nobody asked' {
        $gui = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-AppShowRequest -Gui $Gui } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowFromTray -Times 0 -Exactly -Scope It
    }

    It 'makes the running copy show its window, once' {
        $gui = Get-TestWindow
        InModuleScope HelpdeskToolkit { Send-AppShowRequest } | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $appData -ChildPath 'show.request') | Should -BeTrue

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-AppShowRequest -Gui $Gui } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowFromTray -Times 1 -Exactly -Scope It -ParameterFilter { $Force }

        # The request is used up.
        Test-Path -LiteralPath (Join-Path -Path $appData -ChildPath 'show.request') | Should -BeFalse
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-AppShowRequest -Gui $Gui } | Should -BeFalse
    }

    It 'is prevented by Show-PCHealthCheck, which asks the first copy and returns' {
        Mock -ModuleName HelpdeskToolkit Lock-AppInstance { }
        Mock -ModuleName HelpdeskToolkit Send-AppShowRequest { $true }
        Mock -ModuleName HelpdeskToolkit New-HealthCheckWindow { throw 'A second window must not be built.' }

        Show-PCHealthCheck | Should -BeNullOrEmpty
        Should -Invoke -ModuleName HelpdeskToolkit Send-AppShowRequest -Times 1 -Exactly -Scope It
    }

    It 'asks for nothing when the second start is Windows starting the application' {
        Mock -ModuleName HelpdeskToolkit Lock-AppInstance { }
        Mock -ModuleName HelpdeskToolkit Send-AppShowRequest { $true }
        Mock -ModuleName HelpdeskToolkit New-HealthCheckWindow { throw 'A second window must not be built.' }

        Show-PCHealthCheck -Background | Should -BeNullOrEmpty
        Should -Invoke -ModuleName HelpdeskToolkit Send-AppShowRequest -Times 0 -Exactly -Scope It
    }
}

Describe 'Starting with Windows' {
    It 'is off while there is no shortcut' {
        InModuleScope HelpdeskToolkit { Test-AppAutoStart } | Should -BeFalse
        InModuleScope HelpdeskToolkit { Get-AutoStartPath } | Should -Be (Join-Path -Path $startup -ChildPath 'HelpdeskToolkit.lnk')
    }

    It 'uses the Startup folder of the user when nothing replaces it' {
        InModuleScope HelpdeskToolkit {
            $previous = $script:AutoStartFolder
            $script:AutoStartFolder = $null
            try {
                Get-AutoStartPath | Should -Be (Join-Path -Path ([Environment]::GetFolderPath('Startup')) -ChildPath 'HelpdeskToolkit.lnk')
            }
            finally {
                $script:AutoStartFolder = $previous
            }
        }
    }

    It 'writes a shortcut that starts the application in the background, without a console window' {
        InModuleScope HelpdeskToolkit { Enable-AppAutoStart } | Should -BeTrue
        InModuleScope HelpdeskToolkit { Test-AppAutoStart } | Should -BeTrue

        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path -Path $startup -ChildPath 'HelpdeskToolkit.lnk'))
        $shortcut.TargetPath | Should -BeLike '*\System32\conhost.exe'
        $shortcut.Arguments | Should -BeLike '--headless "*\WindowsPowerShell\v1.0\powershell.exe" *'
        $shortcut.Arguments | Should -BeLike '* -Background*'
        $shortcut.Arguments | Should -Match 'Start-HelpdeskToolkit\.ps1|Show-PCHealthCheck'
        $shortcut.IconLocation | Should -BeLike '*HelpdeskToolkit.ico*'
    }

    It 'removes the shortcut again, and does not mind when there is none' {
        InModuleScope HelpdeskToolkit { Disable-AppAutoStart } | Should -BeTrue
        InModuleScope HelpdeskToolkit { Test-AppAutoStart } | Should -BeFalse
        InModuleScope HelpdeskToolkit { Disable-AppAutoStart } | Should -BeTrue
    }

    It 'passes -Background on to the window' {
        InModuleScope HelpdeskToolkit { Get-LauncherArgument -Background } | Should -BeLike '* -Background*'
        InModuleScope HelpdeskToolkit { Get-LauncherArgument } | Should -Not -BeLike '*-Background*'
    }

    It 'is removed by the uninstaller' {
        $installer = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath '..\installer\HelpdeskToolkit.iss'))
        $installer | Should -Match '\[UninstallDelete\]\s+Type: files; Name: "\{userstartup\}\\HelpdeskToolkit\.lnk"'
    }
}

Describe 'Hide-WindowToTray' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Enable-WindowTrayIcon {
            if (-not $Gui.TrayIcon) { $Gui.TrayIcon = $Gui.TestIcon }
        }
    }

    It 'hides the window, stops the Live monitor and says once where the application went' {
        $gui = Get-TestWindow
        $gui.TestIcon = Get-TestTrayIcon

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Hide-WindowToTray -Gui $Gui }
        $gui.Hidden | Should -BeTrue
        $gui.Window.IsVisible | Should -BeFalse
        $gui.TrayIcon.Shown | Should -Be 1
        $gui.TrayIcon.LastText | Should -Be 'HelpdeskToolkit keeps running here. Click the icon to open it; right-click it to exit.'
        Should -Invoke -ModuleName HelpdeskToolkit Disable-WindowMonitor -Times 1 -Exactly -Scope It -ParameterFilter { -not $Stop }

        # The second time in the same run nothing is announced.
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Hide-WindowToTray -Gui $Gui }
        $gui.TrayIcon.Shown | Should -Be 1
    }

    It 'says nothing when the application starts in the background' {
        $gui = Get-TestWindow
        $gui.TestIcon = Get-TestTrayIcon

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Hide-WindowToTray -Gui $Gui -Quiet }
        $gui.Hidden | Should -BeTrue
        $gui.TrayIcon.Shown | Should -Be 0
    }
}

Describe 'Show-WindowFromTray' -Skip:(-not $isSta) {
    It 'leaves a window alone that is not hidden' {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        $gui = Get-TestWindow

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowFromTray -Gui $Gui }
        $gui.Window.IsVisible | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Enable-WindowMonitor -Times 0 -Exactly -Scope It
    }
}

Describe 'Exit-WindowApplication' -Skip:(-not $isSta) {
    It 'marks the window as closing for good and closes it' {
        $gui = Get-TestWindow
        $script:closed = $false
        $gui.Window.Add_Closed({ $script:closed = $true })

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Exit-WindowApplication -Gui $Gui }
        $gui.Exiting | Should -BeTrue
        $closed | Should -BeTrue
    }
}

Describe 'The restarts of the application' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Exit-WindowApplication { }
    }

    It 'frees the place of the one running window for the new copy and closes for good' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        $gui = Get-TestWindow
        $gui.InstanceLock = New-Object -TypeName System.IO.MemoryStream

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-AppRestart -Gui $Gui } | Should -BeTrue
        $gui.InstanceLock | Should -BeNullOrEmpty
        Should -Invoke -ModuleName HelpdeskToolkit Exit-WindowApplication -Times 1 -Exactly -Scope It
    }

    It 'takes the place back when the new copy does not start' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'The operation was canceled by the user.' }
        Mock -ModuleName HelpdeskToolkit Lock-AppInstance { New-Object -TypeName System.IO.MemoryStream }
        $gui = Get-TestWindow
        $gui.InstanceLock = New-Object -TypeName System.IO.MemoryStream

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-ElevatedRestart -Gui $Gui } | Should -BeFalse
        $gui.InstanceLock | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName HelpdeskToolkit Lock-AppInstance -Times 1 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Exit-WindowApplication -Times 0 -Exactly -Scope It
    }
}

Describe 'The Settings page' -Skip:(-not $isSta) {
    It 'shows whether the application stays in the background and starts with Windows' {
        Mock -ModuleName HelpdeskToolkit Test-AppAutoStart { $true }
        $gui = Get-TestWindow
        $gui.Settings.KeepInBackground = $true

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowSetting -Gui $Gui }
        $gui.Controls.BackgroundBox.IsChecked | Should -BeTrue
        $gui.Controls.AutoStartBox.IsChecked | Should -BeTrue
    }

    It 'leaves both unticked for an application that does neither' {
        Mock -ModuleName HelpdeskToolkit Test-AppAutoStart { $false }
        $gui = Get-TestWindow

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowSetting -Gui $Gui }
        $gui.Controls.BackgroundBox.IsChecked | Should -BeFalse
        $gui.Controls.AutoStartBox.IsChecked | Should -BeFalse
    }
}

Describe 'The texts of the background mode' {
    It 'are translated into Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'In the background', 'Keep running when the window is closed', 'Start with Windows', 'Open HelpdeskToolkit',
            'Run check now', 'Exit', 'HelpdeskToolkit keeps running here. Click the icon to open it; right-click it to exit.',
            'HelpdeskToolkit now starts with Windows, as an icon next to the clock.', 'HelpdeskToolkit no longer starts with Windows.') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
    }
}
