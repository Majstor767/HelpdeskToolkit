function Disable-WindowMonitor {
    <#
    .SYNOPSIS
        Pauses the measurements of the Live monitor page, or ends them for good.
    .DESCRIPTION
        Without -Stop the background runspace keeps existing but stops measuring, so
        the computer is not kept busy while another page is shown. With -Stop (used
        when the window closes) the loop ends and the runspace is released.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Stop
    )

    if ($Gui.MonitorTimer) {
        $Gui.MonitorTimer.Stop()
    }
    if (-not $Gui.Monitor) {
        return
    }

    $Gui.Monitor.Shared.Paused = $true

    if ($Stop) {
        $Gui.Monitor.Shared.Stop = $true
        # Ends a measurement that is still under way; the runspace is then released.
        [void]$Gui.Monitor.Worker.BeginStop($null, $null)
        $Gui.Monitor = $null
    }
}
