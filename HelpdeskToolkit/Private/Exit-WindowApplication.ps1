function Exit-WindowApplication {
    <#
    .SYNOPSIS
        Ends the application, also when it is set to keep running in the background.
    .DESCRIPTION
        With "Keep running when the window is closed" ticked, closing the window only
        hides it. This function closes it for good: it marks the window as exiting, so
        the handler of the Closing event lets the close through. Used by "Exit" in the
        menu of the icon next to the clock and by the restarts of the application.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $Gui.Exiting = $true
    $Gui.Window.Close()
}
