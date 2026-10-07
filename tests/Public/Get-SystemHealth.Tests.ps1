BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-SystemHealth' {
    BeforeAll {
        # Any WMI class that a test did not prepare fails loudly instead of
        # silently reading the real computer.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }

        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [PSCustomObject]@{
                Caption        = 'Microsoft Windows 11 Pro'
                BuildNumber    = '26100'
                LastBootUpTime = (Get-Date).AddDays(-2).AddHours(-3)
                InstallDate    = [datetime]'2024-11-04'
                ProductType    = 1
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
            [PSCustomObject]@{
                Name         = 'TEST-PC-01'
                Manufacturer = 'Contoso'
                Model        = 'Book 5'
                PartOfDomain = $false
                Domain       = 'WORKGROUP'
                UserName     = 'TEST-PC-01\tester'
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
            [PSCustomObject]@{ LicenseStatus = 1 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } {
            'OneDrive', 'Teams', 'Updater' | ForEach-Object { [PSCustomObject]@{ Name = $_ } }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ReliabilityStabilityMetrics' } {
            [PSCustomObject]@{ SystemStabilityIndex = 8.74; TimeGenerated = (Get-Date).AddHours(-2) }
            [PSCustomObject]@{ SystemStabilityIndex = 8.86; TimeGenerated = (Get-Date).AddHours(-1) }
        }
        # The tests run as a standard user unless a test says otherwise.
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        # 91H1 is a release of the test configuration that is supported for a long time.
        Mock -ModuleName HelpdeskToolkit Get-OSDisplayVersion { '91H1' }
        Mock -ModuleName HelpdeskToolkit Get-ThirdPartyTask { }
        Mock -ModuleName HelpdeskToolkit Get-PowerPlanName { 'Balanced' }
        # HiberbootEnabled = 1: Fast Startup is on.
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'HiberbootEnabled' } { 1 }
        # No System File Checker run on record and nothing that delayed a startup; the
        # servicing log and the event log of the test computer are never read.
        Mock -ModuleName HelpdeskToolkit Get-SystemFileCheckResult { }
        Mock -ModuleName HelpdeskToolkit Get-BootDegradation { }
        Mock -ModuleName HelpdeskToolkit Get-Windows11Readiness { throw 'Must only be called on Windows 10' }
    }

    Context 'on a healthy computer' {
        BeforeAll {
            $results = Get-SystemHealth
        }

        It 'returns only System results of the standard type' {
            $results.Category | Sort-Object -Unique | Should -Be 'System'
            $results[0].PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.CheckResult'
        }

        It 'reports <Check> as "<Value>"' -ForEach @(
            @{ Check = 'Computer name'; Value = 'TEST-PC-01' }
            @{ Check = 'Operating system'; Value = 'Microsoft Windows 11 Pro 91H1 (build 26100)' }
            @{ Check = 'Windows installed'; Value = '2024-11-04' }
            @{ Check = 'Manufacturer and model'; Value = 'Contoso Book 5' }
            @{ Check = 'Domain or workgroup'; Value = 'Workgroup: WORKGROUP' }
            @{ Check = 'Signed-in user'; Value = 'TEST-PC-01\tester' }
            @{ Check = 'Windows activation'; Value = 'Activated' }
            @{ Check = 'Startup programs'; Value = '3 programs: OneDrive, Teams, Updater' }
            @{ Check = 'Scheduled tasks'; Value = '0 tasks' }
            @{ Check = 'Power plan'; Value = 'Balanced' }
            @{ Check = 'Fast Startup'; Value = 'Enabled' }
        ) {
            ($results | Where-Object Check -eq $Check).Value | Should -Be $Value
        }

        It 'reports the uptime as OK with the allowed range and typical value' {
            $uptime = $results | Where-Object Check -eq 'Uptime'
            $uptime.Status | Should -Be 'OK'
            $uptime.Value | Should -Be '2 d 3 h 0 min'
            $uptime.Allowed | Should -Be '0 - 7 days'
            $uptime.Typical | Should -Be 'typical uptime'
            $uptime.Recommendation | Should -Be ''
        }

        It 'reports the time zone of the computer' {
            ($results | Where-Object Check -eq 'Time zone').Value | Should -Be ([System.TimeZoneInfo]::Local.DisplayName)
        }

        It 'gives every result a description' {
            $results | Where-Object { -not $_.Description } | Should -BeNullOrEmpty
        }
    }

    Context 'when the computer has not been restarted for a long time' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [PSCustomObject]@{
                    Caption        = 'Microsoft Windows 11 Pro'
                    BuildNumber    = '26100'
                    LastBootUpTime = (Get-Date).AddDays(-10)
                    InstallDate    = $null
                    ProductType    = 1
                }
            }
            $results = Get-SystemHealth
        }

        It 'reports the uptime as a Warning and recommends a restart' {
            $uptime = $results | Where-Object Check -eq 'Uptime'
            $uptime.Status | Should -Be 'Warning'
            $uptime.Recommendation | Should -Match 'Restart the computer'
        }

        It 'leaves out the install date when Windows does not report one' {
            $results | Where-Object Check -eq 'Windows installed' | Should -BeNullOrEmpty
        }
    }

    Context 'when the feature release is not available' {
        It 'reports the operating system without it' {
            Mock -ModuleName HelpdeskToolkit Get-OSDisplayVersion { '' }
            (Get-SystemHealth | Where-Object Check -eq 'Operating system').Value | Should -Be 'Microsoft Windows 11 Pro (build 26100)'
        }
    }

    Context 'when the computer is joined to a domain' {
        It 'reports the domain and falls back to the environment for the user name' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
                [PSCustomObject]@{
                    Name = 'TEST-PC-01'; Manufacturer = 'Contoso'; Model = 'Book 5'
                    PartOfDomain = $true; Domain = 'corp.test.example'; UserName = $null
                }
            }
            $results = Get-SystemHealth
            ($results | Where-Object Check -eq 'Domain or workgroup').Value | Should -Be 'Domain: corp.test.example'
            ($results | Where-Object Check -eq 'Signed-in user').Value | Should -Be ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME)
        }
    }

    Context 'when Windows is not activated' {
        It 'reports a Warning for license status <LicenseStatus>' -ForEach @(
            @{ LicenseStatus = 0 }
            @{ LicenseStatus = 5 }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } {
                [PSCustomObject]@{ LicenseStatus = $LicenseStatus }
            }
            $activation = Get-SystemHealth | Where-Object Check -eq 'Windows activation'
            $activation.Status | Should -Be 'Warning'
            $activation.Value | Should -Be 'Not activated'
        }

        It 'reports a Warning when no license with a product key exists' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'SoftwareLicensingProduct' } { }
            (Get-SystemHealth | Where-Object Check -eq 'Windows activation').Status | Should -Be 'Warning'
        }
    }

    Context 'when many programs start with Windows' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } {
                1..18 | ForEach-Object { [PSCustomObject]@{ Name = 'Program{0:00}' -f $_ } }
                [PSCustomObject]@{ Name = 'BrowserAutoLaunch_0123456789ABCDEF0123456789ABCDEF' }
                # The same program registered twice must be counted once.
                [PSCustomObject]@{ Name = 'Program01' }
            }
            $startup = Get-SystemHealth | Where-Object Check -eq 'Startup programs'
        }

        It 'reports a Warning above the limit and counts each program once' {
            $startup.Status | Should -Be 'Warning'
            $startup.Value | Should -Match '^19 programs: '
            $startup.Allowed | Should -Be '0 - 15'
            $startup.Recommendation | Should -Match 'Startup apps'
        }

        It 'shows the first eight programs and keeps the rest as details' {
            $startup.Value | Should -Match 'and 11 more$'
            $startup.Details.Count | Should -Be 11
            $startup.Details | Should -Contain 'Program18'
        }

        It 'removes generated suffixes from program names' {
            $startup.Value | Should -Match 'BrowserAutoLaunch,'
            $startup.Value | Should -Not -Match '0123456789ABCDEF'
        }
    }

    Context 'Windows support and stability' {
        It 'reports a supported Windows version as OK' {
            $support = Get-SystemHealth | Where-Object Check -eq 'Windows support'
            $support.Status | Should -Be 'OK'
            $support.Value | Should -Match '^Supported until \d{4}-\d{2}-\d{2}$'
        }

        It 'reports a Windows version that is out of support as Critical' {
            Mock -ModuleName HelpdeskToolkit Get-OSDisplayVersion { '90H1' }
            $support = Get-SystemHealth | Where-Object Check -eq 'Windows support'
            $support.Status | Should -Be 'Critical'
            $support.Recommendation | Should -Match 'no longer receives security updates'
        }

        It 'reports the newest stability index' {
            $stability = Get-SystemHealth | Where-Object Check -eq 'Stability index'
            $stability.Status | Should -Be 'OK'
            $stability.Value | Should -Be '8.9 of 10'
            $stability.Allowed | Should -Be '5 - 10 (critical below 3)'
        }

        It 'reports a stability index of <Index> as <Status>' -ForEach @(
            @{ Index = 4.2; Status = 'Warning' }
            @{ Index = 1.5; Status = 'Critical' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ReliabilityStabilityMetrics' } {
                [PSCustomObject]@{ SystemStabilityIndex = $Index; TimeGenerated = Get-Date }
            }
            $stability = Get-SystemHealth | Where-Object Check -eq 'Stability index'
            $stability.Status | Should -Be $Status
            $stability.Recommendation | Should -Match 'Reliability Monitor'
        }

        It 'says so when Windows keeps no stability data' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ReliabilityStabilityMetrics' } { }
            (Get-SystemHealth | Where-Object Check -eq 'Stability index').Value | Should -Be 'Not available'
        }
    }

    Context 'without administrator rights' {
        It 'marks <_> as "Requires admin" instead of trying to read it' -ForEach @('Last startup duration', 'User profiles') {
            Mock -ModuleName HelpdeskToolkit Get-LastBootDuration { }
            $result = Get-SystemHealth | Where-Object Check -eq $_
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Requires admin'
            Should -Invoke -ModuleName HelpdeskToolkit Get-LastBootDuration -Times 0 -Exactly
        }
    }

    Context 'with administrator rights' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-LastBootDuration { [PSCustomObject]@{ Seconds = 45; MeasuredAt = (Get-Date).AddDays(-2) } }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_UserProfile' } {
                [PSCustomObject]@{ LocalPath = 'C:\Users\m.horvat'; Special = $false }
                [PSCustomObject]@{ LocalPath = 'C:\Users\support'; Special = $false }
                [PSCustomObject]@{ LocalPath = 'C:\Windows\ServiceProfiles\LocalService'; Special = $true }
            }
            Mock -ModuleName HelpdeskToolkit Test-Path { $true }
            Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 2GB; FileCount = 10; Complete = $true } }
            Mock -ModuleName HelpdeskToolkit Get-FolderSize -ParameterFilter { $Path -like '*m.horvat' } { [PSCustomObject]@{ Bytes = 40GB; FileCount = 90000; Complete = $false } }
        }

        It 'reports a recent, normal startup duration as OK' {
            $boot = Get-SystemHealth | Where-Object Check -eq 'Last startup duration'
            $boot.Status | Should -Be 'OK'
            $boot.Value | Should -Be ([string]::Format([cultureinfo]::InvariantCulture, '45 seconds (measured {0:yyyy-MM-dd})', @((Get-Date).AddDays(-2))))
            $boot.Allowed | Should -Be '0 - 120 seconds'
        }

        It 'is a Warning when a recent startup took longer than the limit' {
            Mock -ModuleName HelpdeskToolkit Get-LastBootDuration { [PSCustomObject]@{ Seconds = 200; MeasuredAt = (Get-Date).AddDays(-1) } }
            $boot = Get-SystemHealth | Where-Object Check -eq 'Last startup duration'
            $boot.Status | Should -Be 'Warning'
            $boot.Recommendation | Should -Match 'Startup apps'
        }

        It 'does not judge a measurement that is older than the configured number of days' {
            Mock -ModuleName HelpdeskToolkit Get-LastBootDuration { [PSCustomObject]@{ Seconds = 200; MeasuredAt = (Get-Date).AddDays(-300) } }
            $boot = Get-SystemHealth | Where-Object Check -eq 'Last startup duration'
            $boot.Status | Should -Be 'Info'
            $boot.Recommendation | Should -Be ''
        }

        It 'says so when Windows has no startup measurement' {
            Mock -ModuleName HelpdeskToolkit Get-LastBootDuration { }
            (Get-SystemHealth | Where-Object Check -eq 'Last startup duration').Value | Should -Be 'No measurement recorded'
        }

        It 'lists the user profiles by size and skips the profiles of Windows itself' {
            $profiles = Get-SystemHealth | Where-Object Check -eq 'User profiles'
            $profiles.Status | Should -Be 'Info'
            $profiles.Value | Should -Be '2 profiles: m.horvat 40 GB or more, support 2 GB'
        }
    }

    Context 'when WMI is not working' {
        It 'returns a single Warning instead of throwing' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } { throw 'WMI repository is corrupted' }
            $results = @(Get-SystemHealth)
            $results.Count | Should -Be 1
            $results[0].Check | Should -Be 'System information'
            $results[0].Status | Should -Be 'Warning'
            $results[0].Recommendation | Should -Match 'WMI repository is corrupted'
        }

        It 'marks a permission problem as "Requires admin"' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_StartupCommand' } {
                throw (New-Object -TypeName System.UnauthorizedAccessException -ArgumentList 'Access denied')
            }
            (Get-SystemHealth | Where-Object Check -eq 'Startup programs').Value | Should -Be 'Requires admin'
        }
    }

    Context 'scheduled tasks that do not belong to Windows' {
        It 'lists them by name and marks the disabled ones' {
            Mock -ModuleName HelpdeskToolkit Get-ThirdPartyTask {
                [PSCustomObject]@{ Name = 'Updater'; Author = 'Contoso'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Backup'; Author = 'Contoso'; Enabled = $false }
            }
            $tasks = Get-SystemHealth | Where-Object Check -eq 'Scheduled tasks'

            $tasks.Status | Should -Be 'Info'
            $tasks.Value | Should -Be '2 tasks: Backup (disabled), Updater'
        }

        It 'shows the first six and keeps the rest as details' {
            Mock -ModuleName HelpdeskToolkit Get-ThirdPartyTask {
                1..8 | ForEach-Object { [PSCustomObject]@{ Name = "Task$_"; Author = ''; Enabled = $true } }
            }
            $tasks = Get-SystemHealth | Where-Object Check -eq 'Scheduled tasks'

            $tasks.Value | Should -Be '8 tasks: Task1, Task2, Task3, Task4, Task5, Task6 and 2 more'
            $tasks.Details | Should -Be @('Task7', 'Task8')
        }

        It 'reports the tasks as unavailable when the task scheduler does not answer' {
            Mock -ModuleName HelpdeskToolkit Get-ThirdPartyTask { throw 'The task scheduler service is not available' }
            $results = Get-SystemHealth
            ($results | Where-Object Check -eq 'Scheduled tasks').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Power plan').Value | Should -Be 'Balanced'
        }
    }

    Context 'power plan and Fast Startup' {
        It 'reports an unknown plan when the registry does not name it' {
            Mock -ModuleName HelpdeskToolkit Get-PowerPlanName { }
            (Get-SystemHealth | Where-Object Check -eq 'Power plan').Value | Should -Be 'Unknown'
        }

        It 'reports Fast Startup as <Expected> when the registry value is <Value>' -ForEach @(
            @{ Value = 1; Expected = 'Enabled' }
            @{ Value = 0; Expected = 'Disabled' }
            @{ Value = $null; Expected = 'Unknown' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'HiberbootEnabled' } { $Value }
            (Get-SystemHealth | Where-Object Check -eq 'Fast Startup').Value | Should -Be $Expected
        }
    }

    Context 'System File Checker' {
        It 'says so when no check is on record' {
            $result = Get-SystemHealth | Where-Object Check -eq 'System file check'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'No check on record'
        }

        It 'reports a <Verdict> result as <Status>' -ForEach @(
            @{ Verdict = 'Clean'; Status = 'OK'; Value = 'No damaged files (checked 2026-01-09)' }
            @{ Verdict = 'Repaired'; Status = 'Info'; Value = 'Damaged files were found and repaired (checked 2026-01-09)' }
            @{ Verdict = 'Unrepaired'; Status = 'Warning'; Value = 'Damaged files could not be repaired (checked 2026-01-09)' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-SystemFileCheckResult { [PSCustomObject]@{ CheckedAt = [datetime]'2026-01-09 21:04'; Verdict = $Verdict } }.GetNewClosure()
            $result = Get-SystemHealth | Where-Object Check -eq 'System file check'
            $result.Status | Should -Be $Status
            $result.Value | Should -Be $Value
        }

        It 'tells how to repair what the checker could not' {
            Mock -ModuleName HelpdeskToolkit Get-SystemFileCheckResult { [PSCustomObject]@{ CheckedAt = Get-Date; Verdict = 'Unrepaired' } }
            (Get-SystemHealth | Where-Object Check -eq 'System file check').Recommendation | Should -Match 'DISM /Online /Cleanup-Image /RestoreHealth'
        }

        It 'marks the check "Requires admin" when the log may not be read' {
            Mock -ModuleName HelpdeskToolkit Get-SystemFileCheckResult { throw (New-Object -TypeName System.UnauthorizedAccessException -ArgumentList 'Access is denied') }
            (Get-SystemHealth | Where-Object Check -eq 'System file check').Value | Should -Be 'Requires admin'
        }
    }

    Context 'what delayed the startup' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-LastBootDuration { }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_UserProfile' } { }
        }

        It 'is marked "Requires admin" without administrator rights' {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
            (Get-SystemHealth | Where-Object Check -eq 'Startup delays').Value | Should -Be 'Requires admin'
            Should -Invoke -ModuleName HelpdeskToolkit Get-BootDegradation -Times 0 -Exactly
        }

        It 'is OK when Windows blamed nothing' {
            $result = Get-SystemHealth | Where-Object Check -eq 'Startup delays'
            $result.Status | Should -Be 'OK'
            $result.Value | Should -Be 'Nothing slowed the startup in the last 30 days'
        }

        It 'lists small delays for information, the longest first, averaged per culprit' {
            Mock -ModuleName HelpdeskToolkit Get-BootDegradation {
                [PSCustomObject]@{ Kind = 'driver'; Name = 'ctsdrv'; Milliseconds = 2100; MeasuredAt = Get-Date }
                [PSCustomObject]@{ Kind = 'program'; Name = 'Contoso Sync'; Milliseconds = 5000; MeasuredAt = Get-Date }
                [PSCustomObject]@{ Kind = 'program'; Name = 'Contoso Sync'; Milliseconds = 7000; MeasuredAt = Get-Date }
            }
            $result = Get-SystemHealth | Where-Object Check -eq 'Startup delays'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be '2 culprits in the last 30 days: Contoso Sync (program, 6 s), ctsdrv (driver, 2 s)'
            $result.Recommendation | Should -BeNullOrEmpty
            $result.Allowed | Should -Be '0 - 10 seconds'
        }

        It 'is a Warning when something held up the startup for longer than the limit' {
            Mock -ModuleName HelpdeskToolkit Get-BootDegradation {
                [PSCustomObject]@{ Kind = 'service'; Name = 'Contoso Agent'; Milliseconds = 24000; MeasuredAt = Get-Date }
            }
            $result = Get-SystemHealth | Where-Object Check -eq 'Startup delays'
            $result.Status | Should -Be 'Warning'
            $result.Value | Should -Be '1 culprit in the last 30 days: Contoso Agent (service, 24 s)'
            $result.Recommendation | Should -Match 'Startup apps'
        }

        It 'looks back as far as a startup measurement counts as recent' {
            Get-SystemHealth | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-BootDegradation -ParameterFilter {
                [math]::Abs(($Since - (Get-Date).AddDays(-30)).TotalMinutes) -lt 5
            }
        }
    }

    Context 'on Windows 10' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [PSCustomObject]@{
                    Caption = 'Microsoft Windows 10 Pro'; BuildNumber = '19045'; LastBootUpTime = (Get-Date).AddDays(-1)
                    InstallDate = [datetime]'2021-03-01'; ProductType = 1
                }
            }
            Mock -ModuleName HelpdeskToolkit Get-OSDisplayVersion { '22H2' }

            function New-TestReadiness {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                    Justification = 'Test helper that only builds objects in memory.')]
                param($Ready, $Tpm = $true, $Processor = $true)

                [PSCustomObject]@{
                    Ready        = $Ready
                    Requirements = @(
                        [PSCustomObject]@{ Name = 'Processor (64-bit, 2 cores, 1 GHz)'; Met = $Processor; Value = '64-bit, 1 cores, 2400 MHz' }
                        [PSCustomObject]@{ Name = 'Memory (4 GB)'; Met = $true; Value = '8 GB' }
                        [PSCustomObject]@{ Name = 'TPM 2.0'; Met = $Tpm; Value = 'version 1.2' }
                    )
                }
            }
        }

        It 'says that the computer can run Windows 11, with every requirement as a detail' {
            Mock -ModuleName HelpdeskToolkit Get-Windows11Readiness { New-TestReadiness -Ready $true }
            $result = Get-SystemHealth | Where-Object Check -eq 'Windows 11 readiness'
            $result.Status | Should -Be 'OK'
            $result.Value | Should -Be 'This computer meets the requirements of Windows 11'
            $result.Details | Should -Contain 'Memory (4 GB): yes (8 GB)'
        }

        It 'names what stands in the way' {
            Mock -ModuleName HelpdeskToolkit Get-Windows11Readiness { New-TestReadiness -Ready $false -Tpm $false -Processor $false }
            $result = Get-SystemHealth | Where-Object Check -eq 'Windows 11 readiness'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Does not meet the requirements: Processor (64-bit, 2 cores, 1 GHz) (64-bit, 1 cores, 2400 MHz); TPM 2.0 (version 1.2)'
            $result.Details | Should -Contain 'TPM 2.0: no (version 1.2)'
            $result.Recommendation | Should -Match 'Extended Security Updates'
        }

        It 'leaves the answer open when something could not be found out' {
            Mock -ModuleName HelpdeskToolkit Get-Windows11Readiness { New-TestReadiness -Ready $null -Tpm $null }
            $result = Get-SystemHealth | Where-Object Check -eq 'Windows 11 readiness'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Not decided, could not be found out: TPM 2.0'
            $result.Details | Should -Contain 'TPM 2.0: unknown (version 1.2)'
            $result.Recommendation | Should -Match 'as administrator'
        }

        It 'reports the check as unavailable when the hardware cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-Windows11Readiness { throw 'WMI is not working' }
            (Get-SystemHealth | Where-Object Check -eq 'Windows 11 readiness').Value | Should -Be 'Unavailable'
        }
    }

    Context 'on Windows 11' {
        It 'has no result about Windows 11 readiness' {
            Get-SystemHealth | Where-Object Check -eq 'Windows 11 readiness' | Should -BeNullOrEmpty
            Should -Invoke -ModuleName HelpdeskToolkit Get-Windows11Readiness -Times 0 -Exactly
        }
    }
}
