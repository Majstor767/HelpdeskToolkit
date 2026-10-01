function Switch-WindowMonitorPause {
    <#
    .SYNOPSIS
        Pauses the Live monitor when it runs, and resumes it when it is paused.
    .DESCRIPTION
        The action of the Pause button. Pausing keeps the last values on the screen,
        which helps to read them calmly. The button changes its caption and icon to
        say what the next click does.

        The pause chosen by the user is remembered in $Gui.MonitorUserPaused, so
        leaving the page and coming back does not resume the monitor by itself.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $button = $Gui.Controls.MonitorPauseButton
    $Gui.MonitorUserPaused = -not $Gui.MonitorUserPaused

    if ($Gui.Monitor) {
        $Gui.Monitor.Shared.Paused = $Gui.MonitorUserPaused
    }

    if ($Gui.MonitorUserPaused) {
        $button.Content = Get-LocalizedText 'Resume'
        # "Play" symbol of the icon font
        $button.Tag = [string][char]0xE768
        $Gui.Controls.PageSubtitle.Text = Get-LocalizedText 'Paused. The values below are the last ones measured.'
    }
    else {
        $button.Content = Get-LocalizedText 'Pause'
        # "Pause" symbol of the icon font
        $button.Tag = [string][char]0xE769
        $Gui.Controls.PageSubtitle.Text = Get-LocalizedText 'Measuring ...'
    }
}
