function Get-WindowsUpdateHealth {
    <#
    .SYNOPSIS
        Reports the last installed Windows update, a pending restart, paused, pending and failed updates.
    .DESCRIPTION
        - Last installed update: the newest entry returned by Get-HotFix. A Warning is
          raised when nothing was installed for longer than the limit in
          Config\Thresholds.psd1 (45 days by default), which usually means Windows
          Update is stuck or disabled.
        - Pending restart: Windows needs a restart to finish installing updates.
        - Updates paused: Windows Update was paused in Settings and installs nothing
          until the pause ends.
        - Pending updates: updates Windows has found but not installed yet. The answer
          comes from the last search Windows made itself; no new search is started.
        - Failed updates: updates whose last installation attempt in the past 30 days
          failed, with the error code. They are a Warning.

        Nothing is installed, downloaded or changed, and no administrator rights are
        needed.
    .EXAMPLE
        Get-WindowsUpdateHealth

        Returns the Windows Update results.
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

    # Paused updates. "Pause updates" in Settings stores the date until which Windows
    # Update is paused, for example 2026-10-20T09:00:00Z.
    $pausedUntil = $null
    $pauseValue = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' -Name 'PauseUpdatesExpiryTime'
    if ($pauseValue) {
        try {
            $pausedUntil = [datetime]::Parse($pauseValue, [cultureinfo]::InvariantCulture)
        }
        catch {
            Write-Verbose "Unreadable pause date: $pauseValue"
        }
    }

    if ($pausedUntil -and $pausedUntil -gt (Get-Date)) {
        New-CheckResult -Category $category -Check 'Updates paused' -Status Warning `
            -Value ('Yes, until {0:yyyy-MM-dd}' -f $pausedUntil) `
            -Recommendation 'Windows Update is paused, so security updates are not installed. Open Settings > Windows Update and choose "Resume updates".'
    }
    else {
        New-CheckResult -Category $category -Check 'Updates paused' -Status OK -Value 'No'
    }

    # Updates that Windows has found but not installed yet
    try {
        $pending = @(Get-PendingUpdate)
        if ($pending.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Pending updates' -Status OK -Value 'None'
        }
        else {
            $list = ConvertTo-ListValue -Item $pending -Label 'update' -Shown 3
            New-CheckResult -Category $category -Check 'Pending updates' -Status Info -Value $list.Value -Details $list.Details `
                -Recommendation 'Windows has found updates that are not installed yet. Install them in Settings > Windows Update.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Pending updates' -ErrorRecord $_
    }

    # Updates that failed to install. Windows Update writes event 19 for every update
    # it installed and event 20 for every attempt that failed. Windows tries again by
    # itself, so an update only counts as failed when its last attempt failed.
    try {
        try {
            $filter = @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-WindowsUpdateClient'
                Id           = 19, 20
                StartTime    = (Get-Date).AddDays(-$thresholds.FailedDays)
            }
            $events = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
        catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                throw
            }
            $events = @()
        }

        # Last result per kind of update, oldest event first. A failed event carries the
        # error code and then the title; an installed event starts with the title.
        #
        # Updates of one kind replace each other: the security update of September
        # contains the one of August, and antivirus definitions get a new version
        # number several times a day. The month, the KB number and the version are
        # therefore removed from the title to tell the kind, so a newer release that
        # installed counts for an older one that failed.
        $lastResult = [ordered]@{}
        foreach ($entry in ($events | Sort-Object -Property TimeCreated)) {
            $failed = $entry.Id -eq 20
            $title = if ($failed) { [string]$entry.Properties[1].Value } else { [string]$entry.Properties[0].Value }
            $kind = ($title -replace '^\d{4}-\d{2}\s+', '' -replace '\s*\((KB\d+|Version [\d.]+|[\d.]+)\)', '').Trim()

            $lastResult[$kind] = if ($failed) {
                '{0} (error 0x{1:X8})' -f $title.Trim(), [int]$entry.Properties[0].Value
            }
            else {
                ''
            }
        }

        $stillFailing = @($lastResult.Values | Where-Object { $_ })
        if ($stillFailing.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Failed updates' -Status OK -Value ('None in the last {0} days' -f $thresholds.FailedDays)
        }
        else {
            $list = ConvertTo-ListValue -Item $stillFailing -Label 'update' -Shown 2
            New-CheckResult -Category $category -Check 'Failed updates' -Status Warning -Value $list.Value -Details $list.Details `
                -Recommendation 'These updates could not be installed. Restart the computer and check for updates again in Settings > Windows Update; make sure the system disk has free space. If an update keeps failing, search for its error code together with its KB number.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Failed updates' -ErrorRecord $_
    }
}
