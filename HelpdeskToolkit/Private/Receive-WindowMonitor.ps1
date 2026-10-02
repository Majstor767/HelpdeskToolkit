function Receive-WindowMonitor {
    <#
    .SYNOPSIS
        Shows the newest measurement of the background runspace on the Live monitor page.
    .DESCRIPTION
        Called by a timer on the window thread. The background runspace increases a
        counter with every measurement; the page is only redrawn when that counter has
        changed since the last call. A measurement that failed is reported in the
        subtitle of the page instead of stopping the monitor.

        While a recording runs, every new measurement is also written to its file
        (see Add-WindowRecordingRow).

        The same timer picks up the finished measurements of what takes up the space
        of the drives (see Receive-WindowDiskUsage) and what was read for the detail
        page of a component (see Receive-WindowComponentDetail).
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    Receive-WindowDiskUsage -Gui $Gui
    Receive-WindowComponentDetail -Gui $Gui

    $monitor = $Gui.Monitor
    if (-not $monitor) {
        return
    }

    $sequence = $monitor.Shared.Sequence
    if ($sequence -eq $monitor.LastSequence) {
        return
    }
    $monitor.LastSequence = $sequence

    if ($monitor.Shared.Error) {
        $Gui.Controls.PageSubtitle.Text = (Get-LocalizedText 'The live data could not be read: {0}') -f $monitor.Shared.Error
        return
    }

    $snapshot = $monitor.Shared.Snapshot
    if ($snapshot) {
        if ($Gui.Recorder) {
            Add-WindowRecordingRow -Gui $Gui -Snapshot $snapshot
        }
        Show-WindowMonitor -Gui $Gui -Snapshot $snapshot
    }
}
