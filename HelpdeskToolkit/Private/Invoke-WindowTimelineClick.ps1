function Invoke-WindowTimelineClick {
    <#
    .SYNOPSIS
        Opens the web search for a problem of the Timeline page when it is clicked.
    .DESCRIPTION
        A problem on the Timeline page is shown as a link (see Show-WindowTimeline
        and Get-TimelineHelpLink). The page has one handler for all of them; it hands
        the element that was clicked to this function, which opens the address the
        row carries in the browser of the user (Open-WindowHelpLink). A row without
        an address, such as a change, does nothing.
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

    if (-not $Source -or $Source -isnot [System.Windows.Controls.Button]) {
        return
    }
    $item = $Source.DataContext
    if ($item -and $item.PSObject.Properties['Url'] -and [string]$item.Url) {
        [void](Open-WindowHelpLink -Gui $Gui -Url ([string]$item.Url))
    }
}
