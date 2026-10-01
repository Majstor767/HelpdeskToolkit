# Tests for the helper functions behind the checks that were added later: folder sizes,
# battery capacity, scheduled tasks, browser extensions, ports, Wi-Fi, power plan, backup.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
}

Describe 'ConvertTo-ListValue' {
    It 'writes out all items when they fit' {
        $list = InModuleScope HelpdeskToolkit { ConvertTo-ListValue -Item 'A', 'B' -Shown 3 }
        $list.Value | Should -Be 'A, B'
        @($list.Details).Count | Should -Be 0
    }

    It 'writes out the first items and returns the rest as details' {
        $list = InModuleScope HelpdeskToolkit { ConvertTo-ListValue -Item 'A', 'B', 'C', 'D' -Shown 2 }
        $list.Value | Should -Be 'A, B and 2 more'
        $list.Details | Should -Be @('C', 'D')
    }

    It 'starts with the number of items and uses the singular for exactly one' {
        InModuleScope HelpdeskToolkit {
            (ConvertTo-ListValue -Item 'A' -Label 'task').Value | Should -Be '1 task: A'
            (ConvertTo-ListValue -Item 'A', 'B' -Label 'task').Value | Should -Be '2 tasks: A, B'
            (ConvertTo-ListValue -Item @() -Label 'task').Value | Should -Be '0 tasks'
        }
    }

    It 'ignores empty entries' {
        (InModuleScope HelpdeskToolkit { ConvertTo-ListValue -Item 'A', '', 'B' -Label 'task' }).Value | Should -Be '2 tasks: A, B'
    }
}

Describe 'Get-LargestFolder' {
    BeforeAll {
        # A small "drive": folders, a large and a small file in the root, and a user
        # profile that lies inside the "Users" folder.
        $drive = Join-Path -Path $TestDrive -ChildPath 'Drive'
        $userProfile = Join-Path -Path $drive -ChildPath 'Users\tester'
        foreach ($folder in 'Big', 'Small', 'Empty', 'Users\tester\Documents', 'Users\tester\Downloads', 'Users\other') {
            New-Item -Path (Join-Path -Path $drive -ChildPath $folder) -ItemType Directory -Force | Out-Null
        }
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'Big\data.bin'), (New-Object byte[] 5000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'Big\more.bin'), (New-Object byte[] 1000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'Small\data.bin'), (New-Object byte[] 300))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'Users\tester\Documents\a.bin'), (New-Object byte[] 2000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'Users\tester\Downloads\b.bin'), (New-Object byte[] 4000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'Users\other\c.bin'), (New-Object byte[] 9000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'pagefile.sys'), (New-Object byte[] 3000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $drive -ChildPath 'note.txt'), (New-Object byte[] 10))

        $previousProfile = $env:USERPROFILE
        $env:USERPROFILE = $userProfile
        $found = @(InModuleScope HelpdeskToolkit -Parameters @{ Path = $drive } { Get-LargestFolder -Path $Path -MinimumFileBytes 1000 })
    }

    AfterAll {
        $env:USERPROFILE = $previousProfile
    }

    It 'returns the folders and the large root files, largest first' {
        $found.Name | Should -Be @('Big', 'Users\tester\Downloads', 'pagefile.sys', 'Users\tester\Documents', 'Small')
        $found.Bytes | Should -Be @(6000, 4000, 3000, 2000, 300)
    }

    It 'lists the folders of the current user one by one instead of the Users folder' {
        $found.Name | Should -Not -Contain 'Users'
        # Profiles of other users are not measured: a standard user may not read them.
        $found.Name | Should -Not -Contain 'Users\other'
    }

    It 'leaves out empty folders and small files in the root' {
        $found.Name | Should -Not -Contain 'Empty'
        $found.Name | Should -Not -Contain 'note.txt'
    }

    It 'marks everything as measured completely when there was enough time' {
        $found.Complete | Sort-Object -Unique | Should -Be $true
    }

    It 'stops when the time for the whole drive is used up' {
        $none = @(InModuleScope HelpdeskToolkit -Parameters @{ Path = $drive } { Get-LargestFolder -Path $Path -BudgetMs 0 -MinimumFileBytes 1000 })
        # Only the root files are known then; no folder was measured.
        $none.Name | Should -Be @('pagefile.sys')
    }

    It 'returns nothing for a drive that does not exist' {
        @(InModuleScope HelpdeskToolkit { Get-LargestFolder -Path 'Q:\does-not-exist\' }).Count | Should -Be 0
    }
}

Describe 'Get-BatteryCapacity' {
    It 'returns the designed and the current capacity, and the charge cycles' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryStaticData' } { [PSCustomObject]@{ DesignedCapacity = 60000 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryFullChargedCapacity' } { [PSCustomObject]@{ FullChargedCapacity = 48000 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryCycleCount' } { [PSCustomObject]@{ CycleCount = 312 } }
        $battery = InModuleScope HelpdeskToolkit { Get-BatteryCapacity }

        $battery.DesignedCapacity | Should -Be 60000
        $battery.FullChargedCapacity | Should -Be 48000
        $battery.CycleCount | Should -Be 312
    }

    It 'returns no cycle count for a battery that does not count them' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryStaticData' } { [PSCustomObject]@{ DesignedCapacity = 60000 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryFullChargedCapacity' } { [PSCustomObject]@{ FullChargedCapacity = 48000 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryCycleCount' } { [PSCustomObject]@{ CycleCount = 0 } }
        (InModuleScope HelpdeskToolkit { Get-BatteryCapacity }).CycleCount | Should -BeNullOrEmpty
    }

    It 'returns nothing on a computer without a battery' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { }
        @(InModuleScope HelpdeskToolkit { Get-BatteryCapacity }).Count | Should -Be 0
    }

    It 'returns nothing when the battery does not report its designed capacity' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryStaticData' } { [PSCustomObject]@{ DesignedCapacity = 0 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryFullChargedCapacity' } { [PSCustomObject]@{ FullChargedCapacity = 48000 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'BatteryCycleCount' } { }
        @(InModuleScope HelpdeskToolkit { Get-BatteryCapacity }).Count | Should -Be 0
    }
}

