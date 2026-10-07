# Tests for the programs that start with Windows: how they are found, how the tool reads
# whether each one is switched on, and how a click in the window switches one off or on.
#
# The real registry and the real Startup folders are never touched. Get-StartupSource is
# replaced, so everything is read from and written to the registry Pester sets up for a
# test (TestRegistry:) and a folder in the test drive; nobody is asked, and no check is
# started.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'

    # The switch as Windows writes it: the first byte says on (2) or off (3).
    function New-TestSwitch {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds an array of bytes.')]
        param([int]$First)
        [byte[]](@($First, 0, 0, 0) + @(0) * 8)
    }

    # A registry and a folder of the test, laid out like the places Windows reads.
    function Initialize-TestStartup {
        $folder = Join-Path -Path $TestDrive -ChildPath ('Startup-{0}' -f [guid]::NewGuid().ToString('N'))
        [void](New-Item -Path $folder -ItemType Directory -Force)
        $root = 'TestRegistry:\{0}' -f [guid]::NewGuid().ToString('N')
        foreach ($key in 'UserRun', 'MachineRun', 'MachineRun32', 'UserApproved\Run', 'UserApproved\StartupFolder', 'MachineApproved\Run', 'MachineApproved\Run32') {
            [void](New-Item -Path "$root\$key" -Force)
        }
        @{ Root = $root; Folder = $folder }
    }
}

Describe 'Get-StartupSource' {
    It 'names the Run keys of the user and of the computer, the one of 32-bit programs and both Startup folders' {
        $sources = @(InModuleScope HelpdeskToolkit { Get-StartupSource })
        $sources.Count | Should -Be 5
        @($sources | ForEach-Object { '{0} {1}' -f $_.Scope, $_.Source }) | Should -Be @('User Run', 'Machine Run', 'Machine Run32', 'User StartupFolder', 'Machine StartupFolder')
        $sources[0].Path | Should -Be 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $sources[2].Path | Should -BeLike 'HKLM:\Software\WOW6432Node\*\Run'
        $sources[3].Folder | Should -Be ([Environment]::GetFolderPath('Startup'))
    }

    It 'keeps the switches of the user where the user can write and those of the computer where only administrators can' {
        foreach ($source in InModuleScope HelpdeskToolkit { Get-StartupSource }) {
            $hive = if ($source.Scope -eq 'User') { 'HKCU:' } else { 'HKLM:' }
            $source.Approved | Should -BeLike "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\*"
        }
    }
}

