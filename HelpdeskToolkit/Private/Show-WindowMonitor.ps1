function Show-WindowMonitor {
    <#
    .SYNOPSIS
        Displays one performance snapshot on the Live monitor page of the window.
    .DESCRIPTION
        Takes the object returned by Get-PerformanceSnapshot and fills the tiles, meters,
        graphs and lists of the page. Like the result cards, the lists of the page only
        show text and a percentage; this function prepares exactly those for every row.

        The graphs show the history of a value. The window keeps the last 60
        measurements in $Gui.MonitorHistory; every call adds one and redraws the
        lines. Processor, memory, graphics and disk are percentages. The network has
        no fixed upper end, so its two lines (download and upload) are drawn against
        the highest rate in the history, which the caption of the graph names.

        The same histories decide about the warnings at the top of the page (see
        Get-MonitorAlert) and about the status dots of the tiles (see Get-MonitorStatus).
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
    $capacity = 60

    # Clock speed in GHz with one decimal, for example "3.9 GHz"
    $toGigahertz = { param($Megahertz) '{0} GHz' -f [string][math]::Round([double]$Megahertz / 1000, 1) }

    # Memory of a program: megabytes below one gigabyte, for example "512 MB" or "1.3 GB"
    $toSize = {
        param($Bytes)
        if ([double]$Bytes -ge 1GB) { Format-Gigabyte -Bytes $Bytes } else { '{0} MB' -f [string][math]::Round([double]$Bytes / 1MB) }
    }

    # A whole number with thousands separators, the same in every regional setting: "5,964"
    $toCount = { param($Number) ([long]$Number).ToString('N0', [cultureinfo]::InvariantCulture) }

    # Adds a value to a history, keeps only the newest ones and returns them all.
    # (The values are returned as an array: a list that leaves a script block is
    # taken apart by PowerShell, and one with a single value would arrive as a number.)
    $remember = {
        param([string]$Name, $Value)
        $history = $Gui.MonitorHistory[$Name]
        $history.Add([double]$Value)
        while ($history.Count -gt $capacity) {
            $history.RemoveAt(0)
        }
        , $history.ToArray()
    }

    # The points of a line for the drawing area of a graph. Before the page was shown
    # for the first time the area has no size yet.
    $toGraph = {
        param($Canvas, [double[]]$Values)
        $width = if ($Canvas.ActualWidth -gt 0) { $Canvas.ActualWidth } else { 600 }
        $height = if ($Canvas.ActualHeight -gt 0) { $Canvas.ActualHeight } else { 62 }
        ConvertTo-WindowGraph -Value $Values -Width $width -Height $height -Capacity $capacity
    }

    # Adds a percentage to the history of a graph and redraws its line and area.
    $drawGraph = {
        param([string]$Name, $Percent)
        $history = & $remember $Name $Percent
        $graph = & $toGraph $controls["Monitor${Name}Graph"] $history
        $controls["Monitor${Name}Line"].Points = $graph.Line
        $controls["Monitor${Name}Area"].Points = $graph.Area
    }

    # The meters of the lists are bound to the Percent property of each row. WPF needs a
    # plain number there; a value that came out of a script block is wrapped by PowerShell
    # and would leave the meter empty, hence the [double] casts below.

    # --- Processor ---------------------------------------------------------------
    if ($Snapshot.Cpu) {
        $speed = & $toGigahertz $Snapshot.Cpu.FrequencyMHz
        $controls.MonitorCpuText.Text = (Get-LocalizedText '{0} % at {1}') -f $Snapshot.Cpu.Percent, $speed
        $controls.MonitorTileCpu.Text = '{0} %' -f $Snapshot.Cpu.Percent
        $controls.MonitorTileCpuSub.Text = $speed
        & $drawGraph 'Cpu' $Snapshot.Cpu.Percent

        $parked = Get-LocalizedText '{0}, parked by Windows to save power'
        $controls.MonitorProcessors.ItemsSource = @(
            $Snapshot.Cpu.Processors | ForEach-Object {
                $tip = & $toGigahertz $_.FrequencyMHz
                if ($_.Parked) {
                    $tip = $parked -f $tip
                }
                [PSCustomObject]@{ Name = $_.Name; Percent = [double]$_.Percent; Text = '{0} %' -f $_.Percent; Tip = $tip }
            }
        )

        $details = @((Get-LocalizedText 'Base speed {0}') -f (& $toGigahertz $Snapshot.Cpu.BaseFrequencyMHz))
        $details += (Get-LocalizedText '{0} logical processors') -f @($Snapshot.Cpu.Processors).Count
    }
    else {
        $controls.MonitorCpuText.Text = Get-LocalizedText 'Not available'
        $controls.MonitorTileCpu.Text = '-'
        $controls.MonitorTileCpuSub.Text = ''
        $controls.MonitorProcessors.ItemsSource = @()
        $details = @()
    }

    # --- System ------------------------------------------------------------------
    if ($Snapshot.System) {
        $processText = (Get-LocalizedText '{0} processes') -f (& $toCount $Snapshot.System.Processes)
        $details += $processText
        if ($null -ne $Snapshot.System.Threads) {
            $details += (Get-LocalizedText '{0} threads') -f (& $toCount $Snapshot.System.Threads)
            $details += (Get-LocalizedText '{0} handles') -f (& $toCount $Snapshot.System.Handles)
        }
        $controls.MonitorTileUptime.Text = if ($null -ne $Snapshot.System.UptimeSeconds) { Format-Duration -Seconds $Snapshot.System.UptimeSeconds } else { '-' }
        $controls.MonitorTileUptimeSub.Text = $processText
    }
    else {
        $controls.MonitorTileUptime.Text = '-'
        $controls.MonitorTileUptimeSub.Text = ''
    }
    $controls.MonitorCpuDetail.Text = $details -join $separator

    # --- Memory ------------------------------------------------------------------
    if ($Snapshot.Memory) {
        $memory = $Snapshot.Memory
        $used = Format-Gigabyte -Bytes $memory.UsedBytes
        $total = Format-Gigabyte -Bytes $memory.TotalBytes
        $controls.MonitorMemoryText.Text = (Get-LocalizedText '{0} % ({1} of {2} in use)') -f $memory.Percent, $used, $total
        $controls.MonitorMemoryBar.Value = $memory.Percent
        $controls.MonitorTileMemory.Text = '{0} %' -f $memory.Percent
        $controls.MonitorTileMemorySub.Text = (Get-LocalizedText '{0} of {1}') -f $used, $total
        & $drawGraph 'Memory' $memory.Percent

        $stat = { param($Label, $Text) [PSCustomObject]@{ Name = Get-LocalizedText $Label; Text = $Text } }
        $controls.MonitorMemoryStats.ItemsSource = @(
            & $stat 'In use' $used
            & $stat 'Available' (Format-Gigabyte -Bytes $memory.AvailableBytes)
            if ($null -ne $memory.CachedBytes) {
                & $stat 'Cached' (Format-Gigabyte -Bytes $memory.CachedBytes)
            }
            & $stat 'Committed (RAM plus page file)' ((Get-LocalizedText '{0} of {1}') -f (Format-Gigabyte -Bytes $memory.CommittedBytes), (Format-Gigabyte -Bytes $memory.CommitLimitBytes))
            if ($null -ne $memory.PagedPoolBytes) {
                & $stat 'Paged pool' (& $toSize $memory.PagedPoolBytes)
                & $stat 'Non-paged pool' (& $toSize $memory.NonPagedPoolBytes)
            }
            if ($null -ne $memory.PageFilePercent) {
                & $stat 'Page file' ((Get-LocalizedText '{0} % used') -f $memory.PageFilePercent)
            }
        )
    }
    else {
        $controls.MonitorMemoryText.Text = Get-LocalizedText 'Not available'
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
                (Get-LocalizedText '{0} of {1} memory') -f (Format-Gigabyte -Bytes $_.DedicatedUsedBytes), (Format-Gigabyte -Bytes $_.DedicatedTotalBytes)
            }
            else {
                (Get-LocalizedText '{0} memory in use') -f (Format-Gigabyte -Bytes $_.DedicatedUsedBytes)
            }

            # Load per engine, then the ordinary RAM the adapter borrows
            $detail = @($_.Engines | Where-Object { $_ } | ForEach-Object { '{0} {1} %' -f (Get-LocalizedText $_.Name), $_.Percent })
            if ($_.SharedUsedBytes -gt 0) {
                $detail += (Get-LocalizedText 'shared memory {0}') -f (& $toSize $_.SharedUsedBytes)
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
    $disks = @($Snapshot.Disks | Where-Object { $_ })
    $controls.MonitorDisks.ItemsSource = @(
        $disks | ForEach-Object {
            $text = (Get-LocalizedText 'active {0} %') -f $_.Percent
            $text += $separator + ((Get-LocalizedText 'read {0}') -f (Format-DataRate -BytesPerSecond $_.ReadBytesPerSecond))
            $text += $separator + ((Get-LocalizedText 'write {0}') -f (Format-DataRate -BytesPerSecond $_.WriteBytesPerSecond))
            if ($_.QueueLength -gt 0) {
                $text += $separator + ((Get-LocalizedText 'queue {0}') -f $_.QueueLength)
            }
            [PSCustomObject]@{ Name = $_.Name; Percent = [double]$_.Percent; Text = $text }
        }
    )
    # The graph follows the busiest disk: that is the one that slows the computer down.
    $busiestDisk = if ($disks.Count -gt 0) { ($disks | Measure-Object -Property Percent -Maximum).Maximum } else { 0 }
    & $drawGraph 'Disk' $busiestDisk

    # Space on every drive letter, and what takes it up
    Show-WindowVolume -Gui $Gui -Volume @($Snapshot.Volumes | Where-Object { $_ })

    # --- Network -----------------------------------------------------------------
    $network = @($Snapshot.Network | Where-Object { $_ })
    $controls.MonitorNetwork.ItemsSource = @(
        $network | ForEach-Object {
            $text = (Get-LocalizedText 'down {0}') -f (Format-DataRate -BytesPerSecond $_.ReceivedBytesPerSecond -AsBits)
            $text += $separator + ((Get-LocalizedText 'up {0}') -f (Format-DataRate -BytesPerSecond $_.SentBytesPerSecond -AsBits))
            if ($_.LinkBitsPerSecond -gt 0) {
                $text += $separator + ((Get-LocalizedText 'link {0}') -f (Format-DataRate -BytesPerSecond ($_.LinkBitsPerSecond / 8) -AsBits))
            }
            [PSCustomObject]@{ Name = $_.Name; Text = $text }
        }
    )

    # Graph: both directions of all adapters together, in bytes per second. The scale is
    # the highest rate of the history, but never below 100 KB/s, so that an idle line
    # does not look like a busy one.
    $down = if ($network.Count -gt 0) { ($network | Measure-Object -Property ReceivedBytesPerSecond -Sum).Sum } else { 0 }
    $up = if ($network.Count -gt 0) { ($network | Measure-Object -Property SentBytesPerSecond -Sum).Sum } else { 0 }
    $downHistory = & $remember 'NetworkDown' $down
    $upHistory = & $remember 'NetworkUp' $up
    $scale = [math]::Max(100KB, (@($downHistory) + @($upHistory) | Measure-Object -Maximum).Maximum)
    $toPercent = { param($Values) , [double[]]@($Values | ForEach-Object { $_ / $scale * 100 }) }
    $controls.MonitorNetworkDownLine.Points = (& $toGraph $controls.MonitorNetworkGraph (& $toPercent $downHistory)).Line
    $controls.MonitorNetworkUpLine.Points = (& $toGraph $controls.MonitorNetworkGraph (& $toPercent $upHistory)).Line
    $controls.MonitorNetworkCaption.Text = (Get-LocalizedText 'download (blue) and upload (green), last 60 measurements, 0 - {0}') -f (Format-DataRate -BytesPerSecond $scale -AsBits)

    # --- Sensors -----------------------------------------------------------------
    $controls.MonitorSensors.ItemsSource = @(
        # Graphics card: temperature, fan and power draw
        foreach ($sensor in $sensors) {
            $parts = @(
                if ($null -ne $sensor.TemperatureC) { '{0} {1}' -f $sensor.TemperatureC, $degree }
                if ($null -ne $sensor.FanPercent) { (Get-LocalizedText 'fan {0} %') -f $sensor.FanPercent }
                if ($null -ne $sensor.PowerWatts) {
                    if ($sensor.PowerLimitWatts) { (Get-LocalizedText '{0} W of {1} W') -f $sensor.PowerWatts, $sensor.PowerLimitWatts } else { '{0} W' -f $sensor.PowerWatts }
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
                            if ($null -ne $drive.WearPercent) { (Get-LocalizedText 'wear {0} %') -f $drive.WearPercent }
                            if ($null -ne $drive.PowerOnHours) { (Get-LocalizedText '{0} h powered on') -f (& $toCount $drive.PowerOnHours) }
                        )
                        $text = if ($parts.Count -gt 0) { $parts -join $separator } else { Get-LocalizedText 'reports no sensor values' }
                        [PSCustomObject]@{ Name = $drive.Name; Text = $text }
                    }
                }
                'RequiresAdmin' {
                    [PSCustomObject]@{ Name = Get-LocalizedText 'Drives'; Text = Get-LocalizedText 'temperature and wear need administrator rights' }
                }
                default {
                    [PSCustomObject]@{ Name = Get-LocalizedText 'Drives'; Text = (Get-LocalizedText 'could not be read: {0}') -f $health.Message }
                }
            }
        }

        # Thermal zones of the firmware
        foreach ($zone in @($Snapshot.Thermal | Where-Object { $_ })) {
            [PSCustomObject]@{ Name = (Get-LocalizedText 'Thermal zone {0}') -f $zone.Name; Text = '{0} {1}' -f $zone.TemperatureC, $degree }
        }

        # Battery
        if ($Snapshot.Battery) {
            $state = if ($Snapshot.Battery.PluggedIn) { Get-LocalizedText 'plugged in' } else { Get-LocalizedText 'on battery' }
            $text = '{0} %{1}{2}' -f $Snapshot.Battery.Percent, $separator, $state
            if ($null -ne $Snapshot.Battery.MinutesRemaining) {
                $text += $separator + ((Get-LocalizedText 'about {0} left') -f (Format-Duration -Seconds ($Snapshot.Battery.MinutesRemaining * 60)))
            }
            [PSCustomObject]@{ Name = Get-LocalizedText 'Battery'; Text = $text }
        }
    )

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

    # --- Warnings ----------------------------------------------------------------
    $controls.MonitorAlerts.ItemsSource = @(
        Get-MonitorAlert -History $Gui.MonitorHistory -Snapshot $Snapshot | ForEach-Object { [PSCustomObject]@{ Text = $_ } }
    )

    # --- Status dots of the tiles ------------------------------------------------
    Show-WindowAdvice -Gui $Gui -Status @(Get-MonitorStatus -History $Gui.MonitorHistory -Snapshot $Snapshot)

    $interval = if ($Gui.Monitor) { [int]$Gui.Monitor.Shared.IntervalSeconds } else { [int]$Gui.Settings.MonitorIntervalSeconds }
    $controls.PageSubtitle.Text = (Get-LocalizedText 'What the computer is doing right now. Updated {0:HH:mm:ss}; refreshes about every {1} seconds.') -f $Snapshot.TakenAt, $interval
}
