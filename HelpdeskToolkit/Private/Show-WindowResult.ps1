function Show-WindowResult {
    <#
    .SYNOPSIS
        Opens the page of one result and scrolls to it.
    .DESCRIPTION
        Where a click on a notice leads. The page of the category is opened without
        search and filter, so the result is certainly on it; its card is opened, gets
        a frame in the accent color and is scrolled into view in the column of its status.

        Returns $true when the result was found.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Check
    )

    if (-not $Gui.Report) {
        return $false
    }

    $controls = $Gui.Controls

    # The entry of the category in the page list; the Overview when it has none.
    $entries = @($controls.CategoryList.Items)
    $index = 0
    for ($position = 0; $position -lt $entries.Count; $position++) {
        if ($entries[$position].Name -eq $Category) {
            $index = $position
        }
    }
    $page = if ($entries.Count -gt 0) { [string]$entries[$index].Name } else { 'Overview' }

    $Gui.Loading = $true
    try {
        $controls.SearchBox.Text = ''
        $controls.StatusFilter.SelectedIndex = 0
        $controls.CategoryList.SelectedIndex = $index
    }
    finally {
        $Gui.Loading = $false
    }

    $Gui.HighlightCheck = $Check
    # The card of the result is shown with its details.
    $Gui.CardState['{0}|{1}' -f $Category, $Check] = $true
    Show-WindowPage -Gui $Gui -Name $page

    $found = @($controls.ResultItems.ItemsSource) | Where-Object { $_.SourceCheck -eq $Check } | Select-Object -First 1
    if (-not $found) {
        return $false
    }

    # The card is in the column of its status on the page of a category, and in the
    # one list of the page otherwise.
    $list = if ($controls.ColumnsPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
        $controls["Column$($found.Status)Items"]
    }
    else {
        $controls.ResultItems
    }

    $cards = @($list.ItemsSource)
    for ($position = 0; $position -lt $cards.Count; $position++) {
        if ($cards[$position].SourceCheck -eq $Check) {
            # The cards exist only after the layout has run.
            $list.UpdateLayout()
            $card = $list.ItemContainerGenerator.ContainerFromIndex($position)
            if ($card) {
                $card.BringIntoView()
            }
            break
        }
    }

    $true
}
