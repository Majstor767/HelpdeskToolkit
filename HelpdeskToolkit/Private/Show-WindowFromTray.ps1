function Show-WindowFromTray {
    <#
    .SYNOPSIS
        Brings the window back on the screen and to the front.
    .DESCRIPTION
        The opposite of Hide-WindowToTray: used by the icon next to the clock, by a
        Windows notification, and when the application is started a second time while
        it runs in the background.

        A window that was only hidden is shown again where it was; a minimized one is
        restored. When the Live monitor is the open page, it starts measuring again.

        Without -Force nothing happens to a window that is not hidden, so the function
        can be called without a look at the state first.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Show and activate the window whether it was hidden or not.
        [switch]$Force
    )

    if (-not $Gui.Hidden -and -not $Force) {
        return
    }

    $window = $Gui.Window
    $wasHidden = $Gui.Hidden
    $Gui.Hidden = $false
    $window.Show()
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    }

    # Windows does not let a program push its window in front of the one the user is
    # working in; a window that is "topmost" for a moment gets there all the same.
    [void]$window.Activate()
    $window.Topmost = $true
    $window.Topmost = $false

    if ($wasHidden -and $Gui.Page -eq 'Live monitor') {
        Enable-WindowMonitor -Gui $Gui
    }
}
