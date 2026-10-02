function Add-WindowRecordingRow {
    <#
    .SYNOPSIS
        Writes one measurement of the Live monitor as a line into the recording file.
    .DESCRIPTION
        The line holds the values that tell most about "why is it slow right now":
        processor load and speed, memory in use, load and temperature of the graphics
        card, the busiest disk with its read and write rate, the network rates of all
        adapters together, the program that used the most processor time, and the
        answer times of the router and of the internet.

        Each line is appended to the file immediately, so nothing is lost when the
        window is closed or the computer hangs. Numbers are written with a dot as the
        decimal separator and without units, which keeps the file easy to chart.

        When the time of the recording is over, the recording is ended.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The object returned by Get-PerformanceSnapshot.
        [Parameter(Mandatory)]
        [PSCustomObject]$Snapshot
    )

    $recorder = $Gui.Recorder
    if (-not $recorder) {
        return
    }

    # A whole number, or nothing when the value is not known
    $number = { param($Value) if ($null -ne $Value) { [string][long][math]::Round([double]$Value) } else { '' } }

    $disks = @($Snapshot.Disks | Where-Object { $_ })
    $network = @($Snapshot.Network | Where-Object { $_ })
    $gpu = @($Snapshot.Gpu | Where-Object { $_ }) | Select-Object -First 1
    $sensor = @($Snapshot.GpuSensors | Where-Object { $_ }) | Select-Object -First 1
    $busiest = @($Snapshot.Processes | Where-Object { $_ }) | Select-Object -First 1
    $latency = if ($Snapshot.PSObject.Properties['Latency']) { $Snapshot.Latency } else { $null }

    $values = @(
        $Snapshot.TakenAt.ToString('yyyy-MM-dd HH:mm:ss')
        $(if ($Snapshot.Cpu) { & $number $Snapshot.Cpu.Percent } else { '' })
        $(if ($Snapshot.Cpu) { & $number $Snapshot.Cpu.FrequencyMHz } else { '' })
        $(if ($Snapshot.Memory) { & $number $Snapshot.Memory.Percent } else { '' })
        $(if ($Snapshot.Memory) { & $number ($Snapshot.Memory.UsedBytes / 1MB) } else { '' })
        $(if ($gpu) { & $number $gpu.Percent } else { '' })
        $(if ($sensor) { & $number $sensor.TemperatureC } else { '' })
        $(if ($disks.Count -gt 0) { & $number ($disks | Measure-Object -Property Percent -Maximum).Maximum } else { '' })
        $(if ($disks.Count -gt 0) { & $number (($disks | Measure-Object -Property ReadBytesPerSecond -Sum).Sum / 1KB) } else { '' })
        $(if ($disks.Count -gt 0) { & $number (($disks | Measure-Object -Property WriteBytesPerSecond -Sum).Sum / 1KB) } else { '' })
        $(if ($network.Count -gt 0) { & $number (($network | Measure-Object -Property ReceivedBytesPerSecond -Sum).Sum * 8 / 1000) } else { '' })
        $(if ($network.Count -gt 0) { & $number (($network | Measure-Object -Property SentBytesPerSecond -Sum).Sum * 8 / 1000) } else { '' })
        $(if ($busiest) { '"{0}"' -f ([string]$busiest.Name).Replace('"', '""') } else { '' })
        $(if ($busiest) { & $number $busiest.Percent } else { '' })
        # Empty when there was no answer, or when the network tests are skipped
        $(if ($latency) { & $number $latency.GatewayMs } else { '' })
        $(if ($latency) { & $number $latency.InternetMs } else { '' })
    )

    try {
        [System.IO.File]::AppendAllText($recorder.Path, (($values -join $recorder.Delimiter) + "`r`n"))
        $recorder.Rows++
    }
    catch {
        # A file that cannot be written (disk full, file opened in another program) ends the recording.
        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'The recording was stopped: {0}') -f $_.Exception.Message
        Disable-WindowRecording -Gui $Gui
        return
    }

    $remaining = ($recorder.Until - (Get-Date)).TotalSeconds
    if ($remaining -le 0) {
        Disable-WindowRecording -Gui $Gui
    }
    else {
        $Gui.Controls.MonitorRecordText.Text = (Get-LocalizedText 'Recording to {0}  |  {1} measurements  |  {2} left') -f
            $recorder.Path, $recorder.Rows, (Format-Duration -Seconds ([math]::Ceiling($remaining / 60) * 60))
    }
}
