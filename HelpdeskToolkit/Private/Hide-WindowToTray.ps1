function Hide-WindowToTray {
    <#
    .SYNOPSIS
        Takes the window off the screen and leaves the application running next to the clock.
    .DESCRIPTION
        What closing the window does while "Keep running when the window is closed" is
        ticked, and how the application starts with -Background. The icon in the
        notification area stays (Enable-WindowTrayIcon); the automatic check goes on
        and announces new problems with a Windows notification.

        The Live monitor stops measuring while nobody can see it and gives up its
        runspace, unless it is recording into a file. The memory the window does not
        need while it is hidden goes back to Windows (Optimize-ProcessMemory).

        The first time in a run, a notification says where the application went and
        how it is ended, because a window that disappears without ending its program
        is otherwise a surprise. -Quiet leaves that out (used when the application
        starts in the background, where nothing disappeared).
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Quiet
    )

    Enable-WindowTrayIcon -Gui $Gui
    Disable-WindowMonitor -Gui $Gui -Release
    $Gui.Hidden = $true
    $Gui.Window.Hide()
    # A window nobody looks at hands the memory it does not use back to Windows.
    Optimize-ProcessMemory -Trim

    if (-not $Quiet -and -not $Gui.TrayHintShown) {
        $Gui.TrayHintShown = $true
        $Gui.TrayIcon.ShowBalloonTip(8000, 'HelpdeskToolkit',
            (Get-LocalizedText 'HelpdeskToolkit keeps running here. Click the icon to open it; right-click it to exit.'),
            'Info')
    }
}
