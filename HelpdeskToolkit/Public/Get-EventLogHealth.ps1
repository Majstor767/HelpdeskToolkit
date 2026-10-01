function Get-EventLogHealth {
    <#
    .SYNOPSIS
        Counts critical and error events in the System and Application logs.
    .DESCRIPTION
        For each of the two logs the function reports the number of Critical events,
        the number of Error events and the five sources that logged the most of them
        in the selected period. That quickly shows whether the computer has a
        recurring problem and where to look in Event Viewer.

        It also counts unexpected shutdowns (event 6008): power loss, crashes and
        forced power-offs.

        Both logs are readable by standard users, so no administrator rights are
        needed. The limits come from Config\Thresholds.psd1.
    .PARAMETER Days
        How many days back to look. The default is 7.
    .EXAMPLE
        Get-EventLogHealth

        Summarizes the last 7 days.
    .EXAMPLE
        Get-EventLogHealth -Days 30

        Summarizes the last 30 days.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Status, Value, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [ValidateRange(1, 365)]
        [int]$Days = 7
    )

    $category = 'Event Log'
    $thresholds = (Get-HealthThreshold).EventLog
    $since = (Get-Date).AddDays(-$Days)
    $period = if ($Days -eq 1) { 'in the last day' } else { 'in the last {0} days' -f $Days }

    # Event 6008 is written at the next start when Windows was not shut down properly.
    try {
        $shutdowns = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008; StartTime = $since } -ErrorAction Stop)
        $shutdownCount = $shutdowns.Count
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            $shutdownCount = 0
        }
        else {
            $shutdownCount = $null
            New-FailureResult -Category $category -Check 'Unexpected shutdowns' -ErrorRecord $_
        }
    }

    if ($null -ne $shutdownCount) {
        $status = Get-ThresholdStatus -Value $shutdownCount -Warning $thresholds.UnexpectedShutdownWarningAbove
        $recommendation = if ($status -ne 'OK') {
            'The computer lost power or crashed without shutting down properly. Check the power cable or battery, overheating and recently installed drivers.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Unexpected shutdowns' -Status $status `
            -Value ('{0} {1}' -f $shutdownCount, $period) -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $thresholds.UnexpectedShutdownWarningAbove) -Typical $thresholds.TypicalUnexpectedShutdowns
    }

    foreach ($logName in 'System', 'Application') {
        try {
            # Level 1 = Critical, 2 = Error. Filtering in the hashtable is done by the
            # event log service itself, which is much faster than Where-Object.
            $filter = @{ LogName = $logName; Level = 1, 2; StartTime = $since }
            $entries = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
        catch {
            # Get-WinEvent reports "nothing found" as an error; for us that is a clean log.
            if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
                $entries = @()
            }
            else {
                New-FailureResult -Category $category -Check "$logName log" -ErrorRecord $_
                continue
            }
        }

        $criticalCount = @($entries | Where-Object { $_.Level -eq 1 }).Count
        $errorCount = @($entries | Where-Object { $_.Level -eq 2 }).Count

        $status = Get-ThresholdStatus -Value $criticalCount `
            -Warning $thresholds.CriticalEventWarningAbove -Critical $thresholds.CriticalEventCriticalAbove
        $recommendation = if ($status -ne 'OK') {
            'Critical events usually mean crashes or unexpected shutdowns. Open Event Viewer (eventvwr.msc) > Windows Logs > {0} and filter by level Critical.' -f $logName
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check "$logName log - critical events" -Status $status `
            -Value ('{0} {1}' -f $criticalCount, $period) -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $thresholds.CriticalEventWarningAbove -Critical $thresholds.CriticalEventCriticalAbove) `
            -Typical $thresholds.TypicalCriticalEvents

        $status = Get-ThresholdStatus -Value $errorCount -Warning $thresholds.ErrorEventWarningAbove
        $recommendation = if ($status -ne 'OK') {
            'Unusually many errors. Start with the top sources listed below and look them up in Event Viewer (eventvwr.msc) > Windows Logs > {0}.' -f $logName
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check "$logName log - errors" -Status $status `
            -Value ('{0} {1}' -f $errorCount, $period) -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $thresholds.ErrorEventWarningAbove) -Typical $thresholds.TypicalErrorEvents

        $topSources = @(
            $entries |
                Group-Object -Property ProviderName |
                Sort-Object -Property Count -Descending |
                Select-Object -First 5 |
                ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count }
        )
        $topValue = if ($topSources.Count -gt 0) { $topSources -join ', ' } else { 'None' }
        New-CheckResult -Category $category -Check "$logName log - top sources" -Status Info -Value $topValue
    }
}
