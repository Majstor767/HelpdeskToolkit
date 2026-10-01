function Get-SystemHealth {
    <#
    .SYNOPSIS
        Collects basic system information and checks uptime, activation and startup programs.
    .DESCRIPTION
        Reports the computer name, operating system version and build, manufacturer
        and model, domain or workgroup, the signed-in user and the Windows install
        date, and checks three things:

        - Uptime above the limit in Config\Thresholds.psd1 (7 days by default) is a
          Warning, because a long-running machine is a common cause of slowness and
          of updates that never finish installing.
        - Windows that is not activated is a Warning.
        - More startup programs than the configured limit is a Warning, because they
          slow down sign-in.

        Everything is read through CIM (WMI) and the registry, so no administrator
        rights are needed and nothing on the system is changed.
    .EXAMPLE
        Get-SystemHealth

        Returns one result object per check in the System category.
    .EXAMPLE
        Get-SystemHealth | Where-Object Status -ne 'Info'

        Shows only the checks that have an actual verdict (OK, Warning or Critical).
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'System'
    $thresholds = Get-HealthThreshold

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    }
    catch {
        New-FailureResult -Category $category -Check 'System information' -ErrorRecord $_
        return
    }

    New-CheckResult -Category $category -Check 'Computer name' -Status Info -Value $computer.Name

    $displayVersion = Get-OSDisplayVersion
    $osValue = if ($displayVersion) {
        '{0} {1} (build {2})' -f $os.Caption, $displayVersion, $os.BuildNumber
    }
    else {
        '{0} (build {1})' -f $os.Caption, $os.BuildNumber
    }
    New-CheckResult -Category $category -Check 'Operating system' -Status Info -Value $osValue

    if ($os.InstallDate) {
        New-CheckResult -Category $category -Check 'Windows installed' -Status Info -Value ('{0:yyyy-MM-dd}' -f $os.InstallDate)
    }

    New-CheckResult -Category $category -Check 'Manufacturer and model' -Status Info `
        -Value ('{0} {1}' -f $computer.Manufacturer, $computer.Model)

    $membership = if ($computer.PartOfDomain) { 'Domain: {0}' -f $computer.Domain } else { 'Workgroup: {0}' -f $computer.Domain }
    New-CheckResult -Category $category -Check 'Domain or workgroup' -Status Info -Value $membership

    # UserName is empty in remote sessions; the environment always knows who runs the tool.
    $user = if ($computer.UserName) { $computer.UserName } else { '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME }
    New-CheckResult -Category $category -Check 'Signed-in user' -Status Info -Value $user

    New-CheckResult -Category $category -Check 'Time zone' -Status Info -Value ([System.TimeZoneInfo]::Local.DisplayName)

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeValue = '{0} d {1} h {2} min' -f [int][math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes
    $status = Get-ThresholdStatus -Value $uptime.TotalDays -Warning $thresholds.Uptime.WarningDays
    $recommendation = if ($status -eq 'Warning') {
        'Restart the computer; it has been running for more than {0} days. Use Restart, not Shut down: with Fast Startup enabled a shutdown does not reset the uptime.' -f $thresholds.Uptime.WarningDays
    }
    else {
        ''
    }
    New-CheckResult -Category $category -Check 'Uptime' -Status $status -Value $uptimeValue -Recommendation $recommendation `
        -Allowed (Format-AllowedRange -Warning $thresholds.Uptime.WarningDays -Unit 'days') -Typical $thresholds.Uptime.Typical

    # Activation. The filter selects the Windows license that has a product key installed;
    # LicenseStatus 1 means licensed.
    try {
        $filter = "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"
        $license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $filter -ErrorAction Stop | Select-Object -First 1

        if ($license -and $license.LicenseStatus -eq 1) {
            New-CheckResult -Category $category -Check 'Windows activation' -Status OK -Value 'Activated'
        }
        else {
            New-CheckResult -Category $category -Check 'Windows activation' -Status Warning -Value 'Not activated' `
                -Recommendation 'Windows is not activated. Open Settings > System > Activation to see the reason and activate it.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Windows activation' -ErrorRecord $_
    }

    # Startup programs
    try {
        # Some entries carry a generated suffix (Name_0123ABCD...); it is removed for readability.
        $programs = @(Get-CimInstance -ClassName Win32_StartupCommand -ErrorAction Stop |
                ForEach-Object { [string]$_.Name -replace '_[0-9A-Fa-f]{16,}$', '' } | Sort-Object -Unique)

        # The first few names go into the value; the rest is kept as details, which
        # the HTML report shows in an expandable list.
        $shown = 8
        $remaining = @($programs | Select-Object -Skip $shown)
        $value = '{0} programs' -f $programs.Count
        if ($programs.Count -gt 0) {
            $value = '{0}: {1}' -f $value, (($programs | Select-Object -First $shown) -join ', ')
        }
        if ($remaining.Count -gt 0) {
            $value = '{0} and {1} more' -f $value, $remaining.Count
        }

        $status = Get-ThresholdStatus -Value $programs.Count -Warning $thresholds.Startup.WarningProgramCount
        $recommendation = if ($status -ne 'OK') {
            'Many programs start together with Windows, which slows down sign-in. Turn off the ones that are not needed in Task Manager > Startup apps.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Startup programs' -Status $status -Value $value -Recommendation $recommendation `
            -Details $remaining -Allowed (Format-AllowedRange -Warning $thresholds.Startup.WarningProgramCount) -Typical $thresholds.Startup.Typical
    }
    catch {
        New-FailureResult -Category $category -Check 'Startup programs' -ErrorRecord $_
    }
}
