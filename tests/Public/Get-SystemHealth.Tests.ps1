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
        Mock -ModuleName HelpdeskToolkit Get-OSDisplayVersion { '24H2' }
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
            @{ Check = 'Operating system'; Value = 'Microsoft Windows 11 Pro 24H2 (build 26100)' }
            @{ Check = 'Windows installed'; Value = '2024-11-04' }
            @{ Check = 'Manufacturer and model'; Value = 'Contoso Book 5' }
            @{ Check = 'Domain or workgroup'; Value = 'Workgroup: WORKGROUP' }
            @{ Check = 'Signed-in user'; Value = 'TEST-PC-01\tester' }
            @{ Check = 'Windows activation'; Value = 'Activated' }
            @{ Check = 'Startup programs'; Value = '3 programs: OneDrive, Teams, Updater' }
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
}
