function Show-WindowMonitor {
    <#
    .SYNOPSIS
        Displays one performance snapshot on the Live monitor page of the window.
    .DESCRIPTION
        Takes the object returned by Get-PerformanceSnapshot and fills the tiles, meters,
        graphs and lists of the page. Like the result cards, the lists of the page only
        show text and a percentage; this function prepares exactly those for every row.

        The graphs show the history of a value. The window keeps the last measurements
        in $Gui.MonitorHistory; every call adds one and redraws the lines.
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

    $controls = $Gui.Controls
    $visible = [System.Windows.Visibility]::Visible
    $collapsed = [System.Windows.Visibility]::Collapsed
    $separator = '  |  '
    $degree = '{0}C' -f [char]176

    # Clock speed in GHz with one decimal, for example "3.9 GHz"
    $toGigahertz = { param($Megahertz) '{0} GHz' -f [string][math]::Round([double]$Megahertz / 1000, 1) }

    # Memory of a program: megabytes below one gigabyte, for example "512 MB" or "1.3 GB"
    $toSize = {
        param($Bytes)
        if ([double]$Bytes -ge 1GB) { Format-Gigabyte -Bytes $Bytes } else { '{0} MB' -f [string][math]::Round([double]$Bytes / 1MB) }
    }

    # A whole number with thousands separators, the same in every regional setting: "5,964"
    $toCount = { param($Number) ([long]$Number).ToString('N0', [cultureinfo]::InvariantCulture) }

    # Adds a value to the history of a graph and redraws its line and area.
    $drawGraph = {
        param([string]$Name, $Percent)

        $history = $Gui.MonitorHistory[$Name]
        $history.Add([double]$Percent)
        while ($history.Count -gt 60) {
            $history.RemoveAt(0)
        }

        # Before the page was shown for the first time the drawing area has no size yet.
        $canvas = $controls["Monitor${Name}Graph"]
        $width = if ($canvas.ActualWidth -gt 0) { $canvas.ActualWidth } else { 600 }
        $height = if ($canvas.ActualHeight -gt 0) { $canvas.ActualHeight } else { 62 }

        $graph = ConvertTo-WindowGraph -Value $history.ToArray() -Width $width -Height $height -Capacity 60
        $controls["Monitor${Name}Line"].Points = $graph.Line
        $controls["Monitor${Name}Area"].Points = $graph.Area
    }

    # The meters of the lists are bound to the Percent property of each row. WPF needs a
    # plain number there; a value that came out of a script block is wrapped by PowerShell
    # and would leave the meter empty, hence the [double] casts below.

    # --- Processor ---------------------------------------------------------------
    if ($Snapshot.Cpu) {
        $speed = & $toGigahertz $Snapshot.Cpu.FrequencyMHz
        $controls.MonitorCpuText.Text = '{0} % at {1}' -f $Snapshot.Cpu.Percent, $speed
        $controls.MonitorTileCpu.Text = '{0} %' -f $Snapshot.Cpu.Percent
        $controls.MonitorTileCpuSub.Text = $speed
        & $drawGraph 'Cpu' $Snapshot.Cpu.Percent

        $controls.MonitorProcessors.ItemsSource = @(
            $Snapshot.Cpu.Processors | ForEach-Object {
                $tip = & $toGigahertz $_.FrequencyMHz
                if ($_.Parked) {
                    $tip = '{0}, parked by Windows to save power' -f $tip
                }
                [PSCustomObject]@{ Name = $_.Name; Percent = [double]$_.Percent; Text = '{0} %' -f $_.Percent; Tip = $tip }
            }
        )

        $details = @('Base speed {0}' -f (& $toGigahertz $Snapshot.Cpu.BaseFrequencyMHz))
        $details += '{0} logical processors' -f @($Snapshot.Cpu.Processors).Count
    }
    else {
        $controls.MonitorCpuText.Text = 'Not available'
        $controls.MonitorTileCpu.Text = '-'
        $controls.MonitorTileCpuSub.Text = ''
        $controls.MonitorProcessors.ItemsSource = @()
        $details = @()
    }

    # --- System ------------------------------------------------------------------
    if ($Snapshot.System) {
        $details += '{0} processes' -f (& $toCount $Snapshot.System.Processes)
        if ($null -ne $Snapshot.System.Threads) {
            $details += '{0} threads' -f (& $toCount $Snapshot.System.Threads)
            $details += '{0} handles' -f (& $toCount $Snapshot.System.Handles)
        }
        $controls.MonitorTileUptime.Text = if ($null -ne $Snapshot.System.UptimeSeconds) { Format-Duration -Seconds $Snapshot.System.UptimeSeconds } else { '-' }
        $controls.MonitorTileUptimeSub.Text = '{0} processes' -f (& $toCount $Snapshot.System.Processes)
    }
    else {
        $controls.MonitorTileUptime.Text = '-'
        $controls.MonitorTileUptimeSub.Text = ''
    }
    $controls.MonitorCpuDetail.Text = $details -join $separator

    # --- Memory ------------------------------------------------------------------
    if ($Snapshot.Memory) {
        $memory = $Snapshot.Memory
        $controls.MonitorMemoryText.Text = '{0} % ({1} of {2} in use)' -f $memory.Percent,
            (Format-Gigabyte -Bytes $memory.UsedBytes), (Format-Gigabyte -Bytes $memory.TotalBytes)
        $controls.MonitorMemoryBar.Value = $memory.Percent
        $controls.MonitorTileMemory.Text = '{0} %' -f $memory.Percent
        $controls.MonitorTileMemorySub.Text = '{0} of {1}' -f (Format-Gigabyte -Bytes $memory.UsedBytes), (Format-Gigabyte -Bytes $memory.TotalBytes)
        & $drawGraph 'Memory' $memory.Percent

        $stats = @(
            [PSCustomObject]@{ Name = 'In use'; Text = Format-Gigabyte -Bytes $memory.UsedBytes }
            [PSCustomObject]@{ Name = 'Available'; Text = Format-Gigabyte -Bytes $memory.AvailableBytes }
            if ($null -ne $memory.CachedBytes) {
                [PSCustomObject]@{ Name = 'Cached'; Text = Format-Gigabyte -Bytes $memory.CachedBytes }
            }
            [PSCustomObject]@{
                Name = 'Committed (RAM plus page file)'
                Text = '{0} of {1}' -f (Format-Gigabyte -Bytes $memory.CommittedBytes), (Format-Gigabyte -Bytes $memory.CommitLimitBytes)
            }
            if ($null -ne $memory.PagedPoolBytes) {
                [PSCustomObject]@{ Name = 'Paged pool'; Text = & $toSize $memory.PagedPoolBytes }
                [PSCustomObject]@{ Name = 'Non-paged pool'; Text = & $toSize $memory.NonPagedPoolBytes }
            }
            if ($null -ne $memory.PageFilePercent) {
                [PSCustomObject]@{ Name = 'Page file'; Text = '{0} % used' -f $memory.PageFilePercent }
            }
        )
        $controls.MonitorMemoryStats.ItemsSource = $stats
    }
    else {
        $controls.MonitorMemoryText.Text = 'Not available'
        $controls.MonitorMemoryBar.Value = 0
        $controls.MonitorTileMemory.Text = '-'
        $controls.MonitorTileMemorySub.Text = ''
        $controls.MonitorMemoryStats.ItemsSource = @()
    }

    # --- Graphics ----------------------------------------------------------------
    $sensors = @($Snapshot.GpuSensors | Where-Object { $_ })
    $gpus = @(
        $Snapshot.Gpu | Where-Object { $_ } | ForEach-Object {
            $memoryText = if ($_.DedicatedTotalBytes -gt 0) {
                '{0} of {1} memory' -f (Format-Gigabyte -Bytes $_.DedicatedUsedBytes), (Format-Gigabyte -Bytes $_.DedicatedTotalBytes)
            }
            else {
                '{0} memory in use' -f (Format-Gigabyte -Bytes $_.DedicatedUsedBytes)
            }

            # Load per engine, then the ordinary RAM the adapter borrows
            $detail = @($_.Engines | Where-Object { $_ } | ForEach-Object { '{0} {1} %' -f $_.Name, $_.Percent })
            if ($_.SharedUsedBytes -gt 0) {
                $detail += 'shared memory {0}' -f (& $toSize $_.SharedUsedBytes)
            }

            [PSCustomObject]@{
                Name    = $_.Name
                Percent = [double]$_.Percent
                Text    = '{0} %{1}{2}' -f $_.Percent, $separator, $memoryText
                Detail  = $detail -join $separator
            }
        }
    )
    $controls.MonitorGpus.ItemsSource = $gpus
    if ($gpus.Count -eq 0) {
        $controls.MonitorGpuEmpty.Visibility = $visible
        $controls.MonitorGpuGraphFrame.Visibility = $collapsed
        $controls.MonitorTileGpu.Text = '-'
        $controls.MonitorTileGpuSub.Text = ''
    }
    else {
        $controls.MonitorGpuEmpty.Visibility = $collapsed
        $controls.MonitorGpuGraphFrame.Visibility = $visible
        & $drawGraph 'Gpu' $gpus[0].Percent

        $controls.MonitorTileGpu.Text = '{0} %' -f [int]$gpus[0].Percent
        # The temperature is the most useful second number; without a sensor the name is shown.
        $controls.MonitorTileGpuSub.Text = if ($sensors.Count -gt 0 -and $null -ne $sensors[0].TemperatureC) {
            '{0} {1}' -f $sensors[0].TemperatureC, $degree
        }
        else {
            [string]$gpus[0].Name
        }
    }

    # --- Disks -------------------------------------------------------------------
    $controls.MonitorDisks.ItemsSource = @(
        $Snapshot.Disks | Where-Object { $_ } | ForEach-Object {
            $text = 'active {0} %{1}read {2}{1}write {3}' -f $_.Percent, $separator,
                (Format-DataRate -BytesPerSecond $_.ReadBytesPerSecond), (Format-DataRate -BytesPerSecond $_.WriteBytesPerSecond)
            if ($_.QueueLength -gt 0) {
                $text = '{0}{1}queue {2}' -f $text, $separator, $_.QueueLength
            }
            [PSCustomObject]@{ Name = $_.Name; Percent = [double]$_.Percent; Text = $text }
        }
    )

    # Space on every drive letter. The meter takes the colors of the disk space check:
    # the same limits from Config\Thresholds.psd1 decide between normal, warning and critical.
    $diskLimits = (Get-HealthThreshold).Disk
    $controls.MonitorVolumes.ItemsSource = @(
        $Snapshot.Volumes | Where-Object { $_ } | ForEach-Object {
            $freePercent = 100 - $_.Percent
            $level = if ($freePercent -lt $diskLimits.CriticalFreePercent) { 'Critical' } elseif ($freePercent -lt $diskLimits.WarningFreePercent) { 'Warning' } else { 'Normal' }
            [PSCustomObject]@{
                Name    = if ($_.Label) { '{0} {1}' -f $_.Name, $_.Label } else { $_.Name }
                Percent = [double]$_.Percent
                Level   = $level
                Text    = '{0} % used{1}{2} free of {3}' -f $_.Percent, $separator, (Format-Gigabyte -Bytes $_.FreeBytes), (Format-Gigabyte -Bytes $_.TotalBytes)
            }
        }
    )

    # --- Network -----------------------------------------------------------------
    $controls.MonitorNetwork.ItemsSource = @(
        $Snapshot.Network | Where-Object { $_ } | ForEach-Object {
            $text = 'down {0}{1}up {2}' -f (Format-DataRate -BytesPerSecond $_.ReceivedBytesPerSecond -AsBits), $separator,
                (Format-DataRate -BytesPerSecond $_.SentBytesPerSecond -AsBits)
            if ($_.LinkBitsPerSecond -gt 0) {
                $text = '{0}{1}link {2}' -f $text, $separator, (Format-DataRate -BytesPerSecond ($_.LinkBitsPerSecond / 8) -AsBits)
            }
            [PSCustomObject]@{ Name = $_.Name; Text = $text }
        }
    )

    # --- Sensors -----------------------------------------------------------------
    $sensorRows = @(
        # Graphics card: temperature, fan and power draw
        foreach ($sensor in $sensors) {
            $parts = @(
                if ($null -ne $sensor.TemperatureC) { '{0} {1}' -f $sensor.TemperatureC, $degree }
                if ($null -ne $sensor.FanPercent) { 'fan {0} %' -f $sensor.FanPercent }
                if ($null -ne $sensor.PowerWatts) {
                    if ($sensor.PowerLimitWatts) { '{0} W of {1} W' -f $sensor.PowerWatts, $sensor.PowerLimitWatts } else { '{0} W' -f $sensor.PowerWatts }
                }
            )
            if ($parts.Count -gt 0) {
                [PSCustomObject]@{ Name = $sensor.Name; Text = $parts -join $separator }
            }
        }

        # Drives: temperature, wear and hours of use (administrators only)
        $health = $Snapshot.DriveHealth
        if ($health) {
            switch ($health.State) {
                'OK' {
                    foreach ($drive in @($health.Drives | Where-Object { $_ })) {
                        $parts = @(
                            if ($null -ne $drive.TemperatureC) { '{0} {1}' -f $drive.TemperatureC, $degree }
                            if ($null -ne $drive.WearPercent) { 'wear {0} %' -f $drive.WearPercent }
                            if ($null -ne $drive.PowerOnHours) { '{0} h powered on' -f (& $toCount $drive.PowerOnHours) }
                        )
                        $text = if ($parts.Count -gt 0) { $parts -join $separator } else { 'reports no sensor values' }
                        [PSCustomObject]@{ Name = $drive.Name; Text = $text }
                    }
                }
                'RequiresAdmin' {
                    [PSCustomObject]@{ Name = 'Drives'; Text = 'temperature and wear need administrator rights' }
                }
                default {
                    [PSCustomObject]@{ Name = 'Drives'; Text = 'could not be read: {0}' -f $health.Message }
                }
            }
        }

        # Thermal zones of the firmware
        foreach ($zone in @($Snapshot.Thermal | Where-Object { $_ })) {
            [PSCustomObject]@{ Name = 'Thermal zone {0}' -f $zone.Name; Text = '{0} {1}' -f $zone.TemperatureC, $degree }
        }

        # Battery
        if ($Snapshot.Battery) {
            $state = if ($Snapshot.Battery.PluggedIn) { 'plugged in' } else { 'on battery' }
            $text = '{0} %{1}{2}' -f $Snapshot.Battery.Percent, $separator, $state
            if ($null -ne $Snapshot.Battery.MinutesRemaining) {
                $text = '{0}{1}about {2} left' -f $text, $separator, (Format-Duration -Seconds ($Snapshot.Battery.MinutesRemaining * 60))
            }
            [PSCustomObject]@{ Name = 'Battery'; Text = $text }
        }
    )
    $controls.MonitorSensors.ItemsSource = $sensorRows

    # --- Programs ----------------------------------------------------------------
    $controls.MonitorProcesses.ItemsSource = @(
        $Snapshot.Processes | Where-Object { $_ } | ForEach-Object {
            [PSCustomObject]@{ Name = $_.Name; Text = '{0} %{1}{2}' -f $_.Percent, $separator, (& $toSize $_.MemoryBytes) }
        }
    )
    $controls.MonitorMemoryProcesses.ItemsSource = @(
        $Snapshot.MemoryProcesses | Where-Object { $_ } | ForEach-Object {
            [PSCustomObject]@{ Name = $_.Name; Text = & $toSize $_.MemoryBytes }
        }
    )
    $ioRows = @(
        $Snapshot.IoProcesses | Where-Object { $_ } | ForEach-Object {
            [PSCustomObject]@{ Name = $_.Name; Text = Format-DataRate -BytesPerSecond $_.IoBytesPerSecond }
        }
    )
    $controls.MonitorIoProcesses.ItemsSource = $ioRows
    $controls.MonitorIoEmpty.Visibility = if ($ioRows.Count -eq 0) { $visible } else { $collapsed }

    $controls.PageSubtitle.Text = 'What the computer is doing right now. Updated {0:HH:mm:ss}; refreshes about every 2 seconds.' -f $Snapshot.TakenAt
}
