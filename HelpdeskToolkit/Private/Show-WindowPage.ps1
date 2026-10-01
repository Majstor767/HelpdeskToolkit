function Show-WindowPage {
    <#
    .SYNOPSIS
        Shows one page of the window: the Overview or the results of one category.
    .DESCRIPTION
        Called when an entry of the category list is selected.

        - Overview: the verdict, the count per status and every problem of the whole
          report, critical ones first, each with its recommended fix.
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
    if (-not $report) {
        return
    }

    if (-not $Name) {
        $selected = $controls.CategoryList.SelectedItem
        $Name = if ($selected) { $selected.Name } else { 'Overview' }
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
        $controls.OverviewPanel.Visibility = [System.Windows.Visibility]::Visible
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
        $controls.OverviewPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $emptyText = 'No results in this category.'
    }

    $controls.ResultItems.ItemsSource = $items
    $controls.ResultScroll.ScrollToTop()

    if ($items.Count -eq 0) {
        $controls.EmptyText.Text = $emptyText
        $controls.EmptyText.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $controls.EmptyText.Visibility = [System.Windows.Visibility]::Collapsed
    }
}
