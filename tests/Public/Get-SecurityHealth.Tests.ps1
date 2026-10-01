BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-SecurityHealth' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }

        Mock -ModuleName HelpdeskToolkit Get-DefenderStatus {
            [PSCustomObject]@{
                RealTimeProtectionEnabled     = $true
                AntivirusEnabled              = $true
                AntivirusSignatureAge         = 1
                AntivirusSignatureLastUpdated = [datetime]'2026-01-14 06:12'
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-AntivirusProduct { 'Windows Defender' }
        Mock -ModuleName HelpdeskToolkit Get-FirewallProfileState {
            [PSCustomObject]@{ Name = 'Domain'; Enabled = $true }
            [PSCustomObject]@{ Name = 'Private'; Enabled = $true }
            [PSCustomObject]@{ Name = 'Public'; Enabled = $true }
        }
        Mock -ModuleName HelpdeskToolkit Get-SecureBootState { 'Enabled' }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
    }

    Context 'on a well protected computer, without administrator rights' {
        BeforeAll {
            $results = Get-SecurityHealth
        }

        It 'reports <Check> as <Status> with value "<Value>"' -ForEach @(
            @{ Check = 'Defender real-time protection'; Status = 'OK'; Value = 'Enabled' }
            @{ Check = 'Defender definitions'; Status = 'OK'; Value = '1 day old (updated 2026-01-14 06:12)' }
            @{ Check = 'Firewall - Domain profile'; Status = 'OK'; Value = 'Enabled' }
            @{ Check = 'Firewall - Private profile'; Status = 'OK'; Value = 'Enabled' }
            @{ Check = 'Firewall - Public profile'; Status = 'OK'; Value = 'Enabled' }
            @{ Check = 'Secure Boot'; Status = 'OK'; Value = 'Enabled' }
        ) {
            $result = $results | Where-Object Check -eq $Check
            $result.Status | Should -Be $Status
            $result.Value | Should -Be $Value
        }

        It 'skips the checks that need elevation and marks them "Requires admin"' {
            $tpm = $results | Where-Object Check -eq 'TPM'
            $bitLocker = $results | Where-Object Check -like 'BitLocker*'

            $tpm.Status | Should -Be 'Info'
            $tpm.Value | Should -Be 'Requires admin'
            $bitLocker.Value | Should -Be 'Requires admin'
        }

        It 'does not query the admin-only WMI classes at all' {
            Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -Times 0 -Exactly -Scope Context
        }
    }

    Context 'Microsoft Defender' {
        It 'is Critical when real-time protection is off and no other antivirus is installed' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderStatus {
                [PSCustomObject]@{ RealTimeProtectionEnabled = $false; AntivirusEnabled = $false; AntivirusSignatureAge = 0; AntivirusSignatureLastUpdated = Get-Date }
            }
            $protection = Get-SecurityHealth | Where-Object Check -eq 'Defender real-time protection'
            $protection.Status | Should -Be 'Critical'
            $protection.Recommendation | Should -Match 'No active antivirus'
        }

        It 'is only informational when a third-party antivirus has taken over' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderStatus {
                [PSCustomObject]@{ RealTimeProtectionEnabled = $false; AntivirusEnabled = $false; AntivirusSignatureAge = 0; AntivirusSignatureLastUpdated = Get-Date }
            }
            Mock -ModuleName HelpdeskToolkit Get-AntivirusProduct { 'Windows Defender'; 'Contoso Antivirus' }

            $results = Get-SecurityHealth
            $protection = $results | Where-Object Check -eq 'Defender real-time protection'
            $protection.Status | Should -Be 'Info'
            $protection.Value | Should -Be 'Disabled (third-party antivirus: Contoso Antivirus)'
            # Defender does not update its definitions while another product is active.
            $results | Where-Object Check -eq 'Defender definitions' | Should -BeNullOrEmpty
        }

        It 'reports definitions that are <Age> days old as <Status>' -ForEach @(
            @{ Age = 0; Status = 'OK' }
            @{ Age = 3; Status = 'OK' }
            @{ Age = 5; Status = 'Warning' }
            @{ Age = 9; Status = 'Critical' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-DefenderStatus {
                [PSCustomObject]@{
                    RealTimeProtectionEnabled = $true; AntivirusEnabled = $true
                    AntivirusSignatureAge = $Age; AntivirusSignatureLastUpdated = (Get-Date).AddDays(-$Age)
                }
            }
            $definitions = Get-SecurityHealth | Where-Object Check -eq 'Defender definitions'
            $definitions.Status | Should -Be $Status
            $definitions.Allowed | Should -Be '0 - 3 days (critical above 7 days)'
        }

        It 'reports Defender as unavailable when its status cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderStatus { throw 'The Defender module is not installed' }
            $results = Get-SecurityHealth
            ($results | Where-Object Check -eq 'Microsoft Defender').Value | Should -Be 'Unavailable'
            # The other checks still run.
            ($results | Where-Object Check -eq 'Secure Boot').Status | Should -Be 'OK'
        }
    }

    Context 'firewall' {
        It 'is a Warning for every profile that is turned off' {
            Mock -ModuleName HelpdeskToolkit Get-FirewallProfileState {
                [PSCustomObject]@{ Name = 'Domain'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Private'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Public'; Enabled = $false }
            }
            $results = Get-SecurityHealth
            ($results | Where-Object Check -eq 'Firewall - Private profile').Status | Should -Be 'OK'

            $public = $results | Where-Object Check -eq 'Firewall - Public profile'
            $public.Status | Should -Be 'Warning'
            $public.Value | Should -Be 'Disabled'
            $public.Recommendation | Should -Match 'Turn on Windows Defender Firewall'
        }
    }

    Context 'Secure Boot' {
        It 'reports state <State> as <Status> with value "<Value>"' -ForEach @(
            @{ State = 'Disabled'; Status = 'Info'; Value = 'Disabled' }
            @{ State = 'Unsupported'; Status = 'Info'; Value = 'Not supported (legacy BIOS mode)' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-SecureBootState { $State }
            $secureBoot = Get-SecurityHealth | Where-Object Check -eq 'Secure Boot'
            $secureBoot.Status | Should -Be $Status
            $secureBoot.Value | Should -Be $Value
        }
    }

    Context 'with administrator rights' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Tpm' } {
                [PSCustomObject]@{ IsEnabled_InitialValue = $true; SpecVersion = '2.0, 0, 1.59' }
            }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_EncryptableVolume' } {
                [PSCustomObject]@{ ProtectionStatus = 1 }
            }
        }

        It 'reports an enabled TPM with its version' {
            $tpm = Get-SecurityHealth | Where-Object Check -eq 'TPM'
            $tpm.Status | Should -Be 'OK'
            $tpm.Value | Should -Be 'Enabled, version 2.0'
        }

        It 'reports a TPM that is present but disabled as a Warning' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Tpm' } {
                [PSCustomObject]@{ IsEnabled_InitialValue = $false; SpecVersion = '2.0, 0, 1.59' }
            }
            (Get-SecurityHealth | Where-Object Check -eq 'TPM').Status | Should -Be 'Warning'
        }

        It 'reports a missing TPM as information' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Tpm' } { }
            (Get-SecurityHealth | Where-Object Check -eq 'TPM').Value | Should -Be 'Not present'
        }

        It 'reports BitLocker protection that is on as OK' {
            $bitLocker = Get-SecurityHealth | Where-Object Check -like 'BitLocker*'
            $bitLocker.Status | Should -Be 'OK'
            $bitLocker.Value | Should -Be 'Protection on'
        }

        It 'reports BitLocker protection that is off as information with advice' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_EncryptableVolume' } {
                [PSCustomObject]@{ ProtectionStatus = 0 }
            }
            $bitLocker = Get-SecurityHealth | Where-Object Check -like 'BitLocker*'
            $bitLocker.Status | Should -Be 'Info'
            $bitLocker.Value | Should -Be 'Protection off'
            $bitLocker.Recommendation | Should -Match 'BitLocker'
        }

        It 'reports BitLocker as not available when the volume is not found' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_EncryptableVolume' } { }
            (Get-SecurityHealth | Where-Object Check -like 'BitLocker*').Value | Should -Be 'Not available on this system'
        }
    }
}
