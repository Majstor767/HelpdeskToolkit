function Invoke-WindowCardClick {
    <#
    .SYNOPSIS
        Carries out a click inside a result card.
    .DESCRIPTION
        The cards are created from templates, so their clicks are caught on the list
        that contains them. The card a click came from is the "data context" of the
        element that was clicked. Two things in a card can be clicked:

        - The button next to a recommendation opens the place in Windows where the
          problem is fixed (Invoke-CheckAction). When Windows cannot open it, the
          status bar says so. For "Warranty and support" that place is the support
          page of the maker of the computer (Open-WindowSupportPage).
        - The upper part of a compact card (in the columns of a category page) opens
          and closes its details. The choice is stored in $Gui.CardState, so the card
          looks the same after the results were replaced by an automatic check.

        Clicks on anything else are ignored.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The element that was clicked.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Source
    )

    if (-not $Source) {
        return
    }

    $item = $Source.DataContext
    if (-not $item -or -not $item.PSObject.Properties['SourceCheck']) {
        return
    }

    if ($Source -is [System.Windows.Controls.Primitives.ToggleButton]) {
        $Gui.CardState['{0}|{1}' -f $item.SourceCategory, $item.SourceCheck] = $Source.IsChecked -eq $true
    }
    elseif ($Source -is [System.Windows.Controls.Button]) {
        if ($item.SourceCheck -eq 'Warranty and support') {
            [void](Open-WindowSupportPage -Gui $Gui -Value $item.SourceValue)
        }
        elseif (-not (Invoke-CheckAction -Check $item.SourceCheck -Category $item.SourceCategory -Value $item.SourceValue)) {
            $Gui.Controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
        }
    }
}
