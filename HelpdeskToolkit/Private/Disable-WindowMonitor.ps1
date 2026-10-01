function Disable-WindowMonitor {
    <#
    .SYNOPSIS
        Pauses the measurements of the Live monitor page, or ends them for good.
    .DESCRIPTION
        Without -Stop the background runspace keeps existing but stops measuring, so
        the computer is not kept busy while another page is shown. While a recording
        into a file runs, the measurements go on in the background instead, because
        the recording needs them.

        With -Stop (used when the window closes) a running recording is finished, the
        loop ends and the runspace is released.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Stop
    )

    if ($Stop) {
        if ($Gui.Recorder) {
            Disable-WindowRecording -Gui $Gui
        }
        if ($Gui.MonitorTimer) {
            $Gui.MonitorTimer.Stop()
        }
        if ($Gui.Monitor) {
            $Gui.Monitor.Shared.Paused = $true
            $Gui.Monitor.Shared.Stop = $true
            # Ends a measurement that is still under way; the runspace is then released.
            [void]$Gui.Monitor.Worker.BeginStop($null, $null)
            $Gui.Monitor = $null
        }
        return
    }

    # A recording keeps the monitor and its timer running on every page.
    if ($Gui.Recorder) {
        return
    }

    if ($Gui.MonitorTimer) {
        $Gui.MonitorTimer.Stop()
    }
    if ($Gui.Monitor) {
        $Gui.Monitor.Shared.Paused = $true
    }
}
