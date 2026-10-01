function Get-SecurityHealth {
    <#
    .SYNOPSIS
        Checks Microsoft Defender, the firewall, UAC, Remote Desktop, Secure Boot, TPM and BitLocker.
    .DESCRIPTION
        - Defender real-time protection. When it is off because a third-party
          antivirus is registered in Windows Security Center, that is reported as
          information instead of a problem.
        - Age of the antivirus definitions, tamper protection and time since the last
          quick scan.
        - State of the Domain, Private and Public firewall profiles.
        - User Account Control, Remote Desktop and whether the signed-in user is a
          local administrator.
        - Local accounts (with a warning for an enabled Guest account) and folders
          shared on the network.
        - Secure Boot state.
        - TPM presence and version, and BitLocker protection of the system drive.
          Windows only exposes these two to administrators, so without elevation
          they are skipped and marked "Requires admin".

        Nothing is changed on the system. The limits come from Config\Thresholds.psd1.
    .EXAMPLE
        Get-SecurityHealth

        Returns the security results for the local computer.
    .EXAMPLE
        Get-SecurityHealth | Where-Object Status -in 'Warning', 'Critical'

        Shows only the security findings that need attention.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'Security'
    $thresholds = (Get-HealthThreshold).Defender

    # Microsoft Defender
    try {
        $defender = Get-DefenderStatus

        if ($defender.RealTimeProtectionEnabled) {
            New-CheckResult -Category $category -Check 'Defender real-time protection' -Status OK -Value 'Enabled'
        }
        else {
            $otherProducts = @(Get-AntivirusProduct | Where-Object { $_ -notmatch 'Defender' })
            if ($otherProducts.Count -gt 0) {
                New-CheckResult -Category $category -Check 'Defender real-time protection' -Status Info `
                    -Value ('Disabled (third-party antivirus: {0})' -f ($otherProducts -join ', '))
            }
            else {
                New-CheckResult -Category $category -Check 'Defender real-time protection' -Status Critical -Value 'Disabled' `
                    -Recommendation 'No active antivirus was found. Turn on real-time protection in Windows Security > Virus & threat protection.'
            }
        }

        # Definitions are only kept up to date while Defender is the active antivirus.
        if ($defender.AntivirusEnabled) {
            $age = [int]$defender.AntivirusSignatureAge
            $status = Get-ThresholdStatus -Value $age -Warning $thresholds.SignatureWarningDays -Critical $thresholds.SignatureCriticalDays
            $recommendation = if ($status -ne 'OK') {
                'Antivirus definitions are out of date. Open Windows Security > Virus & threat protection > Protection updates and check for updates.'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Defender definitions' -Status $status `
                -Value ('{0} {1} old (updated {2:yyyy-MM-dd HH:mm})' -f $age, $(if ($age -eq 1) { 'day' } else { 'days' }), $defender.AntivirusSignatureLastUpdated) `
                -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.SignatureWarningDays -Critical $thresholds.SignatureCriticalDays -Unit 'days') `
                -Typical $thresholds.Typical

            # Tamper protection stops programs (and malware) from switching Defender off.
            if ($defender.IsTamperProtected) {
                New-CheckResult -Category $category -Check 'Tamper protection' -Status OK -Value 'Enabled'
            }
            else {
                New-CheckResult -Category $category -Check 'Tamper protection' -Status Warning -Value 'Disabled' `
                    -Recommendation 'Without tamper protection a program can switch off the antivirus. Turn it on in Windows Security > Virus & threat protection > Manage settings > Tamper Protection.'
            }

            # Last quick scan. Defender reports 4294967295 when it has never scanned.
            $neverScanned = 4294967295
            $scanAge = [double]$defender.QuickScanAge
            $scanAllowed = Format-AllowedRange -Warning $thresholds.ScanWarningDays -Unit 'days'
            $scanAdvice = 'Run a scan: open Windows Security > Virus & threat protection and choose "Quick scan".'
            if ($scanAge -ge $neverScanned) {
                New-CheckResult -Category $category -Check 'Defender last scan' -Status Warning -Value 'Never' `
                    -Recommendation ('The computer has never been scanned. {0}' -f $scanAdvice) -Allowed $scanAllowed -Typical $thresholds.TypicalScan
            }
            else {
                $status = Get-ThresholdStatus -Value $scanAge -Warning $thresholds.ScanWarningDays
                $recommendation = if ($status -ne 'OK') { 'The last scan was a long time ago. {0}' -f $scanAdvice } else { '' }
                New-CheckResult -Category $category -Check 'Defender last scan' -Status $status `
                    -Value ('{0} {1} ago' -f $scanAge, $(if ($scanAge -eq 1) { 'day' } else { 'days' })) `
                    -Recommendation $recommendation -Allowed $scanAllowed -Typical $thresholds.TypicalScan
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Microsoft Defender' -ErrorRecord $_
    }

    # Firewall profiles
    try {
        $firewallProfiles = @(Get-FirewallProfileState)
        foreach ($firewallProfile in $firewallProfiles) {
            $check = 'Firewall - {0} profile' -f $firewallProfile.Name
            if ($firewallProfile.Enabled) {
                New-CheckResult -Category $category -Check $check -Status OK -Value 'Enabled'
            }
            else {
                New-CheckResult -Category $category -Check $check -Status Warning -Value 'Disabled' `
                    -Recommendation 'Turn on Windows Defender Firewall for this profile (Windows Security > Firewall & network protection), unless a third-party firewall is installed.'
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Firewall' -ErrorRecord $_
    }

    # User Account Control. EnableLUA = 0 switches UAC off completely.
    $uac = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA'
    if ($null -eq $uac) {
        New-CheckResult -Category $category -Check 'User Account Control' -Status Info -Value 'Unknown'
    }
    elseif ($uac -eq 0) {
        New-CheckResult -Category $category -Check 'User Account Control' -Status Critical -Value 'Disabled' `
            -Recommendation 'With UAC off every program runs with full rights without asking. Turn it on: Control Panel > User Accounts > Change User Account Control settings, move the slider up and restart the computer.'
    }
    else {
        New-CheckResult -Category $category -Check 'User Account Control' -Status OK -Value 'Enabled'
    }

    # Remote Desktop. fDenyTSConnections = 0 means incoming connections are accepted.
    $denyRemoteDesktop = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections'
    if ($null -eq $denyRemoteDesktop) {
        New-CheckResult -Category $category -Check 'Remote Desktop' -Status Info -Value 'Unknown'
    }
    elseif ($denyRemoteDesktop -eq 0) {
        New-CheckResult -Category $category -Check 'Remote Desktop' -Status Info -Value 'Enabled' `
            -Recommendation 'The computer accepts Remote Desktop connections. If nobody needs to connect to it remotely, turn it off in Settings > System > Remote Desktop.'
    }
    else {
        New-CheckResult -Category $category -Check 'Remote Desktop' -Status OK -Value 'Disabled'
    }

    # Account type of the user running the tool
    if (Test-IsAdministratorMember) {
        New-CheckResult -Category $category -Check 'Account type' -Status Info -Value 'Administrator' `
            -Recommendation 'The signed-in user is a local administrator, so malware started by this user can take over the whole computer. For daily work a standard account is safer.'
    }
    else {
        New-CheckResult -Category $category -Check 'Account type' -Status OK -Value 'Standard user'
    }

    # Local accounts. The built-in accounts are recognized by the end of their security
    # identifier (SID), because their names are translated and can be renamed.
    try {
        $accounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount = True' -ErrorAction Stop)

        $enabled = @($accounts | Where-Object { -not $_.Disabled } | ForEach-Object { $_.Name })
        New-CheckResult -Category $category -Check 'Local accounts' -Status Info `
            -Value ('{0} enabled: {1}' -f $enabled.Count, $(if ($enabled.Count -gt 0) { $enabled -join ', ' } else { 'none' }))

        $guest = $accounts | Where-Object { $_.SID -like '*-501' } | Select-Object -First 1
        if ($guest -and -not $guest.Disabled) {
            New-CheckResult -Category $category -Check 'Guest account' -Status Warning -Value 'Enabled' `
                -Recommendation 'Anyone can sign in with the Guest account without a password. An administrator should disable it: Computer Management > Local Users and Groups > Users > Guest > "Account is disabled".'
        }
        else {
            New-CheckResult -Category $category -Check 'Guest account' -Status OK -Value 'Disabled'
        }

        $builtInAdministrator = $accounts | Where-Object { $_.SID -like '*-500' } | Select-Object -First 1
        if ($builtInAdministrator -and -not $builtInAdministrator.Disabled) {
            New-CheckResult -Category $category -Check 'Built-in Administrator account' -Status Info -Value 'Enabled' `
                -Recommendation 'The built-in Administrator account is a well-known target and is not protected by UAC prompts. Use a separate administrator account and keep this one disabled.'
        }
        else {
            New-CheckResult -Category $category -Check 'Built-in Administrator account' -Status OK -Value 'Disabled'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Local accounts' -ErrorRecord $_
    }

    # Folders shared on the network. Type 0 is a disk share; names ending in $ are the
    # hidden administrative shares that Windows creates itself.
    try {
        $shares = @(Get-CimInstance -ClassName Win32_Share -ErrorAction Stop |
                Where-Object { $_.Type -eq 0 -and $_.Name -notlike '*$' } |
                ForEach-Object { '{0} ({1})' -f $_.Name, $_.Path })

        if ($shares.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Shared folders' -Status OK -Value 'None'
        }
        else {
            New-CheckResult -Category $category -Check 'Shared folders' -Status Info -Value ('{0}: {1}' -f $shares.Count, ($shares -join ', ')) `
                -Recommendation 'These folders can be reached from other computers on the network. Stop sharing the ones that are no longer needed: right-click the folder > Properties > Sharing.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Shared folders' -ErrorRecord $_
    }

    # Secure Boot
    switch (Get-SecureBootState) {
        'Enabled' {
            New-CheckResult -Category $category -Check 'Secure Boot' -Status OK -Value 'Enabled'
        }
        'Disabled' {
            New-CheckResult -Category $category -Check 'Secure Boot' -Status Info -Value 'Disabled' `
                -Recommendation 'Secure Boot protects the startup process from tampering and is required by Windows 11. It can be turned on in the UEFI firmware settings.'
        }
        default {
            New-CheckResult -Category $category -Check 'Secure Boot' -Status Info -Value 'Not supported (legacy BIOS mode)'
        }
    }

    # TPM (administrators only; without elevation the query just waits and fails)
    if (-not (Test-IsAdministrator)) {
        New-AdminRequiredResult -Category $category -Check 'TPM'
    }
    else {
        try {
            $tpm = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop |
                Select-Object -First 1

            if (-not $tpm) {
                New-CheckResult -Category $category -Check 'TPM' -Status Info -Value 'Not present' `
                    -Recommendation 'No TPM was found. Windows 11 and BitLocker need TPM 2.0; it can often be enabled in the UEFI firmware settings.'
            }
            else {
                # SpecVersion looks like "2.0, 0, 1.59"; the first part is the TPM version.
                $version = ([string]$tpm.SpecVersion -split ',')[0].Trim()
                if ($tpm.IsEnabled_InitialValue) {
                    New-CheckResult -Category $category -Check 'TPM' -Status OK -Value ('Enabled, version {0}' -f $version)
                }
                else {
                    New-CheckResult -Category $category -Check 'TPM' -Status Warning -Value ('Present but disabled, version {0}' -f $version) `
                        -Recommendation 'Enable the TPM in the UEFI firmware settings.'
                }
            }
        }
        catch {
            New-FailureResult -Category $category -Check 'TPM' -ErrorRecord $_
        }
    }

    # BitLocker on the system drive (administrators only)
    $check = 'BitLocker ({0})' -f $env:SystemDrive
    if (-not (Test-IsAdministrator)) {
        New-AdminRequiredResult -Category $category -Check $check
    }
    else {
        try {
            $volume = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftVolumeEncryption' `
                -ClassName Win32_EncryptableVolume -Filter ("DriveLetter = '{0}'" -f $env:SystemDrive) -ErrorAction Stop

            if (-not $volume) {
                New-CheckResult -Category $category -Check $check -Status Info -Value 'Not available on this system'
            }
            elseif ($volume.ProtectionStatus -eq 1) {
                New-CheckResult -Category $category -Check $check -Status OK -Value 'Protection on'
            }
            else {
                New-CheckResult -Category $category -Check $check -Status Info -Value 'Protection off' `
                    -Recommendation 'The system drive is not encrypted. Consider turning on BitLocker, especially on laptops.'
            }
        }
        catch {
            New-FailureResult -Category $category -Check $check -ErrorRecord $_
        }
    }
}
