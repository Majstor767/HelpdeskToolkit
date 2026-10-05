function Disable-WindowMonitor {
    <#
    .SYNOPSIS
        Pauses the measurements of the Live monitor page, releases them, or ends them for good.
    .DESCRIPTION
        Without a switch the background runspace keeps existing but stops measuring, so
        the computer is not kept busy while another page is shown, and coming back to
        the page shows data again without a delay.

        With -Release (used when the window goes into the background) the runspace is
        also given up: it holds a copy of the module and the connections to Windows
        it measures with, about a hundred megabytes that a window nobody looks at
        should not keep. The loop is told to end and the runspace is released once it
        has (see Clear-WindowWorker); the next visit of the page starts a new one
        (Enable-WindowMonitor).

        While a recording into a file runs, neither of the two happens: the
        measurements go on in the background, because the recording needs them.

        With -Stop (used when the window closes) a running recording is finished, the
        loop ends and the runspace is released.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Release,

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
        if ($Release) {
            # The loop looks at Stop several times a second and then ends by itself.
            $Gui.Monitor.Shared.Stop = $true
            if ($Gui.Monitor.Worker) {
                [void]$Gui['RetiredWorkers'].Add(@{ Worker = $Gui.Monitor.Worker; Handle = $Gui.Monitor.Handle })
            }
            $Gui.Monitor = $null
        }
    }
}
