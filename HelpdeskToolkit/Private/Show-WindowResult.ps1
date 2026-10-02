function Show-WindowResult {
    <#
    .SYNOPSIS
        Opens the page of one result and scrolls to it.
    .DESCRIPTION
        Where a click on a notice leads. The page of the category is opened without
        search and filter, so the result is certainly on it; its card gets a frame in
        the accent color and is scrolled into view.

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
    Show-WindowPage -Gui $Gui -Name $page

    $items = @($controls.ResultItems.ItemsSource)
    for ($position = 0; $position -lt $items.Count; $position++) {
        if ($items[$position].SourceCheck -eq $Check) {
            # The cards exist only after the layout has run.
            $controls.ResultItems.UpdateLayout()
            $card = $controls.ResultItems.ItemContainerGenerator.ContainerFromIndex($position)
            if ($card) {
                $card.BringIntoView()
            }
            return $true
        }
    }

    $false
}
