function Get-WindowsUpdateHealth {
    <#
    .SYNOPSIS
        Reports the last installed Windows update and whether a restart is pending.
    .DESCRIPTION
        - Last installed update: the newest entry returned by Get-HotFix. A Warning is
          raised when nothing was installed for longer than the limit in
          Config\Thresholds.psd1 (45 days by default), which usually means Windows
          Update is stuck or disabled.
        - Pending restart: Windows needs a restart to finish installing updates.

        Nothing is installed, downloaded or changed, and no administrator rights are
        needed.
    .EXAMPLE
        Get-WindowsUpdateHealth

        Returns the two Windows Update results.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'Windows Update'
    $thresholds = (Get-HealthThreshold).WindowsUpdate

    try {
        # Some entries have no install date; they cannot be ordered, so they are skipped.
        $latest = Get-HotFix -ErrorAction Stop |
            Where-Object { $_.InstalledOn } |
            Sort-Object -Property InstalledOn -Descending |
            Select-Object -First 1

        if (-not $latest) {
            New-CheckResult -Category $category -Check 'Last installed update' -Status Info -Value 'No update history found'
        }
        else {
            $daysAgo = [int][math]::Floor(((Get-Date) - $latest.InstalledOn).TotalDays)
            $status = Get-ThresholdStatus -Value $daysAgo -Warning $thresholds.WarningDaysSinceLastUpdate
            $recommendation = if ($status -ne 'OK') {
                'No update was installed for more than {0} days. Open Settings > Windows Update and check for updates.' -f $thresholds.WarningDaysSinceLastUpdate
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Last installed update' -Status $status `
                -Value ('{0} on {1:yyyy-MM-dd} ({2} days ago)' -f $latest.HotFixID, $latest.InstalledOn, $daysAgo) `
                -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.WarningDaysSinceLastUpdate -Unit 'days') -Typical $thresholds.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Last installed update' -ErrorRecord $_
    }

    try {
        $reasons = @(Get-PendingRebootReason)
        if ($reasons.Count -gt 0) {
            New-CheckResult -Category $category -Check 'Pending restart' -Status Warning `
                -Value ('Yes ({0})' -f ($reasons -join ', ')) `
                -Recommendation 'Restart the computer to finish installing updates.'
        }
        else {
            New-CheckResult -Category $category -Check 'Pending restart' -Status OK -Value 'No'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Pending restart' -ErrorRecord $_
    }
}
