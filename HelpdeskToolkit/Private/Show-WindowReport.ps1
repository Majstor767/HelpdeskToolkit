function Show-WindowReport {
    <#
    .SYNOPSIS
        Displays a finished health report in the application window.
    .DESCRIPTION
        Fills in the verdict, the score and the count per status, rebuilds the page
        list on the left and opens the Overview page. Every entry of the list carries
        the worst status of its category (shown as a colored dot) and the number of
        problems in it, so the user sees at a glance where to look.

        With -Previous, the report of the check before this one, the Overview also
        shows what changed since then (see Compare-PCHealthReport).

        With -KeepPage the user is not interrupted: the page that is open, the search
        text, the status filter and the place the list is scrolled to stay as they
        are, only the content is replaced. That is how the results of an automatic
        check arrive.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        # The report of the previous check of the same computer, if there is one.
        [PSCustomObject]$Previous,

        [switch]$KeepPage
    )

    $controls = $Gui.Controls
    $window = $Gui.Window
    $summary = $Report.Summary
    $results = @($Report.Results)
    $visible = [System.Windows.Visibility]::Visible
    $collapsed = [System.Windows.Visibility]::Collapsed
    $Gui.Report = $Report
    $Gui.PreviousReport = $Previous

    $controls.CriticalCount.Text = [string]$summary.Critical
    $controls.WarningCount.Text = [string]$summary.Warning
    $controls.OkCount.Text = [string]$summary.OK
    $controls.InfoCount.Text = [string]$summary.Info

    # Score: green from 90, orange from 60, red below. A report of an older version has none.
    if ($Report.PSObject.Properties['Score']) {
        $scoreLevel = if ($Report.Score -ge 90) { 'Ok' } elseif ($Report.Score -ge 60) { 'Warning' } else { 'Critical' }
        $controls.ScoreCount.Text = [string]$Report.Score
        $controls.ScoreCount.Foreground = $window.FindResource("${scoreLevel}Brush")
        $controls.ScoreBorder.BorderBrush = $window.FindResource("${scoreLevel}Brush")
    }
    else {
        $controls.ScoreCount.Text = '-'
    }

    # Verdict: the same wording and colors as in the HTML report.
    if ($summary.Critical -gt 0) {
        $level = 'Critical'
        $verdict = (Get-LocalizedText 'Action required. Critical problems: {0}, warnings: {1}.') -f $summary.Critical, $summary.Warning
    }
    elseif ($summary.Warning -gt 0) {
        $level = 'Warning'
        $verdict = (Get-LocalizedText 'Attention recommended. Warnings: {0}, no critical problems.') -f $summary.Warning
    }
    else {
        $level = 'Ok'
        $verdict = Get-LocalizedText 'No problems found. All checks passed.'
    }
    $controls.VerdictText.Text = $verdict
    $controls.VerdictText.Foreground = $window.FindResource("${level}Brush")
    $controls.VerdictBorder.Background = $window.FindResource("${level}BackBrush")
    $controls.VerdictBorder.BorderBrush = $window.FindResource("${level}Brush")
    $controls.VerdictBorder.Visibility = $visible

    $controls.ComputerText.Text = (Get-LocalizedText 'Computer: {0}  |  checked {1}  |  {2} s') -f $Report.ComputerName, $Report.GeneratedAt, [string]$Report.DurationSeconds

    $status = if ($KeepPage) {
        (Get-LocalizedText 'Updated automatically: {0} results, checked {1}.') -f $results.Count, $Report.GeneratedAt
    }
    else {
        (Get-LocalizedText 'Check finished: {0} results.') -f $results.Count
    }
    if (-not $Report.IsElevated) {
        $status += ' ' + (Get-LocalizedText 'Run without administrator rights: checks marked "Requires admin" were skipped.')
    }
    $controls.StatusText.Text = $status

    $controls.OpenReportButton.IsEnabled = $true
    $controls.CopySummaryButton.IsEnabled = $true
    $controls.SaveAsButton.IsEnabled = $true

    # What changed since the previous check
    if ($Previous) {
        $changes = @(Compare-PCHealthReport -Reference $Previous -Difference $Report)
        $worse = @($changes | Where-Object { $_.Change -in 'New problem', 'Worse' }).Count
        $better = $changes.Count - $worse

        $controls.ChangesTitle.Text = if ($changes.Count -eq 0) {
            (Get-LocalizedText 'No change in the problems since the last check ({0}).') -f $Previous.GeneratedAt
        }
        else {
            (Get-LocalizedText 'Since the last check ({0}): {1} new or worse, {2} resolved or better') -f $Previous.GeneratedAt, $worse, $better
        }
        $controls.ChangesItems.ItemsSource = @(
            $changes | ForEach-Object {
                [PSCustomObject]@{
                    Change     = Get-LocalizedText $_.Change
                    # Decides the color of the badge: red for what got worse, green otherwise
                    Level      = if ($_.Change -in 'New problem', 'Worse') { 'Worse' } else { 'Better' }
                    Text       = '{0} / {1}' -f (Get-LocalizedText $_.Category), (Get-LocalizedCheckName $_.Check)
                    Transition = '{0} -> {1}' -f (Get-LocalizedText $_.Before), (Get-LocalizedText $_.After)
                }
            }
        )
        $controls.ChangesBorder.Visibility = $visible
    }
    else {
        $controls.ChangesItems.ItemsSource = @()
        $controls.ChangesBorder.Visibility = $collapsed
    }

    # Page list: Overview and Live monitor first, then the categories in the order they ran.
    $entries = @(
        ConvertTo-WindowNavigationItem -Name 'Overview' -Result $results
        ConvertTo-WindowNavigationItem -Name 'Live monitor' -EmptyStatus 'Info'
    )
    foreach ($category in @($results | ForEach-Object { $_.Category } | Select-Object -Unique)) {
        $entries += ConvertTo-WindowNavigationItem -Name $category -Result @($results | Where-Object { $_.Category -eq $category })
    }

    # The page to show: the Overview, or with -KeepPage the one that is open.
    $page = if ($KeepPage -and $Gui.Page) { [string]$Gui.Page } else { 'Overview' }
    $index = -1
    for ($position = 0; $position -lt $entries.Count; $position++) {
        if ($entries[$position].Name -eq $page) {
            $index = $position
        }
    }
    if ($index -lt 0 -and $page -ne 'Settings') {
        $page = 'Overview'
        $index = 0
    }

    $Gui.Loading = $true
    try {
        if (-not $KeepPage) {
            # A report the user asked for starts without a filter.
            $controls.SearchBox.Text = ''
            $controls.StatusFilter.SelectedIndex = 0
        }
        $controls.CategoryList.ItemsSource = $entries
        $controls.CategoryList.SelectedIndex = $index
    }
    finally {
        $Gui.Loading = $false
    }

    # The Live monitor and the settings show nothing of the report.
    if ($KeepPage -and $page -in 'Live monitor', 'Settings') {
        return
    }

    Show-WindowPage -Gui $Gui -Name $page -KeepScroll:$KeepPage
}