Describe 'Get-ThirdPartyTask' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-ScheduledTask {
            [PSCustomObject]@{ TaskName = 'Defrag'; TaskPath = '\Microsoft\Windows\Defrag\'; State = 'Ready'; Author = 'Microsoft' }
            [PSCustomObject]@{ TaskName = 'ContosoUpdater'; TaskPath = '\'; State = 'Ready'; Author = 'Contoso' }
            [PSCustomObject]@{ TaskName = 'Backup Task-S-1-5-21-111-222-333-1001'; TaskPath = '\Contoso\'; State = 'Disabled'; Author = 'TEST-PC\tester' }
        }
        $tasks = @(InModuleScope HelpdeskToolkit { Get-ThirdPartyTask })
    }

    It 'leaves out the tasks of Windows' {
        $tasks.Name | Should -Be @('ContosoUpdater', 'Backup Task')
    }

    It 'removes the security identifier of the user from the name' {
        $tasks[1].Name | Should -Be 'Backup Task'
    }

    It 'tells whether a task is enabled' {
        $tasks.Enabled | Should -Be @($true, $false)
    }
}

Describe 'Get-BrowserExtension' {
    BeforeAll {
        # Writes an extension into a fake browser profile below the test folder.
        function New-TestExtension {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only writes into the temporary test folder.')]
            param([string]$ProfilePath, [string]$Id, [string]$Version, [string]$Manifest, [hashtable]$Messages = @{})

            $folder = Join-Path -Path $ProfilePath -ChildPath "Extensions\$Id\$Version"
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path -Path $folder -ChildPath 'manifest.json'), $Manifest)
            foreach ($locale in $Messages.Keys) {
                $localeFolder = Join-Path -Path $folder -ChildPath "_locales\$locale"
                New-Item -Path $localeFolder -ItemType Directory -Force | Out-Null
                [System.IO.File]::WriteAllText((Join-Path -Path $localeFolder -ChildPath 'messages.json'), $Messages[$locale])
            }
        }

        $previousLocal = $env:LOCALAPPDATA
        $previousRoaming = $env:APPDATA
        $env:LOCALAPPDATA = Join-Path -Path $TestDrive -ChildPath 'Local'
        $env:APPDATA = Join-Path -Path $TestDrive -ChildPath 'Roaming'

        $chrome = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Google\Chrome\User Data'
        New-TestExtension -ProfilePath "$chrome\Default" -Id 'aaa' -Version '1.2.0_0' -Manifest '{ "name": "Ad Blocker", "version": "1.2.0" }'
        # An older version of the same extension is still on disk; the newest one counts.
        New-TestExtension -ProfilePath "$chrome\Default" -Id 'aaa' -Version '1.1.0_0' -Manifest '{ "name": "Ad Blocker (old)", "version": "1.1.0" }'
        # The name is a reference into the language files, written in another case.
        New-TestExtension -ProfilePath "$chrome\Default" -Id 'bbb' -Version '3.0_0' -Manifest '{ "name": "__MSG_appName__", "version": "3.0", "default_locale": "de" }' -Messages @{
            de = '{ "appname": { "message": "Einkaufshelfer" } }'
            en = '{ "appname": { "message": "Shopping Helper" } }'
        }
        # Only the default language of the extension has the text.
        New-TestExtension -ProfilePath "$chrome\Default" -Id 'ccc' -Version '1.0_0' -Manifest '{ "name": "__MSG_title__", "version": "1.0", "default_locale": "hr" }' -Messages @{
            hr = '{ "title": { "message": "Rjecnik" } }'
        }
        # The text cannot be found: the folder name of the extension is shown.
        New-TestExtension -ProfilePath "$chrome\Default" -Id 'ddd' -Version '1.0_0' -Manifest '{ "name": "__MSG_missing__", "version": "1.0" }'
        # A second profile has the same extension again.
        New-TestExtension -ProfilePath "$chrome\Profile 1" -Id 'aaa' -Version '1.2.0_0' -Manifest '{ "name": "Ad Blocker", "version": "1.2.0" }'
        # A broken manifest must not stop the others.
        New-TestExtension -ProfilePath "$chrome\Default" -Id 'eee' -Version '1.0_0' -Manifest 'this is not json'
        # Opera keeps the default profile directly in its folder.
        New-TestExtension -ProfilePath (Join-Path -Path $env:APPDATA -ChildPath 'Opera Software\Opera Stable') -Id 'fff' -Version '2.0_0' -Manifest '{ "name": "Sidebar Tool", "version": "2.0" }'

        $extensions = @(InModuleScope HelpdeskToolkit { Get-BrowserExtension })
    }

    AfterAll {
        $env:LOCALAPPDATA = $previousLocal
        $env:APPDATA = $previousRoaming
    }

    It 'returns the extensions of every installed browser' {
        ($extensions | Where-Object Browser -eq 'Chrome').Name | Sort-Object | Should -Be @('Ad Blocker', 'ddd', 'Rjecnik', 'Shopping Helper')
        ($extensions | Where-Object Browser -eq 'Opera').Name | Should -Be 'Sidebar Tool'
    }

    It 'reads the version of the newest installed copy' {
        ($extensions | Where-Object Name -eq 'Ad Blocker').Version | Should -Be '1.2.0'
    }

    It 'lists an extension once per browser, even when several profiles have it' {
        @($extensions | Where-Object Name -eq 'Ad Blocker').Count | Should -Be 1
    }

    It 'prefers the English name of an extension that supports several languages' {
        $extensions.Name | Should -Contain 'Shopping Helper'
        $extensions.Name | Should -Not -Contain 'Einkaufshelfer'
    }

    It 'returns nothing for browsers that are not installed' {
        $extensions | Where-Object Browser -in 'Edge', 'Brave', 'Opera GX' | Should -BeNullOrEmpty
    }
}

