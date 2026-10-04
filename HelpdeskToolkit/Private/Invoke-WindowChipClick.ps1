function Invoke-WindowChipClick {
    <#
    .SYNOPSIS
        Carries out a click on one of the status chips of a category page.
    .DESCRIPTION
        The chips at the top of a category page show how many results have each
        status. A click on one leaves only the results of that status on the page; a
        click on the chip that is chosen shows all of them again.

        The chips are another way to set the status filter next to the search field:
        the click only selects the matching entry there, and the page is drawn again
        by the handler of that list, as after a choice made in the list itself.

        Returns the status that is chosen afterwards, or an empty text for "all".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The chip that was clicked. Its Tag is the status it stands for.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Source
    )

    if ($Source -isnot [System.Windows.Controls.Primitives.ToggleButton] -or -not $Source.Tag) {
        return ''
    }

    # The click has already turned the chip on or off.
    $status = if ($Source.IsChecked -eq $true) { [string]$Source.Tag } else { '' }

    $filter = $Gui.Controls.StatusFilter
    foreach ($entry in $filter.Items) {
        if ([string]$entry.Tag -eq $status) {
            $filter.SelectedItem = $entry
        }
    }
    $status
}
