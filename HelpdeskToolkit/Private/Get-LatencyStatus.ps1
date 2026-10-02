function Get-LatencyStatus {
    <#
    .SYNOPSIS
        Judges the connection for the Network tile of the Live monitor.
    .DESCRIPTION
        Looks at the last measurements of the answer time of the internet (see
        Get-NetworkLatency), which the window keeps as a history; a measurement
        without an answer is stored as -1.

        Returns an object with:

        - Level:   "Ok" (green dot), "Near" (orange), "Over" (red) or "None" (no
                   measurement yet)
        - Value:   the newest answer time, "42 ms", or "no answer"
        - Sub:     the average and the share of lost answers
        - Summary: one sentence that says why, shown when the mouse rests on the tile

        Orange: the average answer time is above Monitor.LatencyWarningMs, or more
        answers were lost than Monitor.LatencyLossPercent. Red: twice as much, or the
        newest three measurements all went unanswered.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Answer times of the internet in milliseconds, oldest first; -1 = no answer.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [double[]]$History
    )

    $monitor = (Get-HealthThreshold).Monitor
    $recent = @($History | Select-Object -Last ([int]$monitor.LatencySamples))

    if ($recent.Count -eq 0) {
        return [PSCustomObject]@{ Level = 'None'; Value = '-'; Sub = ''; Summary = Get-LocalizedText 'No measurement yet.' }
    }

    $answered = @($recent | Where-Object { $_ -ge 0 })
    $lostPercent = [int][math]::Round(($recent.Count - $answered.Count) / $recent.Count * 100)
    $average = if ($answered.Count -gt 0) { [int][math]::Round(($answered | Measure-Object -Average).Average) } else { $null }
    $newest = $recent[-1]
    # Nothing answered at all, or the newest three measurements went unanswered.
    $silent = $answered.Count -eq 0 -or ($recent.Count -ge 3 -and @($recent | Select-Object -Last 3 | Where-Object { $_ -ge 0 }).Count -eq 0)

    $level = 'Ok'
    if ($silent -or $lostPercent -gt $monitor.LatencyLossPercent * 2 -or ($null -ne $average -and $average -gt $monitor.LatencyWarningMs * 2)) {
        $level = 'Over'
    }
    elseif ($lostPercent -gt $monitor.LatencyLossPercent -or ($null -ne $average -and $average -gt $monitor.LatencyWarningMs)) {
        $level = 'Near'
    }

    $value = if ($newest -ge 0) { '{0} ms' -f [int]$newest } else { Get-LocalizedText 'no answer' }
    $sub = if ($null -ne $average) {
        (Get-LocalizedText 'average {0} ms, {1} % lost') -f $average, $lostPercent
    }
    else {
        (Get-LocalizedText '{0} % lost') -f $lostPercent
    }

    $summary = switch ($level) {
        'Over' {
            if ($silent) {
                Get-LocalizedText 'The internet does not answer. Check the router answer time in the Network section below: when the router answers, the fault is with the provider.'
            }
            else {
                (Get-LocalizedText 'The connection is bad: {0} ms on average and {1} % of the answers lost over the last {2} measurements. Calls and remote work will break up.') -f $average, $lostPercent, $recent.Count
            }
        }
        'Near' { (Get-LocalizedText 'The connection is unsteady: {0} ms on average and {1} % of the answers lost over the last {2} measurements; up to {3} ms and {4} % is fine.') -f $average, $lostPercent, $recent.Count, $monitor.LatencyWarningMs, $monitor.LatencyLossPercent }
        default { (Get-LocalizedText 'Fine: the internet answers in {0} ms on average and {1} % of the answers were lost over the last {2} measurements.') -f $average, $lostPercent, $recent.Count }
    }

    [PSCustomObject]@{
        Level   = $level
        Value   = $value
        Sub     = $sub
        Summary = $summary
    }
}