Describe 'Get-StartupProgram' {
    BeforeAll {
        $place = Initialize-TestStartup
        $root = $place.Root

        New-ItemProperty -Path "$root\UserRun" -Name 'Discord' -Value '"C:\Contoso\Discord\Update.exe" --start' | Out-Null
        New-ItemProperty -Path "$root\UserRun" -Name 'EADM' -Value '"C:\Contoso\EA\Launcher.exe"' | Out-Null
        New-ItemProperty -Path "$root\UserRun" -Name 'BrowserAutoLaunch_0123456789ABCDEF0123456789ABCDEF' -Value 'browser.exe --no-startup-window' | Out-Null
        New-ItemProperty -Path "$root\MachineRun" -Name 'SecurityHealth' -Value 'health.exe' | Out-Null
        New-ItemProperty -Path "$root\MachineRun32" -Name 'Lightshot' -Value 'lightshot.exe' | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $place.Folder -ChildPath 'Rainmeter.lnk') -Value 'shortcut'
        Set-Content -LiteralPath (Join-Path -Path $place.Folder -ChildPath 'Notes.lnk') -Value 'shortcut'
        Set-Content -LiteralPath (Join-Path -Path $place.Folder -ChildPath 'desktop.ini') -Value 'settings of the folder'

        # What Task Manager has written so far
        New-ItemProperty -Path "$root\UserApproved\Run" -Name 'Discord' -Value (New-TestSwitch 2) -PropertyType Binary | Out-Null
        New-ItemProperty -Path "$root\UserApproved\Run" -Name 'EADM' -Value (New-TestSwitch 3) -PropertyType Binary | Out-Null
        New-ItemProperty -Path "$root\UserApproved\StartupFolder" -Name 'Rainmeter.lnk' -Value (New-TestSwitch 3) -PropertyType Binary | Out-Null
        New-ItemProperty -Path "$root\MachineApproved\Run" -Name 'SecurityHealth' -Value (New-TestSwitch 6) -PropertyType Binary | Out-Null
        New-ItemProperty -Path "$root\MachineApproved\Run32" -Name 'Lightshot' -Value (New-TestSwitch 7) -PropertyType Binary | Out-Null

        $sources = @(
            @{ Scope = 'User'; Source = 'Run'; Path = "$root\UserRun"; Folder = ''; Approved = "$root\UserApproved\Run" }
            @{ Scope = 'Machine'; Source = 'Run'; Path = "$root\MachineRun"; Folder = ''; Approved = "$root\MachineApproved\Run" }
            @{ Scope = 'Machine'; Source = 'Run32'; Path = "$root\MachineRun32"; Folder = ''; Approved = "$root\MachineApproved\Run32" }
            @{ Scope = 'User'; Source = 'StartupFolder'; Path = ''; Folder = $place.Folder; Approved = "$root\UserApproved\StartupFolder" }
            # A place that does not exist on this computer
            @{ Scope = 'Machine'; Source = 'StartupFolder'; Path = ''; Folder = (Join-Path -Path $TestDrive -ChildPath 'No such folder'); Approved = "$root\MachineApproved\StartupFolder" }
        )
        Mock -ModuleName HelpdeskToolkit Get-StartupSource { $sources }.GetNewClosure()
        $programs = @(InModuleScope HelpdeskToolkit { Get-StartupProgram })
    }

    It 'finds the programs of every place, and no settings file of a folder' {
        @($programs.Name | Sort-Object) | Should -Be @('BrowserAutoLaunch', 'Discord', 'EADM', 'Lightshot', 'Notes', 'Rainmeter', 'SecurityHealth')
    }

    It 'says of <Name> that it is <State>: <Why>' -ForEach @(
        @{ Name = 'Discord'; Enabled = $true; State = 'on'; Why = 'its switch starts with 02' }
        @{ Name = 'EADM'; Enabled = $false; State = 'off'; Why = 'its switch starts with 03' }
        @{ Name = 'BrowserAutoLaunch'; Enabled = $true; State = 'on'; Why = 'it has no switch yet' }
        @{ Name = 'SecurityHealth'; Enabled = $true; State = 'on'; Why = 'its switch starts with 06, an even number' }
        @{ Name = 'Lightshot'; Enabled = $false; State = 'off'; Why = 'its switch starts with 07, an odd number' }
        @{ Name = 'Rainmeter'; Enabled = $false; State = 'off'; Why = 'the switch of its shortcut starts with 03' }
        @{ Name = 'Notes'; Enabled = $true; State = 'on'; Why = 'its shortcut has no switch yet' }
    ) {
        ($programs | Where-Object Name -eq $Name).Enabled | Should -Be $Enabled
    }

    It 'keeps the real name of an entry next to the name that is shown, because the switch is filed under the real one' {
        $browser = $programs | Where-Object Name -eq 'BrowserAutoLaunch'
        $browser.Entry | Should -Be 'BrowserAutoLaunch_0123456789ABCDEF0123456789ABCDEF'
        ($programs | Where-Object Name -eq 'Rainmeter').Entry | Should -Be 'Rainmeter.lnk'
    }

    It 'says whose each program is and where its switch lies' {
        $discord = $programs | Where-Object Name -eq 'Discord'
        $discord.Scope | Should -Be 'User'
        $discord.Source | Should -Be 'Run'
        $discord.Approved | Should -Be "$root\UserApproved\Run"
        $discord.Command | Should -Be '"C:\Contoso\Discord\Update.exe" --start'
        ($programs | Where-Object Name -eq 'Lightshot').Scope | Should -Be 'Machine'
        ($programs | Where-Object Name -eq 'Lightshot').Source | Should -Be 'Run32'
    }

    It 'returns nothing, and does not fail, where no place exists' {
        Mock -ModuleName HelpdeskToolkit Get-StartupSource {
            @{ Scope = 'User'; Source = 'Run'; Path = 'TestRegistry:\No such key'; Folder = ''; Approved = 'TestRegistry:\No such switches' }
        }
        { InModuleScope HelpdeskToolkit { Get-StartupProgram } } | Should -Not -Throw
        @(InModuleScope HelpdeskToolkit { Get-StartupProgram }).Count | Should -Be 0
    }
}

