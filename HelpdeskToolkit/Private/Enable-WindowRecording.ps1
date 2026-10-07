function Enable-WindowRecording {
    <#
    .SYNOPSIS
        Starts writing the measurements of the Live monitor into a CSV file.
    .DESCRIPTION
        Meant for problems that come and go: start the recording, let the user work
        or reproduce the problem, and look at the file afterwards, or attach it to the
        ticket. One line is written per measurement (see Add-WindowRecordingRow), until
        the chosen time is over or the recording is stopped.

        The file is created in the report folder of the window and gets a header line
        at once. Like the CSV export of a report it is written as UTF-8 with a byte
        order mark and with the list separator of the regional settings, so that it
        opens correctly in Excel on this computer.

        While a recording runs, the monitor keeps measuring on every page of the
        window (see Disable-WindowMonitor). Returns the path of the file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # How long to record.
        [ValidateRange(1, 1440)]
        [int]$Minutes = 5
    )

    $folder = $Gui.OutputFolder
    if (-not (Test-Path -LiteralPath $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    $path = Join-Path -Path $folder -ChildPath ([string]::Format([cultureinfo]::InvariantCulture, 'Monitor_{0}_{1:yyyyMMdd-HHmmss}.csv', $env:COMPUTERNAME, (Get-Date)))
    $delimiter = [string][cultureinfo]::CurrentCulture.TextInfo.ListSeparator
    $columns = 'Time', 'CpuPercent', 'CpuSpeedMHz', 'MemoryPercent', 'MemoryUsedMB', 'GpuPercent', 'GpuTemperatureC',
        'DiskActivePercent', 'DiskReadKBps', 'DiskWriteKBps', 'NetworkDownKbps', 'NetworkUpKbps', 'BusiestProgram', 'BusiestProgramPercent',
        'PingRouterMs', 'PingInternetMs'

    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllText($path, (($columns -join $delimiter) + "`r`n"), $encoding)

    $Gui.Recorder = @{
        Path      = $path
        Delimiter = $delimiter
        Until     = (Get-Date).AddMinutes($Minutes)
        Rows      = 0
    }

    $controls = $Gui.Controls
    $controls.MonitorRecordButton.Content = Get-LocalizedText 'Stop recording'
    # "Stop" symbol of the icon font
    $controls.MonitorRecordButton.Tag = [string][char]0xE71A
    $controls.MonitorRecordMinutes.IsEnabled = $false
    $controls.MonitorRecordText.Text = (Get-LocalizedText 'Recording to {0}') -f $path
    $controls.MonitorRecordText.Visibility = [System.Windows.Visibility]::Visible

    # A recording needs measurements, also when the monitor was paused.
    if ($Gui.MonitorUserPaused) {
        Switch-WindowMonitorPause -Gui $Gui
    }

    $path
}