Describe 'Get-ListeningPort' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-NetTCPConnection {
            [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 445; OwningProcess = 4 }
            [PSCustomObject]@{ LocalAddress = '::'; LocalPort = 445; OwningProcess = 4 }
            [PSCustomObject]@{ LocalAddress = '127.0.0.1'; LocalPort = 8080; OwningProcess = 500 }
            [PSCustomObject]@{ LocalAddress = '::1'; LocalPort = 8080; OwningProcess = 500 }
            [PSCustomObject]@{ LocalAddress = '127.0.0.1'; LocalPort = 135; OwningProcess = 900 }
            [PSCustomObject]@{ LocalAddress = '192.0.2.10'; LocalPort = 135; OwningProcess = 900 }
            [PSCustomObject]@{ LocalAddress = '0.0.0.0'; LocalPort = 50000; OwningProcess = 7777 }
        }
        Mock -ModuleName HelpdeskToolkit Get-Process {
            [PSCustomObject]@{ Id = 4; ProcessName = 'System' }
            [PSCustomObject]@{ Id = 500; ProcessName = 'devserver' }
            [PSCustomObject]@{ Id = 900; ProcessName = 'svchost' }
        }
        $ports = @(InModuleScope HelpdeskToolkit { Get-ListeningPort })
    }

    It 'returns every port once, sorted by number' {
        $ports.Port | Should -Be @(135, 445, 8080, 50000)
    }

    It 'names the program behind the port, or "unknown" when it has ended meanwhile' {
        $ports.Process | Should -Be @('svchost', 'System', 'devserver', 'unknown')
    }

    It 'marks a port as local only when every address it listens on is the loopback address' {
        $ports.LocalOnly | Should -Be @($false, $false, $true, $false)
    }

    It 'asks only for connections in the state "Listen"' {
        Should -Invoke -ModuleName HelpdeskToolkit Get-NetTCPConnection -Scope Describe -ParameterFilter { $State -eq 'Listen' }
    }
}

