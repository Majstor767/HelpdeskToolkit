function Get-WindowsSupportInfo {
    <#
    .SYNOPSIS
        Decides whether a Windows version still receives security updates.
    .DESCRIPTION
        Compares the Windows version of the computer with the end-of-support dates in
        Config\Thresholds.psd1 and returns the status, value and recommendation of the
        "Windows support" check.

        - Windows 10 has one end date for all editions.
        - Windows 11 is supported per feature release (24H2, 25H2, ...). Home and Pro
          get 24 months, Enterprise and Education 36 months.
        - Server and long-term servicing (LTSC) editions follow other rules and are not
          judged.

        The function has no access to the system: everything comes in as parameters,
        which makes it easy to test.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # For example "Microsoft Windows 11 Pro"
        [Parameter(Mandatory)]
        [string]$Caption,

        [Parameter(Mandatory)]
        [int]$BuildNumber,

        # Feature release, for example "24H2"; empty when unknown.
        [AllowEmptyString()]
        [string]$DisplayVersion = '',

        # 1 = workstation; domain controllers and servers have other values.
        [int]$ProductType = 1
    )

    $support = (Get-HealthThreshold).WindowsSupport
    $today = (Get-Date).Date
    $info = @{ Status = 'Info'; Value = ''; Recommendation = '' }

    if ($ProductType -ne 1) {
        $info.Value = 'Server edition: not checked'
        return $info
    }
    if ($Caption -match 'LTSC|LTSB') {
        $info.Value = 'Long-term servicing edition: has its own support dates'
        return $info
    }

    # Windows 11 starts at build 22000; everything below is Windows 10.
    if ($BuildNumber -lt 22000) {
        $end = [datetime]::ParseExact($support.Windows10End, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        $upgradeAdvice = 'Upgrade to Windows 11 if the hardware allows it; otherwise enroll the computer in Extended Security Updates or replace it.'
    }
    else {
        # "Pro Education" belongs to the Home and Pro group, so Pro is tested first.
        $table = if ($Caption -notmatch 'Pro' -and $Caption -match 'Enterprise|Education') { $support.Enterprise } else { $support.HomePro }

        if (-not $DisplayVersion -or -not $table.ContainsKey($DisplayVersion)) {
            $info.Value = if ($DisplayVersion) { 'No end date known for version {0}' -f $DisplayVersion } else { 'Version unknown' }
            return $info
        }
        $end = [datetime]::ParseExact($table[$DisplayVersion], 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        $upgradeAdvice = 'Install the newest feature update: Settings > Windows Update.'
    }

    $daysLeft = [int]($end - $today).TotalDays

    if ($daysLeft -lt 0) {
        $info.Status = 'Critical'
        $info.Value = 'Out of support since {0:yyyy-MM-dd}' -f $end
        $info.Recommendation = 'This Windows version no longer receives security updates. {0}' -f $upgradeAdvice
    }
    elseif ($daysLeft -lt $support.WarningDaysBeforeEnd) {
        $info.Status = 'Warning'
        $info.Value = 'Supported until {0:yyyy-MM-dd} ({1} days left)' -f $end, $daysLeft
        $info.Recommendation = 'Support for this Windows version ends soon. {0}' -f $upgradeAdvice
    }
    else {
        $info.Status = 'OK'
        $info.Value = 'Supported until {0:yyyy-MM-dd}' -f $end
    }

    $info
}
