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
                QuickScanAge                  = 2
                IsTamperProtected             = $true
            }
        }
        # Registry: UAC on (EnableLUA = 1), Remote Desktop off (fDenyTSConnections = 1),
        # no automatic sign-in (AutoAdminLogon = 0).
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { 1 }
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'AutoAdminLogon' } { '0' }
        Mock -ModuleName HelpdeskToolkit Get-DefenderThreat { }
        Mock -ModuleName HelpdeskToolkit Get-AdministratorGroupMember { 'Administrator', 'support' }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministratorMember { $false }
        # Local accounts: the built-in ones are identified by the end of their SID.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_UserAccount' } {
            [PSCustomObject]@{ Name = 'Administrator'; SID = 'S-1-5-21-1-2-3-500'; Disabled = $true }
            [PSCustomObject]@{ Name = 'Guest'; SID = 'S-1-5-21-1-2-3-501'; Disabled = $true }
            [PSCustomObject]@{ Name = 'm.horvat'; SID = 'S-1-5-21-1-2-3-1001'; Disabled = $false }
        }
        # Only the administrative shares that Windows creates itself.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Share' } {
            [PSCustomObject]@{ Name = 'C$'; Path = 'C:\'; Type = 2147483648 }
            [PSCustomObject]@{ Name = 'IPC$'; Path = ''; Type = 2147483651 }
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
            @{ Check = 'Defender last scan'; Status = 'OK'; Value = '2 days ago' }
            @{ Check = 'User Account Control'; Status = 'OK'; Value = 'Enabled' }
            @{ Check = 'Remote Desktop'; Status = 'OK'; Value = 'Disabled' }
            @{ Check = 'Account type'; Status = 'OK'; Value = 'Standard user' }
            @{ Check = 'Tamper protection'; Status = 'OK'; Value = 'Enabled' }
            @{ Check = 'Local accounts'; Status = 'Info'; Value = '1 enabled: m.horvat' }
            @{ Check = 'Guest account'; Status = 'OK'; Value = 'Disabled' }
            @{ Check = 'Built-in Administrator account'; Status = 'OK'; Value = 'Disabled' }
            @{ Check = 'Shared folders'; Status = 'OK'; Value = 'None' }
            @{ Check = 'Threat history'; Status = 'OK'; Value = 'No threats found' }
            @{ Check = 'Administrators'; Status = 'Info'; Value = '2 members: Administrator, support' }
            @{ Check = 'Automatic sign-in'; Status = 'OK'; Value = 'Disabled' }
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
            ($results | Where-Object Check -eq 'Failed sign-ins').Value | Should -Be 'Requires admin'
            ($results | Where-Object Check -eq 'Account lockouts').Value | Should -Be 'Requires admin'
        }

        It 'does not query the admin-only WMI classes at all' {
            Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -Times 0 -Exactly -Scope Context -ParameterFilter {
                $ClassName -in 'Win32_Tpm', 'Win32_EncryptableVolume'
            }
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
                    RealTimeProtectionEnabled = $true; AntivirusEnabled = $true; QuickScanAge = 0; IsTamperProtected = $true
                    AntivirusSignatureAge = $Age; AntivirusSignatureLastUpdated = (Get-Date).AddDays(-$Age)
                }
            }
            $definitions = Get-SecurityHealth | Where-Object Check -eq 'Defender definitions'
            $definitions.Status | Should -Be $Status
            $definitions.Allowed | Should -Be '0 - 3 days (critical above 7 days)'
        }

        It 'reports a last scan <Age> days ago as <Status>' -ForEach @(
            @{ Age = 1; Status = 'OK'; Value = '1 day ago' }
            @{ Age = 14; Status = 'OK'; Value = '14 days ago' }
            @{ Age = 30; Status = 'Warning'; Value = '30 days ago' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-DefenderStatus {
                [PSCustomObject]@{
                    RealTimeProtectionEnabled = $true; AntivirusEnabled = $true; QuickScanAge = $Age; IsTamperProtected = $true
                    AntivirusSignatureAge = 0; AntivirusSignatureLastUpdated = Get-Date
                }
            }
            $scan = Get-SecurityHealth | Where-Object Check -eq 'Defender last scan'
            $scan.Status | Should -Be $Status
            $scan.Value | Should -Be $Value
            $scan.Allowed | Should -Be '0 - 14 days'
        }

        It 'reports a computer that was never scanned as a Warning' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderStatus {
                [PSCustomObject]@{
                    RealTimeProtectionEnabled = $true; AntivirusEnabled = $true; QuickScanAge = 4294967295; IsTamperProtected = $true
                    AntivirusSignatureAge = 0; AntivirusSignatureLastUpdated = Get-Date
                }
            }
            $scan = Get-SecurityHealth | Where-Object Check -eq 'Defender last scan'
            $scan.Status | Should -Be 'Warning'
            $scan.Value | Should -Be 'Never'
            $scan.Recommendation | Should -Match 'Quick scan'
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

    Context 'User Account Control, Remote Desktop and account type' {
        It 'is Critical when UAC is switched off' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'EnableLUA' } { 0 }
            $uac = Get-SecurityHealth | Where-Object Check -eq 'User Account Control'
            $uac.Status | Should -Be 'Critical'
            $uac.Value | Should -Be 'Disabled'
            $uac.Recommendation | Should -Match 'User Account Control settings'
        }

        It 'reports enabled Remote Desktop as information with advice' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'fDenyTSConnections' } { 0 }
            $remoteDesktop = Get-SecurityHealth | Where-Object Check -eq 'Remote Desktop'
            $remoteDesktop.Status | Should -Be 'Info'
            $remoteDesktop.Value | Should -Be 'Enabled'
            $remoteDesktop.Recommendation | Should -Match 'Remote Desktop'
        }

        It 'reports Unknown when a registry value cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue { }
            $results = Get-SecurityHealth
            ($results | Where-Object Check -eq 'User Account Control').Value | Should -Be 'Unknown'
            ($results | Where-Object Check -eq 'Remote Desktop').Value | Should -Be 'Unknown'
        }

        It 'reports a local administrator as information with advice' {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministratorMember { $true }
            $account = Get-SecurityHealth | Where-Object Check -eq 'Account type'
            $account.Status | Should -Be 'Info'
            $account.Value | Should -Be 'Administrator'
            $account.Recommendation | Should -Match 'standard account'
        }
    }

    Context 'tamper protection, local accounts and shared folders' {
        It 'is a Warning when tamper protection is off' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderStatus {
                [PSCustomObject]@{
                    RealTimeProtectionEnabled = $true; AntivirusEnabled = $true; QuickScanAge = 0; IsTamperProtected = $false
                    AntivirusSignatureAge = 0; AntivirusSignatureLastUpdated = Get-Date
                }
            }
            $tamper = Get-SecurityHealth | Where-Object Check -eq 'Tamper protection'
            $tamper.Status | Should -Be 'Warning'
            $tamper.Recommendation | Should -Match 'Tamper Protection'
        }

        It 'is a Warning when the Guest account is enabled' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_UserAccount' } {
                [PSCustomObject]@{ Name = 'Gast'; SID = 'S-1-5-21-1-2-3-501'; Disabled = $false }
                [PSCustomObject]@{ Name = 'm.horvat'; SID = 'S-1-5-21-1-2-3-1001'; Disabled = $false }
            }
            $results = Get-SecurityHealth
            ($results | Where-Object Check -eq 'Guest account').Status | Should -Be 'Warning'
            ($results | Where-Object Check -eq 'Local accounts').Value | Should -Be '2 enabled: Gast, m.horvat'
        }

        It 'reports an enabled built-in Administrator account as information with advice' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_UserAccount' } {
                [PSCustomObject]@{ Name = 'Administrator'; SID = 'S-1-5-21-1-2-3-500'; Disabled = $false }
            }
            $administrator = Get-SecurityHealth | Where-Object Check -eq 'Built-in Administrator account'
            $administrator.Status | Should -Be 'Info'
            $administrator.Value | Should -Be 'Enabled'
            $administrator.Recommendation | Should -Match 'UAC'
        }

        It 'lists folders the user shared, but not the hidden administrative shares' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Share' } {
                [PSCustomObject]@{ Name = 'C$'; Path = 'C:\'; Type = 2147483648 }
                [PSCustomObject]@{ Name = 'Scans'; Path = 'D:\Scans'; Type = 0 }
                [PSCustomObject]@{ Name = 'Archive$'; Path = 'D:\Archive'; Type = 0 }
            }
            $shares = Get-SecurityHealth | Where-Object Check -eq 'Shared folders'
            $shares.Status | Should -Be 'Info'
            $shares.Value | Should -Be '1: Scans (D:\Scans)'
            $shares.Recommendation | Should -Match 'Stop sharing'
        }

        It 'reports the accounts as unavailable when they cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_UserAccount' } { throw 'Query failed' }
            (Get-SecurityHealth | Where-Object Check -eq 'Local accounts').Value | Should -Be 'Unavailable'
        }
    }

    Context 'threat history, administrators and automatic sign-in' {
        It 'is Critical while a threat is still active' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderThreat {
                [PSCustomObject]@{ Name = 'Trojan:Win32/Test'; IsActive = $true }
                [PSCustomObject]@{ Name = 'PUA:Win32/Old'; IsActive = $false }
            }
            $threats = Get-SecurityHealth | Where-Object Check -eq 'Threat history'
            $threats.Status | Should -Be 'Critical'
            $threats.Value | Should -Be '1 active: Trojan:Win32/Test'
            $threats.Recommendation | Should -Match 'full scan'
        }

        It 'reports threats that were handled as information, the first three in the value' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderThreat {
                'One', 'Two', 'Three', 'Four' | ForEach-Object { [PSCustomObject]@{ Name = "PUA:Win32/$_"; IsActive = $false } }
            }
            $threats = Get-SecurityHealth | Where-Object Check -eq 'Threat history'
            $threats.Status | Should -Be 'Info'
            $threats.Value | Should -Be '4 found earlier and handled: PUA:Win32/One, PUA:Win32/Two, PUA:Win32/Three and 1 more'
            $threats.Details | Should -Be @('PUA:Win32/Four')
        }

        It 'reports the threat history as unavailable when Defender cannot be asked' {
            Mock -ModuleName HelpdeskToolkit Get-DefenderThreat { throw 'The Defender module is not installed' }
            (Get-SecurityHealth | Where-Object Check -eq 'Threat history').Value | Should -Be 'Unavailable'
        }

        It 'is a Warning when Windows signs in automatically' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'AutoAdminLogon' } { '1' }
            $autoSignIn = Get-SecurityHealth | Where-Object Check -eq 'Automatic sign-in'
            $autoSignIn.Status | Should -Be 'Warning'
            $autoSignIn.Recommendation | Should -Match 'netplwiz'
        }

        It 'treats a missing automatic sign-in setting as disabled' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'AutoAdminLogon' } { }
            (Get-SecurityHealth | Where-Object Check -eq 'Automatic sign-in').Status | Should -Be 'OK'
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
                [PSCustomObject]@{ DriveLetter = 'C:'; ProtectionStatus = 1 }
            }
            Mock -ModuleName HelpdeskToolkit Get-SignInEvent { }
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
                [PSCustomObject]@{ DriveLetter = 'C:'; ProtectionStatus = 0 }
            }
            $bitLocker = Get-SecurityHealth | Where-Object Check -like 'BitLocker*'
            $bitLocker.Status | Should -Be 'Info'
            $bitLocker.Value | Should -Be 'Protection off'
            $bitLocker.Recommendation | Should -Match 'BitLocker'
        }

        It 'reports every drive, not only the system drive' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_EncryptableVolume' } {
                [PSCustomObject]@{ DriveLetter = 'D:'; ProtectionStatus = 0 }
                [PSCustomObject]@{ DriveLetter = 'C:'; ProtectionStatus = 1 }
                [PSCustomObject]@{ DriveLetter = $null; ProtectionStatus = 0 }
            }
            $bitLocker = @(Get-SecurityHealth | Where-Object Check -like 'BitLocker*')
            $bitLocker.Check | Should -Be @('BitLocker (C:)', 'BitLocker (D:)')
            $bitLocker.Value | Should -Be @('Protection on', 'Protection off')
        }

        It 'reports no failed sign-ins and no lockouts as OK' {
            $results = Get-SecurityHealth
            $failed = $results | Where-Object Check -eq 'Failed sign-ins'
            $failed.Status | Should -Be 'OK'
            $failed.Value | Should -Be '0 in the last 7 days'
            $failed.Allowed | Should -Be '0 - 20'
            ($results | Where-Object Check -eq 'Account lockouts').Value | Should -Be '0 in the last 7 days'
        }

        It 'counts failed sign-ins and names the accounts they were for' {
            Mock -ModuleName HelpdeskToolkit Get-SignInEvent -ParameterFilter { $Kind -eq 'FailedSignIn' } {
                'm.horvat', 'm.horvat', 'm.horvat', 'administrator'
            }
            $failed = Get-SecurityHealth | Where-Object Check -eq 'Failed sign-ins'
            $failed.Status | Should -Be 'OK'
            $failed.Value | Should -Be '4 in the last 7 days, most for: m.horvat (3), administrator (1)'
        }

        It 'is a Warning when there are more failed sign-ins than the limit' {
            Mock -ModuleName HelpdeskToolkit Get-SignInEvent -ParameterFilter { $Kind -eq 'FailedSignIn' } { 1..25 | ForEach-Object { 'm.horvat' } }
            $failed = Get-SecurityHealth | Where-Object Check -eq 'Failed sign-ins'
            $failed.Status | Should -Be 'Warning'
            $failed.Recommendation | Should -Match 'guessing the password'
        }

        It 'is a Warning when an account was locked out' {
            Mock -ModuleName HelpdeskToolkit Get-SignInEvent -ParameterFilter { $Kind -eq 'Lockout' } { 'm.horvat', 'm.horvat' }
            $lockouts = Get-SecurityHealth | Where-Object Check -eq 'Account lockouts'
            $lockouts.Status | Should -Be 'Warning'
            $lockouts.Value | Should -Be '2 in the last 7 days: m.horvat'
        }

        It 'looks back the requested number of days in the Security log' {
            Get-SecurityHealth -Days 30 | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-SignInEvent -ParameterFilter {
                $Kind -eq 'FailedSignIn' -and [math]::Abs(($Since - (Get-Date).AddDays(-30)).TotalMinutes) -lt 5
            }
        }

        It 'reports BitLocker as not available when the volume is not found' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_EncryptableVolume' } { }
            (Get-SecurityHealth | Where-Object Check -like 'BitLocker*').Value | Should -Be 'Not available on this system'
        }
    }
}
