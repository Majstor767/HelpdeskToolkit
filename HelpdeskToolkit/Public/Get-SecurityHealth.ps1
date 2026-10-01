function Get-SecurityHealth {
    <#
    .SYNOPSIS
        Checks Microsoft Defender, the Windows firewall profiles and BitLocker.
    .DESCRIPTION
        - Defender real-time protection. When it is off because a third-party
          antivirus is registered in Windows Security Center, that is reported as
          information instead of a problem.
        - Age of the antivirus definitions.
        - State of the Domain, Private and Public firewall profiles.
        - BitLocker protection of the system drive. Windows only exposes this to
          administrators, so without elevation the check is skipped and marked
          "Requires admin".

        Nothing is changed on the system. The limits come from Config\Thresholds.psd1.
    .EXAMPLE
        Get-SecurityHealth

        Returns the security results for the local computer.
    .EXAMPLE
        Get-SecurityHealth | Where-Object Status -in 'Warning', 'Critical'

        Shows only the security findings that need attention.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Status, Value and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'Security'
    $thresholds = (Get-HealthThreshold).Defender

    # Microsoft Defender
    try {
        $defender = Get-MpComputerStatus -ErrorAction Stop

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
                -Recommendation $recommendation
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Microsoft Defender' -ErrorRecord $_
    }

    # Firewall profiles
    try {
        $firewallProfiles = @(Get-NetFirewallProfile -ErrorAction Stop)
        foreach ($firewallProfile in $firewallProfiles) {
            $check = 'Firewall - {0} profile' -f $firewallProfile.Name
            # Enabled is an enum on Windows PowerShell 5.1; comparing as text works everywhere.
            if ([string]$firewallProfile.Enabled -eq 'True') {
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