Describe 'Set-StartupProgramState' {
    BeforeEach {
        $place = Initialize-TestStartup
        $approved = "$($place.Root)\UserApproved\Run"
        $program = [PSCustomObject]@{ Name = 'Discord'; Entry = 'Discord'; Scope = 'User'; Source = 'Run'; Command = 'discord.exe'; Enabled = $true; Approved = $approved }
    }

    It 'switches a program off with the value Task Manager writes: 03 and the moment it happened' {
        $before = [datetime]::UtcNow.AddSeconds(-2)
        InModuleScope HelpdeskToolkit -Parameters @{ Program = $program } { Set-StartupProgramState -Program $Program -Enabled $false -Confirm:$false }

        $value = (Get-Item -LiteralPath $approved).GetValue('Discord')
        $value.Count | Should -Be 12
        $value[0..3] | Should -Be @(3, 0, 0, 0)
        $when = [datetime]::FromFileTimeUtc([System.BitConverter]::ToInt64($value, 4))
        $when | Should -BeGreaterThan $before
        $when | Should -BeLessThan ([datetime]::UtcNow.AddSeconds(2))
        (Get-Item -LiteralPath $approved).GetValueKind('Discord') | Should -Be 'Binary'
    }

    It 'switches a program on with 02 and nothing else' {
        New-ItemProperty -Path $approved -Name 'Discord' -Value (New-TestSwitch 3) -PropertyType Binary | Out-Null
        InModuleScope HelpdeskToolkit -Parameters @{ Program = $program } { Set-StartupProgramState -Program $Program -Enabled $true -Confirm:$false }

        (Get-Item -LiteralPath $approved).GetValue('Discord') | Should -Be @(2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    It 'creates the place of the switches when Windows has not made it yet' {
        $program.Approved = "$($place.Root)\NewApproved\Run"
        InModuleScope HelpdeskToolkit -Parameters @{ Program = $program } { Set-StartupProgramState -Program $Program -Enabled $false -Confirm:$false }
        (Get-Item -LiteralPath $program.Approved).GetValue('Discord')[0] | Should -Be 3
    }

    It 'files the switch under the real name of the entry' {
        $program.Name = 'BrowserAutoLaunch'
        $program.Entry = 'BrowserAutoLaunch_0123456789ABCDEF0123456789ABCDEF'
        InModuleScope HelpdeskToolkit -Parameters @{ Program = $program } { Set-StartupProgramState -Program $Program -Enabled $false -Confirm:$false }
        (Get-Item -LiteralPath $approved).GetValueNames() | Should -Be @('BrowserAutoLaunch_0123456789ABCDEF0123456789ABCDEF')
    }

    It 'leaves the entry of the program and the other switches alone' {
        New-ItemProperty -Path "$($place.Root)\UserRun" -Name 'Discord' -Value 'discord.exe' | Out-Null
        New-ItemProperty -Path $approved -Name 'Steam' -Value (New-TestSwitch 2) -PropertyType Binary | Out-Null
        InModuleScope HelpdeskToolkit -Parameters @{ Program = $program } { Set-StartupProgramState -Program $Program -Enabled $false -Confirm:$false }

        (Get-Item -LiteralPath "$($place.Root)\UserRun").GetValue('Discord') | Should -Be 'discord.exe'
        (Get-Item -LiteralPath $approved).GetValue('Steam')[0] | Should -Be 2
    }

    It 'changes nothing with -WhatIf' {
        InModuleScope HelpdeskToolkit -Parameters @{ Program = $program } { Set-StartupProgramState -Program $Program -Enabled $false -WhatIf }
        (Get-Item -LiteralPath $approved).GetValueNames() | Should -BeNullOrEmpty
    }

    It 'is what Get-StartupProgram reads back' {
        $root = $place.Root
        New-ItemProperty -Path "$root\UserRun" -Name 'Discord' -Value 'discord.exe' | Out-Null
        $sources = @(@{ Scope = 'User'; Source = 'Run'; Path = "$root\UserRun"; Folder = ''; Approved = $approved })
        Mock -ModuleName HelpdeskToolkit Get-StartupSource { $sources }.GetNewClosure()

        (InModuleScope HelpdeskToolkit { Get-StartupProgram }).Enabled | Should -BeTrue
        InModuleScope HelpdeskToolkit { Set-StartupProgramState -Program (Get-StartupProgram) -Enabled $false -Confirm:$false }
        (InModuleScope HelpdeskToolkit { Get-StartupProgram }).Enabled | Should -BeFalse
        InModuleScope HelpdeskToolkit { Set-StartupProgramState -Program (Get-StartupProgram) -Enabled $true -Confirm:$false }
        (InModuleScope HelpdeskToolkit { Get-StartupProgram }).Enabled | Should -BeTrue
    }
}

Describe 'A click on a startup program: Switch-WindowStartupProgram' -Skip:(-not $isSta) {
    BeforeAll {
        # Whatever a test forgets to say: nobody is asked, nothing is written, no check starts.
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $false }
        Mock -ModuleName HelpdeskToolkit Set-StartupProgramState { }
        Mock -ModuleName HelpdeskToolkit Invoke-WindowCheck { }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        Mock -ModuleName HelpdeskToolkit Get-StartupProgram {
            [PSCustomObject]@{ Name = 'Discord'; Entry = 'Discord'; Scope = 'User'; Source = 'Run'; Command = 'discord.exe'; Enabled = $true; Approved = 'TestRegistry:\Unused' }
            [PSCustomObject]@{ Name = 'EADM'; Entry = 'EADM'; Scope = 'User'; Source = 'Run'; Command = 'ea.exe'; Enabled = $false; Approved = 'TestRegistry:\Unused' }
            [PSCustomObject]@{ Name = 'Lightshot'; Entry = 'Lightshot'; Scope = 'Machine'; Source = 'Run32'; Command = 'lightshot.exe'; Enabled = $true; Approved = 'TestRegistry:\Unused' }
        }
    }

    BeforeEach {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Report = New-TestReport -Result @(New-TestResult -Category 'System' -Check 'Startup programs' -Status OK -Value '2 programs start with Windows')
    }

    It 'asks first, naming the program and saying what the switch does' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Discord' } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 1 -Exactly -Scope It -ParameterFilter {
            $Title -eq 'Startup programs' -and $Text -like 'Stop "Discord" from starting with Windows?*stays installed*Task Manager*'
        }
    }

    It 'changes nothing when the answer is No' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Discord' } | Should -BeFalse

        Should -Invoke -ModuleName HelpdeskToolkit Set-StartupProgramState -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -Be 'Nothing was changed.'
    }

    It 'switches a program off when the answer is Yes, says so and checks again' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Discord' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Set-StartupProgramState -Times 1 -Exactly -Scope It -ParameterFilter { $Program.Name -eq 'Discord' -and $Enabled -eq $false }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly -Scope It -ParameterFilter { $Background }
        $gui.Controls.StatusText.Text | Should -Be '"Discord" no longer starts with Windows. The list is being updated.'
    }

    It 'offers to switch a program on again that is off' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'EADM' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 1 -Exactly -Scope It -ParameterFilter { $Text -like 'Let "EADM" start with Windows again?*' }
        Should -Invoke -ModuleName HelpdeskToolkit Set-StartupProgramState -Times 1 -Exactly -Scope It -ParameterFilter { $Program.Name -eq 'EADM' -and $Enabled -eq $true }
        $gui.Controls.StatusText.Text | Should -Be '"EADM" starts with Windows again. The list is being updated.'
    }

    It 'does not ask and changes nothing for a program of every user while the window has standard rights' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Lightshot' } | Should -BeFalse

        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Set-StartupProgramState -Times 0 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -BeLike '"Lightshot" starts for every user of this computer, so switching it needs administrator rights.*'
    }

    It 'switches a program of every user with administrator rights' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Lightshot' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Set-StartupProgramState -Times 1 -Exactly -Scope It -ParameterFilter { $Program.Name -eq 'Lightshot' -and $Enabled -eq $false }
    }

    It 'changes nothing for a program that is not a startup program of this computer, as in a report of another one' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Contoso Agent' } | Should -BeFalse

        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Set-StartupProgramState -Times 0 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -BeLike '"Contoso Agent" is not among the startup programs of this computer.*'
    }

    It 'says why when the switch cannot be written, and starts no check' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Set-StartupProgramState { throw 'Requested registry access is not allowed.' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Discord' } | Should -BeFalse

        $gui.Controls.StatusText.Text | Should -Be 'The startup of "Discord" could not be switched: Requested registry access is not allowed.'
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly -Scope It
    }

    It 'starts no second check while one is running' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        $gui.Worker = 'a check is already running'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Discord' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly -Scope It
    }

    It 'writes down what it switched' {
        $log = InModuleScope HelpdeskToolkit { Get-AppDataPath -ChildPath 'app.log' }
        if (Test-Path -LiteralPath $log) {
            Remove-Item -LiteralPath $log -Force
        }
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowStartupProgram -Gui $Gui -Name 'Discord' } | Should -BeTrue
        (Get-Content -LiteralPath $log) -join "`n" | Should -Match '\[Info\] The startup of "Discord" was switched off \(User, Run, entry "Discord"\)'
    }
}

