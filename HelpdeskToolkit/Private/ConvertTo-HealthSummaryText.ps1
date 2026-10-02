function ConvertTo-HealthSummaryText {
    <#
    .SYNOPSIS
        Writes the result of a health check as a short plain text for a ticket or an e-mail.
    .DESCRIPTION
        A technician rarely needs the whole report in a ticket: the computer, the time,
        the verdict, and the problems with what to do about them are enough. This
        function produces that as text without any formatting, so it can be pasted
        anywhere. The "Copy summary" button of the window puts it on the clipboard.

        The text is written in the language of the window (see Get-LocalizedText).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report
    )

    $summary = $Report.Summary
    $lines = New-Object -TypeName 'System.Collections.Generic.List[string]'

    $lines.Add(('{0} - {1}' -f (Get-LocalizedText 'PC Health Check'), $Report.ComputerName))
    $checked = (Get-LocalizedText 'Checked: {0}') -f $Report.GeneratedAt
    if ($Report.PSObject.Properties['Score']) {
        $checked = '{0}  |  {1}' -f $checked, ((Get-LocalizedText 'Health score: {0} of 100') -f $Report.Score)

        # Where the points went, for example "(Security -19, Software -8)"
        $lost = @(Get-HealthScoreBreakdown -Result @($Report.Results) | ForEach-Object { '{0} -{1}' -f (Get-LocalizedText $_.Category), $_.Points })
        if ($lost.Count -gt 0) {
            $checked = '{0} ({1})' -f $checked, ($lost -join ', ')
        }
    }
    $lines.Add($checked)
    $lines.Add(((Get-LocalizedText '{0} critical, {1} warning, {2} OK, {3} info') -f $summary.Critical, $summary.Warning, $summary.OK, $summary.Info))
    $lines.Add('')

    # Most severe first, like the Overview page
    $results = @($Report.Results)
    $problems = @($results | Where-Object { $_.Status -eq 'Critical' }) + @($results | Where-Object { $_.Status -eq 'Warning' })

    if ($problems.Count -eq 0) {
        $lines.Add((Get-LocalizedText 'No problems found.'))
    }
    else {
        foreach ($item in ($problems | ConvertTo-WindowItem -ShowCategory)) {
            $lines.Add(('[{0}] {1} - {2}: {3}' -f $item.StatusText.ToUpper(), $item.Category, $item.Check, $item.Value))
            if ($item.Recommendation) {
                $lines.Add(('    {0} {1}' -f (Get-LocalizedText 'Fix:'), $item.Recommendation))
            }
        }
    }

    $lines.Add('')
    $footer = (Get-LocalizedText 'Created with HelpdeskToolkit {0}.') -f $Report.ToolVersion
    if (-not $Report.IsElevated) {
        $footer = '{0} {1}' -f $footer, (Get-LocalizedText 'Run without administrator rights: checks marked "Requires admin" were skipped.')
    }
    $lines.Add($footer)

    $lines -join "`r`n"
}
