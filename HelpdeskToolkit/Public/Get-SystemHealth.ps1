function Get-SystemHealth {
    <#
    .SYNOPSIS
        Collects basic system information and checks the uptime.
    .DESCRIPTION
        Reads the computer name, operating system version and build, manufacturer,
        model and the time since the last boot. Everything is read through CIM (WMI)
        and the registry, so no administrator rights are needed and nothing on the
        system is changed.

        Uptime above the limit in Config\Thresholds.psd1 (7 days by default) is
        reported as a Warning, because a long-running machine is a common cause of
        slowness and of updates that never finish installing.
    .EXAMPLE
        Get-SystemHealth

        Returns one result object per check in the System category.
    .EXAMPLE
        Get-SystemHealth | Where-Object Status -ne 'Info'

        Shows only the checks that have an actual verdict (OK, Warning or Critical).
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Status, Value and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'System'
    $threshold = (Get-HealthThreshold).Uptime

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    }
    catch {
        New-CheckResult -Category $category -Check 'System information' -Status Warning -Value 'Unavailable' `
            -Recommendation "CIM/WMI query failed: $($_.Exception.Message)"
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

    New-CheckResult -Category $category -Check 'Manufacturer and model' -Status Info `
        -Value ('{0} {1}' -f $computer.Manufacturer, $computer.Model)

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeValue = '{0} d {1} h {2} min' -f [int][math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes
    if ($uptime.TotalDays -gt $threshold.WarningDays) {
        New-CheckResult -Category $category -Check 'Uptime' -Status Warning -Value $uptimeValue `
            -Recommendation ('Restart the computer; it has been running for more than {0} days. Use Restart, not Shut down: with Fast Startup enabled a shutdown does not reset the uptime.' -f $threshold.WarningDays)
    }
    else {
        New-CheckResult -Category $category -Check 'Uptime' -Status OK -Value $uptimeValue
    }
}