Describe 'Get-WifiConnection' {
    It 'reads the connected network from English output' {
        Mock -ModuleName HelpdeskToolkit Invoke-NetshWlan {
            ''
            'There is 1 interface on the system:'
            ''
            '    Name                   : Wi-Fi'
            '    Description            : Contoso Wi-Fi 6 AX200 160MHz'
            '    Physical address       : 00:00:5e:00:53:2a'
            '    State                  : connected'
            '    SSID                   : Office Net'
            '    AP BSSID               : 00:00:5e:00:53:99'
            '    Band                   : 5 GHz'
            '    Channel                : 36'
            '    Radio type             : 802.11ax'
            '    Authentication         : WPA2-Personal'
            '    Cipher                 : CCMP'
            '    Receive rate (Mbps)    : 866.7'
            '    Signal                 : 87%'
            '    Profile                : Office Net'
            ''
        }
        $wifi = InModuleScope HelpdeskToolkit { Get-WifiConnection }

        $wifi.Ssid | Should -Be 'Office Net'
        $wifi.SignalPercent | Should -Be 87
        $wifi.Radio | Should -Be '802.11ax'
        $wifi.Band | Should -Be '5 GHz'
        $wifi.Security | Should -Be 'WPA2-Personal'
    }

    It 'reads the same values when Windows uses another language for the labels' {
        Mock -ModuleName HelpdeskToolkit Invoke-NetshWlan {
            '    Naziv                  : Wi-Fi'
            '    Stanje                 : povezano'
            '    SSID                   : Ured'
            '    BSSID                  : 00:00:5e:00:53:99'
            '    Vrsta radija           : 802.11ac'
            '    Provjera autenticnosti : WPA3-Personal'
            '    Signal                 : 64%'
            ''
        }
        $wifi = InModuleScope HelpdeskToolkit { Get-WifiConnection }

        $wifi.Ssid | Should -Be 'Ured'
        $wifi.SignalPercent | Should -Be 64
        $wifi.Radio | Should -Be '802.11ac'
        $wifi.Band | Should -Be ''
        $wifi.Security | Should -Be 'WPA3-Personal'
    }

    It 'reports a network without WPA or WEP as open' {
        Mock -ModuleName HelpdeskToolkit Invoke-NetshWlan {
            '    SSID                   : Cafe'
            '    Authentication         : Open'
            '    Signal                 : 70%'
            ''
        }
        (InModuleScope HelpdeskToolkit { Get-WifiConnection }).Security | Should -Be 'Open'
    }

    It 'returns nothing for an adapter that is not connected' {
        Mock -ModuleName HelpdeskToolkit Invoke-NetshWlan {
            '    Name                   : Wi-Fi'
            '    State                  : disconnected'
            '    Radio status           : Hardware On'
            ''
        }
        @(InModuleScope HelpdeskToolkit { Get-WifiConnection }).Count | Should -Be 0
    }

    It 'returns one connection per adapter' {
        Mock -ModuleName HelpdeskToolkit Invoke-NetshWlan {
            '    SSID                   : First'
            '    Signal                 : 50%'
            ''
            '    SSID                   : Second'
            '    Signal                 : 90%'
        }
        (InModuleScope HelpdeskToolkit { Get-WifiConnection }).Ssid | Should -Be @('First', 'Second')
    }

    It 'returns nothing on a computer without Wi-Fi' {
        Mock -ModuleName HelpdeskToolkit Invoke-NetshWlan { }
        @(InModuleScope HelpdeskToolkit { Get-WifiConnection }).Count | Should -Be 0
    }
}

