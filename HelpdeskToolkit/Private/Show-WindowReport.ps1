function Show-WindowReport {
    <#
    .SYNOPSIS
        Displays a finished health report in the application window.
    .DESCRIPTION
        Fills in the verdict and the count per status, builds the category list on the
        left and opens the Overview page. Every entry of the list carries the worst
        status of its category (shown as a colored dot) and the number of problems in
        it, so the user sees at a glance where to look.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [PSCustomObject]$Report
    )

    $controls = $Gui.Controls
    $window = $Gui.Window
    $summary = $Report.Summary
    $results = @($Report.Results)
    $Gui.Report = $Report

    $controls.CriticalCount.Text = [string]$summary.Critical
    $controls.WarningCount.Text = [string]$summary.Warning
    $controls.OkCount.Text = [string]$summary.OK
    $controls.InfoCount.Text = [string]$summary.Info

    # Verdict: the same wording and colors as in the HTML report.
    $criticalText = '{0} critical problem{1}' -f $summary.Critical, $(if ($summary.Critical -ne 1) { 's' })
    $warningText = '{0} warning{1}' -f $summary.Warning, $(if ($summary.Warning -ne 1) { 's' })
    if ($summary.Critical -gt 0) {
        $level = 'Critical'
        $verdict = 'Action required. {0} and {1} found.' -f $criticalText, $warningText
    }
    elseif ($summary.Warning -gt 0) {
        $level = 'Warning'
        $verdict = 'Attention recommended. {0} found, no critical problems.' -f $warningText
    }
    else {
        $level = 'Ok'
        $verdict = 'No problems found. All checks passed.'
    }
    $controls.VerdictText.Text = $verdict
    $controls.VerdictText.Foreground = $window.FindResource("${level}Brush")
    $controls.VerdictBorder.Background = $window.FindResource("${level}BackBrush")
    $controls.VerdictBorder.BorderBrush = $window.FindResource("${level}Brush")
    $controls.VerdictBorder.Visibility = [System.Windows.Visibility]::Visible

    $controls.ComputerText.Text = 'Computer: {0}  |  checked {1}  |  {2} s' -f $Report.ComputerName, $Report.GeneratedAt, [string]$Report.DurationSeconds

    $status = 'Check finished: {0} results.' -f $results.Count
    if (-not $Report.IsElevated) {
        $status += ' Run without administrator rights: checks marked "Requires admin" were skipped.'
    }
    $controls.StatusText.Text = $status

    $controls.OpenReportButton.IsEnabled = $true
    $controls.SaveAsButton.IsEnabled = $true

    # Category list: Overview first, then the categories in the order they ran.
    $statusOrder = @('Critical', 'Warning', 'OK', 'Info')
    $newEntry = {
        param($EntryName, $EntryResults)

        $statuses = @($EntryResults | ForEach-Object { $_.Status })
        $worst = $statusOrder | Where-Object { $statuses -contains $_ } | Select-Object -First 1
        $problems = @($EntryResults | Where-Object { $_.Status -in 'Critical', 'Warning' }).Count

        [PSCustomObject]@{
            Name  = $EntryName
            Worst = if ($worst) { $worst } else { 'None' }
            Badge = if ($problems -gt 0) { [string]$problems } else { '' }
        }
    }

    $entries = @(& $newEntry 'Overview' $results)
    foreach ($category in @($results | ForEach-Object { $_.Category } | Select-Object -Unique)) {
        $entries += & $newEntry $category @($results | Where-Object { $_.Category -eq $category })
    }

    $controls.CategoryList.ItemsSource = $entries
    $controls.CategoryList.SelectedIndex = 0

    Show-WindowPage -Gui $Gui -Name 'Overview'
}
