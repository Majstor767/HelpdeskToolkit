function Compare-PCHealthReport {
    <#
    .SYNOPSIS
        Compares two health reports and returns what got worse and what got better.
    .DESCRIPTION
        Answers the question "what changed since the last check?". The two reports are
        usually of the same computer at different times: before and after a repair, or
        last month and today.

        A check is compared with the check of the same name in the same category. Only
        the status counts: OK and Info both mean "no problem", Warning is worse and
        Critical is the worst. A change in the value alone (for example 31 instead of
        28 errors, both OK) is not reported.

        The kinds of change:

        - New problem:  there was no problem before, now there is a Warning or Critical
        - Worse:        a Warning became Critical
        - Better:       a Critical became a Warning
        - Resolved:     there was a problem before and now there is none

        A report can be given as an object (from Get-PCHealthReport) or as the path of
        a report that was saved as JSON. Nothing on the computer is read or changed.
    .PARAMETER Reference
        The older report: an object or the path of a JSON file.
    .PARAMETER Difference
        The newer report: an object or the path of a JSON file.
    .EXAMPLE
        Compare-PCHealthReport -Reference .\before.json -Difference .\after.json

        Shows what changed between two saved reports.
    .EXAMPLE
        $before = Get-PCHealthReport
        # ... repair something ...
        Compare-PCHealthReport -Reference $before -Difference (Get-PCHealthReport) | Format-Table Change, Category, Check, Before, After

        Checks whether a repair helped.
    .EXAMPLE
        Compare-PCHealthReport .\monday.json .\friday.json | Where-Object Change -eq 'New problem'

        Lists only the problems that appeared during the week.
    .OUTPUTS
        HelpdeskToolkit.ReportChange
        Objects with the properties Change, Category, Check, Before, After, Value and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.ReportChange')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        $Reference,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNull()]
        $Difference
    )

    # A text is the path of a saved report.
    $load = { param($Report) if ($Report -is [string]) { Import-HealthReport -Path $Report } else { $Report } }
    $before = & $load $Reference
    $after = & $load $Difference

    $rank = @{ 'Critical' = 2; 'Warning' = 1; 'OK' = 0; 'Info' = 0 }

    # Results by "category | check". Several results can share a name (two displays,
    # two memory modules); they are told apart by their position: first, second, ...
    $index = {
        param($Results)
        $table = [ordered]@{}
        $seen = @{}
        foreach ($result in @($Results)) {
            $name = '{0} | {1}' -f $result.Category, $result.Check
            $seen[$name] = [int]$seen[$name] + 1
            $table['{0} | {1}' -f $name, $seen[$name]] = $result
        }
        $table
    }
    $old = & $index $before.Results
    $new = & $index $after.Results

    $change = {
        param($Kind, $Result, $Before, $After)
        [PSCustomObject]@{
            PSTypeName     = 'HelpdeskToolkit.ReportChange'
            Change         = $Kind
            Category       = $Result.Category
            Check          = $Result.Check
            Before         = $Before
            After          = $After
            Value          = $Result.Value
            Recommendation = $Result.Recommendation
        }
    }

    $changes = @(
        # Checks of the newer report, in the order they ran
        foreach ($key in $new.Keys) {
            $result = $new[$key]
            $newRank = [int]$rank[[string]$result.Status]
            $previous = if ($old.Contains($key)) { $old[$key] } else { $null }
            $oldRank = if ($previous) { [int]$rank[[string]$previous.Status] } else { 0 }
            $oldStatus = if ($previous) { [string]$previous.Status } else { 'Not checked' }

            if ($newRank -gt $oldRank) {
                $kind = if ($oldRank -eq 0) { 'New problem' } else { 'Worse' }
                & $change $kind $result $oldStatus ([string]$result.Status)
            }
            elseif ($newRank -lt $oldRank) {
                $kind = if ($newRank -eq 0) { 'Resolved' } else { 'Better' }
                & $change $kind $result $oldStatus ([string]$result.Status)
            }
        }

        # Problems of the older report whose check no longer exists, for example a
        # network that is not connected any more
        foreach ($key in $old.Keys) {
            if (-not $new.Contains($key) -and [int]$rank[[string]$old[$key].Status] -gt 0) {
                & $change 'Resolved' $old[$key] ([string]$old[$key].Status) 'Not checked'
            }
        }
    )

    # The most important kind first
    $order = 'New problem', 'Worse', 'Better', 'Resolved'
    foreach ($kind in $order) {
        $changes | Where-Object { $_.Change -eq $kind }
    }
}
