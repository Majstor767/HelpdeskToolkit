function Show-WindowPage {
    <#
    .SYNOPSIS
        Shows one page of the window: the Overview, the Live monitor, the timeline, the settings or one category.
    .DESCRIPTION
        Called when an entry of the page list or the Settings button is clicked, and
        again when the search text or the status filter changes. The name of the page
        that is shown is kept in $Gui.Page.

        - Overview: the verdict, the score, the count per status, what changed since the
          last check, and every problem of the whole report, critical ones first, each
          with its recommended fix.
        - Live monitor: what the computer is doing right now. It needs no health check
          and measures only while it is shown (or while a recording runs).
        - Timeline: what happened on the computer lately (installations, updates,
          crashes), grouped by day; see Show-WindowTimeline.
        - Settings: language, theme, the automatic check, keyboard shortcuts and where
          the application keeps its files. It is opened with the button below the page
          list, so no entry of the list is selected while it is shown.
        - A category (System, Network, ...): every check of that category, side by
          side in four columns, one per status: Info, OK, Warning, Critical. Each kind
          of result stands by itself, so a problem cannot be overlooked among the rest.
          The cards of the columns are compact: the name of the check and its value. A
          click opens the explanation, the allowed range and the recommendation. The
          problems are open from the start, and what the user opens or closes is
          remembered ($Gui.CardState) until the next check the user starts.

        Order: wherever results are listed below each other (Overview, search results,
        inside a column), the most severe come first: Critical, then Warning, then OK,
        then Info. Results with the same status keep the order in which the checks ran.

        The cards of the page are always in ResultItems, as one list; on the page of a
        category the same cards are also handed to the four columns, which are shown
        in place of the list.

        Search and filter (on pages with results):
        - A search text looks through all results of the report, whatever page is
          open; the cards then also name their category.
        - The status filter narrows down what the page shows. On the Overview, which
          normally lists the problems, it shows every result with the chosen status.
          On the page of a category it hides the columns of the other statuses.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Page to show. Defaults to the entry selected in the page list.
        [string]$Name,

        # Leave the list of results where it is scrolled to. Used when the results are
        # replaced by newer ones while the user is reading them.
        [switch]$KeepScroll
    )

    $controls = $Gui.Controls
    $report = $Gui.Report
    $visible = [System.Windows.Visibility]::Visible
    $collapsed = [System.Windows.Visibility]::Collapsed

    if (-not $Name) {
        $selected = $controls.CategoryList.SelectedItem
        $Name = if ($selected) { $selected.Name } elseif ($Gui.Page -eq 'Settings') { 'Settings' } else { 'Overview' }
    }
    $Gui.Page = $Name
    $controls.TimelinePanel.Visibility = $collapsed

    # The Settings button is drawn like the selected entry of the list while its page is open.
    if ($Name -eq 'Settings') {
        $controls.SettingsButton.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'SelectedBrush')
        if ($controls.CategoryList.SelectedIndex -ne -1) {
            $wasLoading = $Gui.Loading
            $Gui.Loading = $true
            try {
                $controls.CategoryList.SelectedIndex = -1
            }
            finally {
                $Gui.Loading = $wasLoading
            }
        }
    }
    else {
        $controls.SettingsButton.ClearValue([System.Windows.Controls.Control]::BackgroundProperty)
    }

    if ($Name -eq 'Live monitor') {
        $controls.PageTitle.Text = Get-LocalizedText 'Live monitor'
        $controls.PageSubtitle.Text = Get-LocalizedText 'Measuring ...'
        $controls.OverviewPanel.Visibility = $collapsed
        $controls.ResultScroll.Visibility = $collapsed
        $controls.ColumnsPanel.Visibility = $collapsed
        $controls.EmptyText.Visibility = $collapsed
        $controls.SettingsPanel.Visibility = $collapsed
        $controls.FilterPanel.Visibility = $collapsed
        $controls.MonitorPanel.Visibility = $visible
        # The page opens with the monitor itself, not with the details of a component.
        $controls.ComponentPanel.Visibility = $collapsed
        $Gui.MonitorComponent = ''
        Enable-WindowMonitor -Gui $Gui
        return
    }

    # Every other page leaves the monitor; it only measures while it is visible.
    Disable-WindowMonitor -Gui $Gui
    $controls.MonitorPanel.Visibility = $collapsed
    $controls.ComponentPanel.Visibility = $collapsed
    $Gui.MonitorComponent = ''

    if ($Name -eq 'Settings') {
        $controls.PageTitle.Text = Get-LocalizedText 'Settings'
        $controls.PageSubtitle.Text = Get-LocalizedText 'How the application looks, and where it keeps its own files.'
        $controls.OverviewPanel.Visibility = $collapsed
        $controls.ResultScroll.Visibility = $collapsed
        $controls.ColumnsPanel.Visibility = $collapsed
        $controls.EmptyText.Visibility = $collapsed
        $controls.FilterPanel.Visibility = $collapsed
        $controls.SettingsPanel.Visibility = $visible
        Show-WindowSetting -Gui $Gui
        return
    }

    $controls.SettingsPanel.Visibility = $collapsed
    $controls.ColumnsPanel.Visibility = $collapsed
    $controls.ResultScroll.Visibility = $visible

    if ($Name -eq 'Timeline' -and $report) {
        $controls.PageTitle.Text = Get-LocalizedText 'Timeline'
        $controls.PageSubtitle.Text = Get-LocalizedText 'What happened on this computer lately, as Windows recorded it: installations, updates, crashes and failures.'
        $controls.OverviewPanel.Visibility = $collapsed
        $controls.ResultScroll.Visibility = $collapsed
        $controls.FilterPanel.Visibility = $collapsed
        $controls.TimelinePanel.Visibility = $visible
        Show-WindowTimeline -Gui $Gui -KeepScroll:$KeepScroll
        return
    }

    if (-not $report) {
        # No health check has finished yet: the Overview says that the first one is
        # running, or shows the hint to start it.
        $controls.PageTitle.Text = Get-LocalizedText 'Overview'
        $controls.OverviewPanel.Visibility = $visible
        $controls.FilterPanel.Visibility = $collapsed
        $controls.ResultItems.ItemsSource = @()
        if ($Gui.Worker) {
            $controls.PageSubtitle.Text = Get-LocalizedText 'The check is running. It usually takes 10 to 20 seconds.'
            $controls.EmptyText.Text = Get-LocalizedText 'Checking the computer ... The results appear here as soon as the check is finished.'
        }
        else {
            $controls.PageSubtitle.Text = Get-LocalizedText 'Click Run check to examine this computer.'
            $controls.EmptyText.Text = Get-LocalizedText 'No results yet. Click Run check.'
        }
        $controls.EmptyText.Visibility = $visible
        return
    }

    $controls.FilterPanel.Visibility = $visible

    # Most severe first; within one status the order of the checks is kept.
    $results = @(
        foreach ($status in 'Critical', 'Warning', 'OK', 'Info') {
            $report.Results | Where-Object { $_.Status -eq $status }
        }
        $report.Results | Where-Object { $_.Status -notin 'Critical', 'Warning', 'OK', 'Info' }
    )

    # The two filters
    $search = ([string]$controls.SearchBox.Text).Trim()
    $controls.SearchHint.Visibility = if ($controls.SearchBox.Text) { $collapsed } else { $visible }
    $statusFilter = if ($controls.StatusFilter.SelectedItem) { [string]$controls.StatusFilter.SelectedItem.Tag } else { '' }
    $hasStatus = {
        param($Result)
        switch ($statusFilter) {
            '' { $true }
            'Problems' { $Result.Status -in 'Critical', 'Warning' }
            default { $Result.Status -eq $statusFilter }
        }
    }

    if ($search) {
        # All results of the report whose visible text contains the search text
        $items = @(
            $results | Where-Object { & $hasStatus $_ } | ConvertTo-WindowItem -ShowCategory | Where-Object {
                $text = $_.Check, $_.Value, $_.Description, $_.Recommendation, $_.Category, $_.More, $_.SourceCheck -join "`n"
                $text.IndexOf($search, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
            }
        )
        $controls.PageTitle.Text = Get-LocalizedText 'Search results'
        $controls.PageSubtitle.Text = (Get-LocalizedText '{0} of {1} results contain "{2}".') -f $items.Count, $results.Count, $search
        $controls.OverviewPanel.Visibility = $collapsed
        $emptyText = Get-LocalizedText 'Nothing found.'
    }
    elseif ($Name -eq 'Overview') {
        if ($statusFilter) {
            $shown = @($results | Where-Object { & $hasStatus $_ })
            $subtitle = (Get-LocalizedText '{0} of {1} results have the chosen status.') -f $shown.Count, $results.Count
        }
        else {
            # Only the problems, like the problem list of the HTML report.
            $shown = @($results | Where-Object { $_.Status -in 'Critical', 'Warning' })
            $subtitle = if ($shown.Count -eq 0) {
                Get-LocalizedText 'Nothing needs attention. Choose a category on the left to see its details.'
            }
            else {
                (Get-LocalizedText 'These {0} results need attention. Choose a category on the left to see everything it checked.') -f $shown.Count
            }
        }
        $items = @($shown | ConvertTo-WindowItem -ShowCategory)

        $controls.PageTitle.Text = Get-LocalizedText 'Overview'
        $controls.PageSubtitle.Text = $subtitle
        $controls.OverviewPanel.Visibility = $visible
        $emptyText = if ($statusFilter) { Get-LocalizedText 'No result has the chosen status.' } else { Get-LocalizedText 'No problems found.' }
    }
    else {
        $pageResults = @($results | Where-Object { $_.Category -eq $Name })
        $items = @($pageResults | Where-Object { & $hasStatus $_ } | ConvertTo-WindowItem)

        # For example "1 Critical, 2 Warning, 5 OK"
        $counts = foreach ($status in 'Critical', 'Warning', 'OK', 'Info') {
            $count = @($pageResults | Where-Object { $_.Status -eq $status }).Count
            if ($count -gt 0) {
                '{0} {1}' -f $count, (Get-LocalizedText $status)
            }
        }

        $controls.PageTitle.Text = Get-LocalizedText $Name
        $controls.PageSubtitle.Text = @($counts) -join ', '
        $controls.OverviewPanel.Visibility = $collapsed
        $emptyText = if ($statusFilter) { Get-LocalizedText 'No result has the chosen status.' } else { Get-LocalizedText 'No results in this category.' }
    }

    # The result a notice has led to gets a frame, once.
    if ($Gui.HighlightCheck) {
        foreach ($item in $items) {
            if ($item.SourceCheck -eq $Gui.HighlightCheck) {
                $item.Highlight = 'Yes'
            }
        }
        $Gui.HighlightCheck = ''
    }

    # Which compact cards are open: the problems, unless the user decided otherwise.
    foreach ($item in $items) {
        $key = '{0}|{1}' -f $item.SourceCategory, $item.SourceCheck
        $item.Expanded = if ($Gui.CardState.ContainsKey($key)) { [bool]$Gui.CardState[$key] } else { $item.Status -in 'Critical', 'Warning' }
    }

    $offset = $controls.ResultScroll.VerticalOffset
    $controls.ResultItems.ItemsSource = $items
    $controls.EmptyText.Text = $emptyText

    if (-not $search -and $Name -ne 'Overview') {
        # The page of a category: one column per status. A status filter leaves only
        # the columns it names.
        $statuses = 'Critical', 'Warning', 'OK', 'Info'
        $shown = switch ($statusFilter) {
            '' { $statuses }
            'Problems' { 'Critical', 'Warning' }
            default { $statusFilter }
        }

        foreach ($status in $statuses) {
            $cards = @($items | Where-Object { $_.Status -eq $status })
            $scroll = $controls["Column${status}Scroll"]
            $columnOffset = $scroll.VerticalOffset

            $controls["Column${status}Items"].ItemsSource = $cards
            $controls["Column${status}Count"].Text = [string]$cards.Count
            $controls["Column${status}Empty"].Visibility = if ($cards.Count -eq 0) { $visible } else { $collapsed }
            $controls["Column$status"].Visibility = if ($status -in $shown) { $visible } else { $collapsed }

            if ($KeepScroll) {
                $scroll.ScrollToVerticalOffset($columnOffset)
            }
            else {
                $scroll.ScrollToTop()
            }
        }

        $controls.ResultScroll.Visibility = $collapsed
        $controls.EmptyText.Visibility = $collapsed
        $controls.ColumnsPanel.Visibility = $visible
        return
    }

    if ($KeepScroll) {
        $controls.ResultScroll.ScrollToVerticalOffset($offset)
    }
    else {
        $controls.ResultScroll.ScrollToTop()
    }

    $controls.EmptyText.Visibility = if ($items.Count -eq 0) { $visible } else { $collapsed }
}
