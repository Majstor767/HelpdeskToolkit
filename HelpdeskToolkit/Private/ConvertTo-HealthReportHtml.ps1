function ConvertTo-HealthReportHtml {
    <#
    .SYNOPSIS
        Renders a health report object as a self-contained HTML document.
    .DESCRIPTION
        Returns the HTML as a string; saving it is done by Export-HealthReportHtml.
        The stylesheet in Assets\Report.css is embedded in a <style> element, so the
        result is a single file with no external dependencies that can be e-mailed or
        attached to a ticket.

        Layout, top to bottom: header with computer and run details, overall verdict,
        counts per status, where the points of the score went, the list of problems
        with recommendations, one card per category with every check, and at the end
        the time line of recent changes and failures.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report
    )

    # Most severe first; used for sorting and for the "worst status" of a category.
    $statusOrder = @('Critical', 'Warning', 'OK', 'Info')

    $css = Get-Content -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\Report.css') -Raw
    $results = @($Report.Results)
    $summary = $Report.Summary
    $computerName = ConvertTo-HtmlEncodedText -Text $Report.ComputerName

    # What happened on the computer lately. Reports of older versions have no time line.
    $timeline = @()
    if ($Report.PSObject.Properties['Timeline']) {
        $timeline = @($Report.Timeline | Where-Object { $_ })
    }

    # Builds one table row; shared by the problem list and the category cards.
    $newRow = {
        param($Result, [switch]$ShowCategory)

        $statusClass = $Result.Status.ToLower()
        $check = ConvertTo-HtmlEncodedText -Text $Result.Check
        if ($ShowCategory) {
            $check = '{0} <span class="category-label">({1})</span>' -f $check, (ConvertTo-HtmlEncodedText -Text $Result.Category)
        }

        # What the checked thing is. Left out of the problem list to keep it short;
        # the same row with its explanation appears in the category card below.
        $description = if ($Result.Description -and -not $ShowCategory) {
            '<div class="description">{0}</div>' -f (ConvertTo-HtmlEncodedText -Text $Result.Description)
        }
        else {
            ''
        }

        # Items that did not fit into the value. <details> is plain HTML that opens
        # and closes on click, so no script is needed.
        $details = ''
        $items = @($Result.Details)
        if ($items.Count -gt 0) {
            $listItems = ($items | ForEach-Object { '<li>{0}</li>' -f (ConvertTo-HtmlEncodedText -Text $_) }) -join ''
            $details = '<details><summary>Show {0} more</summary><ul>{1}</ul></details>' -f $items.Count, $listItems
        }
        $recommendation = if ($Result.Recommendation) {
            '<div class="recommendation">{0}</div>' -f (ConvertTo-HtmlEncodedText -Text $Result.Recommendation)
        }
        else {
            ''
        }

        # Why the problem matters; only for a result that is one. A check that could
        # not be read ("Unavailable") is no finding.
        $risk = ''
        if ($Result.Status -in 'Warning', 'Critical' -and [string]$Result.Value -ne 'Unavailable') {
            $riskText = Get-CheckRisk -Check $Result.Check -Category $Result.Category
            if ($riskText) {
                $risk = '<div class="risk">{0}</div>' -f (ConvertTo-HtmlEncodedText -Text $riskText)
            }
        }

        # Measurements carry the allowed range and a typical value to compare with.
        $referenceParts = @()
        if ($Result.Allowed) {
            $referenceParts += '<span><b>Allowed:</b> {0}</span>' -f (ConvertTo-HtmlEncodedText -Text $Result.Allowed)
        }
        if ($Result.Typical) {
            $referenceParts += '<span><b>Typical:</b> {0}</span>' -f (ConvertTo-HtmlEncodedText -Text $Result.Typical)
        }
        $reference = if ($referenceParts.Count -gt 0) {
            '<div class="reference">{0}</div>' -f ($referenceParts -join '')
        }
        else {
            ''
        }

        '<tr><td class="col-status"><span class="badge {0}">{1}</span></td><td class="col-check"><div class="check">{2}</div>{3}</td><td><div class="value">{4}</div>{5}{6}{7}{8}</td></tr>' -f `
            $statusClass, $Result.Status, $check, $description, (ConvertTo-HtmlEncodedText -Text $Result.Value), $details, $reference, $risk, $recommendation
    }

    $tableHead = '<thead><tr><th class="col-status">Status</th><th class="col-check">Check</th><th>Result</th></tr></thead>'

    $html = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $html.Add('<!DOCTYPE html>')
    $html.Add('<html lang="en">')
    $html.Add('<head>')
    $html.Add('<meta charset="utf-8">')
    $html.Add('<meta name="viewport" content="width=device-width, initial-scale=1">')
    $html.Add(('<title>PC Health Report - {0} - {1}</title>' -f $computerName, (ConvertTo-HtmlEncodedText -Text $Report.GeneratedAt)))
    $html.Add('<style>')
    $html.Add($css)
    $html.Add('</style>')
    $html.Add('</head>')
    $html.Add('<body>')

    # Header
    $html.Add('<header class="report-header"><div class="container">')
    $html.Add('<div>')
    $html.Add('<p class="eyebrow">HelpdeskToolkit</p>')
    $html.Add('<h1>PC Health Report</h1>')
    $html.Add(('<p class="computer">Computer: <strong>{0}</strong></p>' -f $computerName))
    $html.Add('</div>')
    $html.Add('<dl class="meta">')
    $html.Add(('<div><dt>Generated</dt><dd>{0}</dd></div>' -f (ConvertTo-HtmlEncodedText -Text $Report.GeneratedAt)))
    $html.Add(('<div><dt>Duration</dt><dd>{0} s</dd></div>' -f [string]$Report.DurationSeconds))
    $html.Add(('<div><dt>Event log period</dt><dd>{0} days</dd></div>' -f [string]$Report.EventLogDays))
    $html.Add(('<div><dt>Administrator rights</dt><dd>{0}</dd></div>' -f $(if ($Report.IsElevated) { 'Yes' } else { 'No' })))
    # Reports saved by older versions have no score.
    if ($Report.PSObject.Properties['Score']) {
        $html.Add(('<div><dt>Health score</dt><dd>{0} of 100</dd></div>' -f [string]$Report.Score))
    }
    $html.Add('</dl>')
    $html.Add('</div></header>')

    $html.Add('<main><div class="container">')

    # Overall verdict
    $criticalText = '{0} critical problem{1}' -f $summary.Critical, $(if ($summary.Critical -ne 1) { 's' })
    $warningText = '{0} warning{1}' -f $summary.Warning, $(if ($summary.Warning -ne 1) { 's' })
    if ($summary.Critical -gt 0) {
        $html.Add(('<p class="verdict critical"><strong>Action required.</strong> <span>{0} and {1} found.</span></p>' -f $criticalText, $warningText))
    }
    elseif ($summary.Warning -gt 0) {
        $html.Add(('<p class="verdict warning"><strong>Attention recommended.</strong> <span>{0} found, no critical problems.</span></p>' -f $warningText))
    }
    else {
        $html.Add('<p class="verdict ok"><strong>No problems found.</strong> <span>All checks passed.</span></p>')
    }

    # Counts per status
    $html.Add('<section class="summary" aria-label="Summary">')
    foreach ($status in $statusOrder) {
        $html.Add(('<div class="tile {0}"><span class="count">{1}</span><span class="label">{2}</span></div>' -f $status.ToLower(), $summary.$status, $status))
    }
    $html.Add('</section>')

    # Where the points of the score went
    $lost = @(Get-HealthScoreBreakdown -Result $results | ForEach-Object {
            $parts = @(
                if ($_.Critical -gt 0) { '{0} critical' -f $_.Critical }
                if ($_.Warning -gt 0) { '{0} warning{1}' -f $_.Warning, $(if ($_.Warning -ne 1) { 's' }) }
            )
            '<span><b>{0}</b> &minus;{1} ({2})</span>' -f (ConvertTo-HtmlEncodedText -Text $_.Category), $_.Points, ($parts -join ', ')
        })
    if ($lost.Count -gt 0 -and $Report.PSObject.Properties['Score']) {
        $html.Add(('<p class="score-breakdown">Health score {0} of 100. Points lost: {1}</p>' -f [string]$Report.Score, ($lost -join '')))
    }

    # Categories in the order the checks ran, each with its worst status. Inside a
    # category the most severe results come first; results with the same status keep
    # the order in which the checks ran.
    $categories = @($results | ForEach-Object { $_.Category } | Select-Object -Unique)
    $categoryInfo = foreach ($category in $categories) {
        $categoryResults = @($results | Where-Object { $_.Category -eq $category })
        $worst = $statusOrder | Where-Object { @($categoryResults | ForEach-Object { $_.Status }) -contains $_ } | Select-Object -First 1
        [PSCustomObject]@{
            Name    = $category
            Id      = 'cat-' + ($category.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
            Results = @(foreach ($status in $statusOrder) { $categoryResults | Where-Object { $_.Status -eq $status } })
            Worst   = $worst
        }
    }
    $categoryInfo = @($categoryInfo)

    $html.Add('<nav class="toc" aria-label="Categories">')
    foreach ($info in $categoryInfo) {
        $html.Add(('<a href="#{0}"><span class="dot {1}"></span>{2}</a>' -f $info.Id, $info.Worst.ToLower(), (ConvertTo-HtmlEncodedText -Text $info.Name)))
    }
    if ($timeline.Count -gt 0) {
        $html.Add('<a href="#timeline"><span class="dot info"></span>Timeline</a>')
    }
    $html.Add('</nav>')

    # Problems first: this is the part a technician acts on.
    $problems = @($results | Where-Object { $_.Status -eq 'Critical' }) + @($results | Where-Object { $_.Status -eq 'Warning' })
    if ($problems.Count -gt 0) {
        $html.Add('<section class="card" id="problems">')
        $html.Add(('<div class="card-header"><h2>Problems and recommendations</h2><span class="counts">{0} to review</span></div>' -f $problems.Count))
        $html.Add('<table>')
        $html.Add($tableHead)
        $html.Add('<tbody>')
        foreach ($problem in $problems) {
            $html.Add((& $newRow -Result $problem -ShowCategory))
        }
        $html.Add('</tbody></table>')
        $html.Add('</section>')
    }

    # One card per category
    foreach ($info in $categoryInfo) {
        $counts = foreach ($status in $statusOrder) {
            $count = @($info.Results | Where-Object { $_.Status -eq $status }).Count
            if ($count -gt 0) {
                '<span class="{0}">{1} {2}</span>' -f $status.ToLower(), $count, $status
            }
        }

        $html.Add(('<section class="card" id="{0}">' -f $info.Id))
        $html.Add(('<div class="card-header"><h2>{0}</h2><span class="counts">{1}</span></div>' -f (ConvertTo-HtmlEncodedText -Text $info.Name), (@($counts) -join ' &middot; ')))
        $html.Add('<table>')
        $html.Add($tableHead)
        $html.Add('<tbody>')
        foreach ($result in $info.Results) {
            $html.Add((& $newRow -Result $result))
        }
        $html.Add('</tbody></table>')
        $html.Add('</section>')
    }

    # Time line: what happened on the computer lately, newest first.
    if ($timeline.Count -gt 0) {
        $problemCount = @($timeline | Where-Object { $_.Level -eq 'Problem' }).Count
        $html.Add('<section class="card" id="timeline">')
        $html.Add(('<div class="card-header"><h2>Timeline</h2><span class="counts">{0} problems &middot; {1} changes</span></div>' -f $problemCount, ($timeline.Count - $problemCount)))
        $html.Add('<p class="timeline-hint">What happened on this computer lately, as Windows recorded it for Reliability Monitor. Look for a change (an installation, an update, a driver) shortly before the first failure.</p>')
        $html.Add('<details><summary>Show the {0} entries</summary>' -f $timeline.Count)
        $html.Add('<table class="timeline">')
        $html.Add('<thead><tr><th class="col-time">Time</th><th class="col-kind">What</th><th>Program or update</th></tr></thead>')
        $html.Add('<tbody>')
        foreach ($entry in $timeline) {
            $title = ConvertTo-HtmlEncodedText -Text $entry.Title
            if ($entry.Count -gt 1) {
                $title = '{0} <span class="times">&times; {1}</span>' -f $title, $entry.Count
            }
            $html.Add(('<tr class="{0}"><td class="col-time">{1}</td><td class="col-kind"><span class="dot {2}"></span>{3}</td><td>{4}</td></tr>' -f `
                    $entry.Level.ToLower(), (ConvertTo-HtmlEncodedText -Text $entry.Time), $(if ($entry.Level -eq 'Problem') { 'critical' } else { 'info' }),
                    (ConvertTo-HtmlEncodedText -Text $entry.Kind), $title))
        }
        $html.Add('</tbody></table>')
        $html.Add('</details>')
        $html.Add('</section>')
    }

    $html.Add('</div></main>')

    # Footer
    $footer = 'Generated by HelpdeskToolkit {0}. The tool only reads information; nothing on the computer was changed.' -f (ConvertTo-HtmlEncodedText -Text $Report.ToolVersion)
    $footer += ' The status of a measurement is decided by its allowed range. Typical values are rules of thumb for a healthy office PC and are shown for comparison only.'
    if (-not $Report.IsElevated) {
        $footer += ' Checks marked &quot;Requires admin&quot; were skipped because the tool ran without administrator rights.'
    }
    $html.Add(('<footer><div class="container">{0}</div></footer>' -f $footer))

    $html.Add('</body>')
    $html.Add('</html>')

    $html -join "`n"
}