Describe 'Get-PowerPlanName' {
    It 'returns the English name stored after the reference into the system file' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'ActivePowerScheme' } { '381b4222-f694-41f0-9685-ff5bb260df2e' }
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'FriendlyName' } { '@%SystemRoot%\system32\powrprof.dll,-15,Balanced' }
        InModuleScope HelpdeskToolkit { Get-PowerPlanName } | Should -Be 'Balanced'
    }

    It 'returns the plain name of a plan the user created' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'ActivePowerScheme' } { '11111111-2222-3333-4444-555555555555' }
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'FriendlyName' } { 'My Gaming Plan' }
        InModuleScope HelpdeskToolkit { Get-PowerPlanName } | Should -Be 'My Gaming Plan'
    }

    It 'knows the plans of Windows when the registry has no name for them' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'ActivePowerScheme' } { '8C5E7FDA-E8BF-4A96-9A85-A6E23A8C635C' }
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'FriendlyName' } { }
        InModuleScope HelpdeskToolkit { Get-PowerPlanName } | Should -Be 'High performance'
    }

    It 'returns nothing when the active plan cannot be read' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { }
        InModuleScope HelpdeskToolkit { Get-PowerPlanName } | Should -BeNullOrEmpty
    }

    It 'looks up the name under the key of the active plan' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'ActivePowerScheme' } { 'abc' }
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'FriendlyName' } { 'Plan' }
        InModuleScope HelpdeskToolkit { Get-PowerPlanName } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'FriendlyName' -and $Path -like '*\PowerSchemes\abc' }
    }
}

Describe 'Get-FileHistoryTarget' {
    BeforeAll {
        $previousLocal = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = Join-Path -Path $TestDrive -ChildPath 'Local'
        $folder = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Windows\FileHistory\Configuration'
        $config = Join-Path -Path $folder -ChildPath 'Config1.xml'
    }

    AfterAll {
        $env:LOCALAPPDATA = $previousLocal
    }

    It 'returns nothing when File History was never set up' {
        InModuleScope HelpdeskToolkit { Get-FileHistoryTarget } | Should -BeNullOrEmpty
    }

    It 'returns the name of the drive that receives the backups' {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $config -Value '<DataProtectionUserConfig><Target><TargetName>Backup Drive</TargetName><TargetUrl>E:\</TargetUrl></Target></DataProtectionUserConfig>'
        InModuleScope HelpdeskToolkit { Get-FileHistoryTarget } | Should -Be 'Backup Drive'
    }

    It 'falls back to the address of the target when it has no name' {
        Set-Content -LiteralPath $config -Value '<DataProtectionUserConfig><Target><TargetUrl>\\nas\backup</TargetUrl></Target></DataProtectionUserConfig>'
        InModuleScope HelpdeskToolkit { Get-FileHistoryTarget } | Should -Be '\\nas\backup'
    }

    It 'still reports that File History is set up when the file cannot be understood' {
        Set-Content -LiteralPath $config -Value 'not xml at all'
        InModuleScope HelpdeskToolkit { Get-FileHistoryTarget } | Should -Be 'unknown target'
    }
}

Describe 'Get-RestorePoint' {
    It 'converts the creation time of every restore point' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance {
            [PSCustomObject]@{ CreationTime = '20260112183000.000000-000' }
            [PSCustomObject]@{ CreationTime = '20260103100000.000000-000' }
        }
        $points = @(InModuleScope HelpdeskToolkit { Get-RestorePoint })

        $points.Count | Should -Be 2
        $points[0] | Should -BeOfType [datetime]
        $points[0].ToUniversalTime().ToString('yyyy-MM-dd HH:mm') | Should -Be '2026-01-12 18:30'
    }

    It 'asks the System Restore class in the namespace root/default' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { }
        InModuleScope HelpdeskToolkit { Get-RestorePoint } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $Namespace -eq 'root/default' -and $ClassName -eq 'SystemRestore' }
    }
}

Describe 'Get-PendingUpdate' {
    It 'asks the Windows Update Agent without starting a new search and returns the titles' {
        # A stand-in for the COM object of Windows Update.
        $session = [PSCustomObject]@{ Searcher = [PSCustomObject]@{ Online = $true; Query = '' } }
        $session.Searcher | Add-Member -MemberType ScriptMethod -Name Search -Value {
            param($Query)
            $this.Query = $Query
            [PSCustomObject]@{ Updates = @([PSCustomObject]@{ Title = 'Update A' }, [PSCustomObject]@{ Title = 'Update B' }) }
        }
        $session | Add-Member -MemberType ScriptMethod -Name CreateUpdateSearcher -Value { $this.Searcher }
        Mock -ModuleName HelpdeskToolkit New-Object { $session } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }

        InModuleScope HelpdeskToolkit { Get-PendingUpdate } | Should -Be @('Update A', 'Update B')
        $session.Searcher.Online | Should -BeFalse
        $session.Searcher.Query | Should -Be 'IsInstalled=0 and IsHidden=0'
    }
}
