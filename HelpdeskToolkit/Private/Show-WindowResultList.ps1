function Show-WindowResultList {
    <#
    .SYNOPSIS
        Fills the result list of the window, applying the "Show problems only" filter.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls
    if (-not $Gui.Report) {
        return
    }

    $results = @($Gui.Report.Results)
    $problemsOnly = $controls.ProblemsOnlyCheckBox.IsChecked -eq $true
    if ($problemsOnly) {
        # Most severe first, like the problem list of the HTML report.
        $results = @($results | Where-Object { $_.Status -eq 'Critical' }) + @($results | Where-Object { $_.Status -eq 'Warning' })
    }

    $controls.ResultsGrid.ItemsSource = $results

    if ($results.Count -eq 0) {
        $controls.EmptyText.Text = if ($problemsOnly) { 'No problems found.' } else { 'No results.' }
        $controls.EmptyText.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $controls.EmptyText.Visibility = [System.Windows.Visibility]::Collapsed
    }
}
