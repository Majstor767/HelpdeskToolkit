function Show-WindowPage {
    <#
    .SYNOPSIS
        Shows one page of the window: the Overview, the Live monitor or one category.
    .DESCRIPTION
        Called when an entry of the category list is selected.

        - Overview: the verdict, the count per status and every problem of the whole
          report, critical ones first, each with its recommended fix.
        - Live monitor: what the computer is doing right now. It needs no health check
          and measures only while it is shown.
        - A category (System, Network, ...): every check of that category in the
          order it ran.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Page to show. Defaults to the entry selected in the category list.
        [string]$Name
    )

    $controls = $Gui.Controls
    $report = $Gui.Report
    $visible = [System.Windows.Visibility]::Visible
    $collapsed = [System.Windows.Visibility]::Collapsed

    if (-not $Name) {
        $selected = $controls.CategoryList.SelectedItem
        $Name = if ($selected) { $selected.Name } else { 'Overview' }
    }

    if ($Name -eq 'Live monitor') {
        $controls.PageTitle.Text = 'Live monitor'
        $controls.PageSubtitle.Text = 'Measuring ...'
        $controls.OverviewPanel.Visibility = $collapsed
        $controls.ResultScroll.Visibility = $collapsed
        $controls.EmptyText.Visibility = $collapsed
        $controls.MonitorPanel.Visibility = $visible
        Enable-WindowMonitor -Gui $Gui
        return
    }

    # Every other page shows result cards; the monitor only measures while it is visible.
    Disable-WindowMonitor -Gui $Gui
    $controls.MonitorPanel.Visibility = $collapsed
    $controls.ResultScroll.Visibility = $visible

    if (-not $report) {
        # No health check has run yet: the Overview shows the hint to start one.
        $controls.PageTitle.Text = 'Overview'
        $controls.PageSubtitle.Text = 'Click Run check to examine this computer.'
        $controls.OverviewPanel.Visibility = $visible
        $controls.ResultItems.ItemsSource = @()
        $controls.EmptyText.Text = 'No results yet. Click Run check.'
        $controls.EmptyText.Visibility = $visible
        return
    }

    $results = @($report.Results)

    if ($Name -eq 'Overview') {
        # Most severe first, like the problem list of the HTML report.
        $problems = @($results | Where-Object { $_.Status -eq 'Critical' }) + @($results | Where-Object { $_.Status -eq 'Warning' })
        $items = @($problems | ConvertTo-WindowItem -ShowCategory)

        $controls.PageTitle.Text = 'Overview'
        $controls.PageSubtitle.Text = if ($problems.Count -eq 0) {
            'Nothing needs attention. Choose a category on the left to see its details.'
        }
        else {
            'These {0} results need attention. Choose a category on the left to see everything it checked.' -f $problems.Count
        }
        $controls.OverviewPanel.Visibility = $visible
        $emptyText = 'No problems found.'
    }
    else {
        $pageResults = @($results | Where-Object { $_.Category -eq $Name })
        $items = @($pageResults | ConvertTo-WindowItem)

        # For example "1 Critical, 2 Warning, 5 OK"
        $counts = foreach ($status in 'Critical', 'Warning', 'OK', 'Info') {
            $count = @($pageResults | Where-Object { $_.Status -eq $status }).Count
            if ($count -gt 0) {
                '{0} {1}' -f $count, $status
            }
        }

        $controls.PageTitle.Text = $Name
        $controls.PageSubtitle.Text = @($counts) -join ', '
        $controls.OverviewPanel.Visibility = $collapsed
        $emptyText = 'No results in this category.'
    }

    $controls.ResultItems.ItemsSource = $items
    $controls.ResultScroll.ScrollToTop()

    if ($items.Count -eq 0) {
        $controls.EmptyText.Text = $emptyText
        $controls.EmptyText.Visibility = $visible
    }
    else {
        $controls.EmptyText.Visibility = $collapsed
    }
}
