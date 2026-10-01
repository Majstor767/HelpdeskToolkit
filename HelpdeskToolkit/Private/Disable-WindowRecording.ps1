function Disable-WindowRecording {
    <#
    .SYNOPSIS
        Ends the recording of the Live monitor and says where the file is.
    .DESCRIPTION
        Called when the user stops the recording, when its time is over and when the
        window closes. The file needs no closing step: every line was written to the
        disk as it was measured. The button and the text of the page return to their
        resting state, and the path of the file is shown.

        When the monitor page is not open, the measurements are paused again, as they
        only went on for the sake of the recording.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $recorder = $Gui.Recorder
    if (-not $recorder) {
        return
    }
    $Gui.Recorder = $null

    $controls = $Gui.Controls
    $controls.MonitorRecordButton.Content = Get-LocalizedText 'Record to file'
    # "Record" symbol of the icon font
    $controls.MonitorRecordButton.Tag = [string][char]0xE7C8
    $controls.MonitorRecordMinutes.IsEnabled = $true

    $text = (Get-LocalizedText 'Recording saved: {0} ({1} measurements)') -f $recorder.Path, $recorder.Rows
    $controls.MonitorRecordText.Text = $text
    $controls.StatusText.Text = $text

    if ($controls.MonitorPanel.Visibility -ne [System.Windows.Visibility]::Visible) {
        Disable-WindowMonitor -Gui $Gui
    }
}
