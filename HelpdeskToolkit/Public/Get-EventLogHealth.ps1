function Get-EventLogHealth {
    <#
    .SYNOPSIS
        Counts critical and error events in the System and Application logs.
    .DESCRIPTION
        For each of the two logs the function reports the number of Critical events,
        the number of Error events and the five sources that logged the most of them
        in the selected period. That quickly shows whether the computer has a
        recurring problem and where to look in Event Viewer.

        It also counts unexpected shutdowns (event 6008: power loss, crashes and
        forced power-offs), blue screens (event 1001), problems reported by the disk
        drivers and the file system, and errors reported by the hardware itself (WHEA).

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
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
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

    # Blue screens: after a crash Windows writes event 1001 with the stop code at the next start.
    try {
        try {
            $filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; StartTime = $since }
            $blueScreens = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
        catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                throw
            }
            $blueScreens = @()
        }
        $blueScreenCount = $blueScreens.Count

        # The stop code says what kind of crash it was. It is the first thing the event
        # records ("0x0000009f (0x0000000000000003, ...)"); the details list every code
        # with how often it happened, and the window offers a search for each.
        $stopCodes = @(
            foreach ($entry in $blueScreens) {
                $first = if ($entry.PSObject.Properties['Properties'] -and @($entry.Properties).Count -gt 0) { [string]@($entry.Properties)[0].Value } else { '' }
                if ($first -match '0x[0-9A-Fa-f]{8}\b') {
                    '0x{0}' -f $Matches[0].Substring(2).ToUpperInvariant()
                }
            }
        )
        $details = @($stopCodes | Group-Object | Sort-Object -Property Count -Descending | ForEach-Object { 'Stop code {0} ({1}x)' -f $_.Name, $_.Count })

        $status = Get-ThresholdStatus -Value $blueScreenCount -Warning $thresholds.BlueScreenWarningAbove
        $recommendation = if ($status -ne 'OK') {
            'Windows crashed with a blue screen. The usual causes are a faulty driver, bad memory or overheating: install pending driver and Windows updates, test the memory with Windows Memory Diagnostic (mdsched.exe) and look up the stop code in Event Viewer > Windows Logs > System (source BugCheck).'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Blue screens' -Status $status `
            -Value ('{0} {1}' -f $blueScreenCount, $period) -Recommendation $recommendation -Details $details `
            -Allowed (Format-AllowedRange -Warning $thresholds.BlueScreenWarningAbove) -Typical $thresholds.TypicalBlueScreens
    }
    catch {
        New-FailureResult -Category $category -Check 'Blue screens' -ErrorRecord $_
    }

    # Two kinds of events that point at failing hardware: problems reported by the disk
    # drivers and the file system, and errors the hardware itself reported (WHEA).
    $hardwareChecks = @(
        @{
            Check          = 'Disk errors'
            Providers      = 'disk', 'Ntfs', 'volmgr'
            WarningAbove   = $thresholds.DiskErrorWarningAbove
            Recommendation = 'The disk or the file system reported problems. Back up important data, check the drive health in the Hardware category and run "chkdsk /scan" as administrator. Repeated errors usually mean the drive or its cable is failing.'
        }
        @{
            Check          = 'Hardware errors'
            Providers      = 'Microsoft-Windows-WHEA-Logger'
            WarningAbove   = $thresholds.HardwareErrorWarningAbove
            Recommendation = 'The hardware reported errors to Windows. Typical causes are faulty memory, overheating or an unstable power supply: clean the cooling, test the memory with Windows Memory Diagnostic (mdsched.exe) and update the BIOS and chipset drivers.'
        }
    )

    # Every kind of event among the given ones, the most frequent first, as
    # "<source> <number> (<how often>)": the source and the event number are the two
    # things to look up to find out what an event means and how it is fixed. They
    # become the details of the result, where the window makes each of them a link
    # (see Get-CheckHelpLink). A log that is flooded by hundreds of kinds of events is
    # cut off after the hundred most frequent.
    $listEvents = {
        param([object[]]$Entry)
        @(
            $Entry |
                Group-Object -Property ProviderName, Id |
                Sort-Object -Property Count -Descending |
                Select-Object -First 100 |
                ForEach-Object { '{0} {1} ({2})' -f $_.Group[0].ProviderName, $_.Group[0].Id, $_.Count }
        )
    }

    foreach ($hardwareCheck in $hardwareChecks) {
        try {
            try {
                # Levels 1 to 3: critical, error and warning.
                $filter = @{ LogName = 'System'; ProviderName = $hardwareCheck.Providers; Level = 1, 2, 3; StartTime = $since }
                $found = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
            }
            catch {
                if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                    throw
                }
                $found = @()
            }
            $count = $found.Count

            $status = Get-ThresholdStatus -Value $count -Warning $hardwareCheck.WarningAbove
            $recommendation = if ($status -ne 'OK') { $hardwareCheck.Recommendation } else { '' }
            $details = @(if ($found.Count -gt 0) { & $listEvents $found })
            New-CheckResult -Category $category -Check $hardwareCheck.Check -Status $status `
                -Value ('{0} {1}' -f $count, $period) -Recommendation $recommendation -Details $details `
                -Allowed (Format-AllowedRange -Warning $hardwareCheck.WarningAbove) -Typical '0'
        }
        catch {
            New-FailureResult -Category $category -Check $hardwareCheck.Check -ErrorRecord $_
        }
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
        $details = @(if ($criticalCount -gt 0) { & $listEvents @($entries | Where-Object { $_.Level -eq 1 }) })
        New-CheckResult -Category $category -Check "$logName log - critical events" -Status $status `
            -Value ('{0} {1}' -f $criticalCount, $period) -Recommendation $recommendation -Details $details `
            -Allowed (Format-AllowedRange -Warning $thresholds.CriticalEventWarningAbove -Critical $thresholds.CriticalEventCriticalAbove) `
            -Typical $thresholds.TypicalCriticalEvents

        $status = Get-ThresholdStatus -Value $errorCount -Warning $thresholds.ErrorEventWarningAbove
        $recommendation = if ($status -ne 'OK') {
            'Unusually many errors. Each kind is listed in the details with its event number, the most frequent first; start with those. The events themselves are in Event Viewer (eventvwr.msc) > Windows Logs > {0}.' -f $logName
        }
        else {
            ''
        }
        $details = @(if ($errorCount -gt 0) { & $listEvents @($entries | Where-Object { $_.Level -eq 2 }) })
        New-CheckResult -Category $category -Check "$logName log - errors" -Status $status `
            -Value ('{0} {1}' -f $errorCount, $period) -Recommendation $recommendation -Details $details `
            -Allowed (Format-AllowedRange -Warning $thresholds.ErrorEventWarningAbove) -Typical $thresholds.TypicalErrorEvents

        # The five busiest sources go into the value; any others are kept as details.
        $sources = @(
            $entries |
                Group-Object -Property ProviderName |
                Sort-Object -Property Count -Descending |
                ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count }
        )
        $otherSources = @($sources | Select-Object -Skip 5)
        $topValue = if ($sources.Count -gt 0) { ($sources | Select-Object -First 5) -join ', ' } else { 'None' }
        if ($otherSources.Count -gt 0) {
            $topValue = '{0} and {1} more' -f $topValue, $otherSources.Count
        }
        New-CheckResult -Category $category -Check "$logName log - top sources" -Status Info -Value $topValue -Details $otherSources
    }
}