Describe 'The startup programs on a result card' {
    BeforeAll {
        $result = New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '2 programs start with Windows, 1 more turned off' `
            -Recommendation 'Turn some off.' -Details @('Discord', 'Steam', 'EADM (turned off)')
        $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $result } { $Result | ConvertTo-WindowItem }
    }

    It 'makes every program a line that can be clicked' {
        @($item.MoreItems).Count | Should -Be 3
        $item.MoreItems.Link | Should -Be @('Yes', 'Yes', 'Yes')
        $item.MoreItems.Action | Should -Be @('Startup', 'Startup', 'Startup')
        # No address: the click does not leave the application.
        $item.MoreItems.Url | Should -Be @('', '', '')
    }

    It 'hands the click the name of the program, without the mark of one that is off' {
        $item.MoreItems.Target | Should -Be @('Discord', 'Steam', 'EADM')
        $item.MoreItems.Text | Should -Be @('Discord', 'Steam', 'EADM (turned off)')
    }

    It 'says in the tip what a click does' {
        $item.MoreItems[0].Tip | Should -Be 'Click to stop this program from starting with Windows'
        $item.MoreItems[2].Tip | Should -Be 'Click to let this program start with Windows again'
    }

    It 'announces the list as the whole list of switches' {
        $item.MoreHeader | Should -Be 'Show all 3: click a program to switch it off or on'
    }

    It 'leaves the lines of every other result as they were' {
        $other = New-TestResult -Category 'System' -Check 'Scheduled tasks' -Status Info -Value '2 tasks' -Details @('Task A', 'Task B (turned off)')
        $otherItem = InModuleScope HelpdeskToolkit -Parameters @{ Result = $other } { $Result | ConvertTo-WindowItem }
        $otherItem.MoreItems.Link | Should -Be @('', '')
        $otherItem.MoreItems.Action | Should -Be @('', '')
        $otherItem.MoreHeader | Should -Be 'Show 2 more'
    }

    It 'gives an event line its tip too, now that the tip comes with the line' {
        $events = New-TestResult -Category 'Event Log' -Check 'System log - errors' -Status Warning -Value '3 in the last 7 days' -Details @('Service Control Manager 7031 (3)')
        $eventItem = InModuleScope HelpdeskToolkit -Parameters @{ Result = $events } { $Result | ConvertTo-WindowItem }
        $eventItem.MoreItems[0].Link | Should -Be 'Yes'
        $eventItem.MoreItems[0].Action | Should -Be ''
        $eventItem.MoreItems[0].Tip | Should -Be 'Look up what this event means and how it is fixed'
    }
}

Describe 'A click on a line of a card' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Switch-WindowStartupProgram { $true }
        Mock -ModuleName HelpdeskToolkit Open-WindowHelpLink { $true }
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
    }

    It 'switches the startup program of the line' {
        $button = New-Object -TypeName System.Windows.Controls.Button
        $button.DataContext = [PSCustomObject]@{ Text = 'Discord'; Url = ''; Action = 'Startup'; Target = 'Discord'; Tip = ''; Link = 'Yes' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

        Should -Invoke -ModuleName HelpdeskToolkit Switch-WindowStartupProgram -Times 1 -Exactly -Scope It -ParameterFilter { $Name -eq 'Discord' }
        Should -Invoke -ModuleName HelpdeskToolkit Open-WindowHelpLink -Times 0 -Exactly -Scope It
    }

    It 'still opens the address of an event line' {
        $button = New-Object -TypeName System.Windows.Controls.Button
        $button.DataContext = [PSCustomObject]@{ Text = 'Event 41'; Url = 'https://example.test/'; Action = ''; Target = ''; Tip = ''; Link = 'Yes' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

        Should -Invoke -ModuleName HelpdeskToolkit Open-WindowHelpLink -Times 1 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Switch-WindowStartupProgram -Times 0 -Exactly -Scope It
    }
}

Describe 'The layout of a line of the details' {
    BeforeAll {
        $xaml = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml'))
        $template = [regex]::Match($xaml, '(?s)<DataTemplate x:Key="MoreLine">.*?</DataTemplate>').Value
    }

    It 'shows a line as a link when the line says it can be clicked, whatever a click does' {
        $template | Should -Not -BeNullOrEmpty
        ([regex]::Matches($template, 'Binding="\{Binding Link\}"')).Count | Should -Be 2
        $template | Should -Not -Match 'Binding="\{Binding Url\}"'
    }

    It 'takes the tip from the line' {
        $template | Should -Match 'ToolTip="\{Binding Tip\}"'
    }
}

Describe 'The texts of the startup programs' {
    It 'are translated into Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'Show all {0}: click a program to switch it off or on', 'turned off', 'Nothing was changed.',
            'Click to stop this program from starting with Windows', 'Click to let this program start with Windows again',
            'Stop "{0}" from starting with Windows?', 'Let "{0}" start with Windows again?',
            '"{0}" no longer starts with Windows. The list is being updated.', '"{0}" starts with Windows again. The list is being updated.',
            'The startup of "{0}" could not be switched: {1}') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
    }

    It 'translates the value of the check' {
        InModuleScope HelpdeskToolkit {
            $script:Language = 'hr'
            $script:Translations = $null
            try {
                # The dots stand for Croatian letters, which this file does without.
                Get-LocalizedText '20 programs start with Windows, 13 more turned off' | Should -Match '^S Windowsima se pokre.e programa: 20, isklju.eno jo.: 13$'
                Get-LocalizedText '1 program starts with Windows' | Should -Match '^S Windowsima se pokre.e programa: 1$'
            }
            finally {
                $script:Language = 'en'
                $script:Translations = $null
            }
        }
    }
}
