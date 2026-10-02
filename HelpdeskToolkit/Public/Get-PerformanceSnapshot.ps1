function Get-PerformanceSnapshot {
    <#
    .SYNOPSIS
        Returns what the computer is doing right now: load per processor, memory, graphics, disks, network, sensors and the busiest programs.
    .DESCRIPTION
        Takes one measurement of the live performance data that Windows keeps:

        - Cpu:             total load, current and base clock speed, and load, speed and
                           parking state of every logical processor (a core with
                           hyper-threading counts as two)
        - System:          number of processes, threads and handles, and the time since
                           Windows started
        - Memory:          physical memory in use, available and cached; committed memory
                           against its limit; kernel pools; page file usage
        - Gpu:             load (in total and per engine: 3D, copy, video decode, video
                           encode) and dedicated and shared memory of each graphics adapter
        - GpuSensors:      temperature, fan speed and power draw of NVIDIA graphics
                           cards, read with the nvidia-smi tool of the installed driver
        - Disks:           how busy each physical disk is, its read and write rate and
                           its queue length
        - Volumes:         used and free space of every drive letter
        - DriveHealth:     temperature, wear and power-on hours of every drive
                           (administrator rights needed; otherwise State is "RequiresAdmin")
        - Network:         receive and send rate and link speed of each network adapter
        - Latency:         with -IncludeLatency: how quickly the router and the internet
                           answer a ping right now (nothing without the switch)
        - Thermal:         temperature of the thermal zones the firmware reports (mostly
                           on laptops)
        - Battery:         charge and remaining time, on computers that have a battery
        - Processes:       the programs using the most processor time, grouped by name
        - MemoryProcesses: the programs using the most memory, grouped by name
        - IoProcesses:     the programs reading and writing the most data (files, network
                           and devices together), grouped by name

        The window (Show-PCHealthCheck) calls this command again and again for its
        "Live monitor" page. In a script it can be used for logging or for a quick look.

        The data comes from the performance classes of WMI, whose names are the same in
        every Windows language. Nothing is changed, and apart from DriveHealth no
        administrator rights are needed. One measurement takes about half a second,
        because the classes are read at the same time.

        Processor temperature, fan speeds and voltages of the motherboard are not
        included: Windows does not expose them, and tools that show them install their
        own hardware driver.

        A part that cannot be read is returned empty; the other parts are still filled in.
    .PARAMETER TopProcessCount
        How many programs to return in Processes, MemoryProcesses and IoProcesses. The default is 5.
    .PARAMETER IncludeLatency
        Also ping the router and the address of the internet connectivity test (see
        Config\Thresholds.psd1) and return the answer times in Latency. This is the
        only part of a snapshot that sends anything over the network.
    .EXAMPLE
        Get-PerformanceSnapshot

        Returns one snapshot object.
    .EXAMPLE
        (Get-PerformanceSnapshot).Cpu.Processors | Format-Table Name, Percent, FrequencyMHz, Parked

        Shows the load and the clock speed of every logical processor.
    .EXAMPLE
        (Get-PerformanceSnapshot).MemoryProcesses | Format-Table Name, @{ n = 'GB'; e = { [math]::Round($_.MemoryBytes / 1GB, 1) } }

        Shows the programs that use the most memory.
    .EXAMPLE
        while ($true) { (Get-PerformanceSnapshot).Processes | Format-Table; Start-Sleep -Seconds 5 }

        Prints the busiest programs every few seconds until Ctrl+C is pressed.
    .OUTPUTS
        HelpdeskToolkit.PerformanceSnapshot
        An object with the properties TakenAt, Cpu, System, Memory, Gpu, GpuSensors, Disks, Volumes, DriveHealth, Network, Latency, Thermal, Battery, Processes, MemoryProcesses and IoProcesses.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.PerformanceSnapshot')]
    param(
        [ValidateRange(1, 20)]
        [int]$TopProcessCount = 5,

        [switch]$IncludeLatency
    )

    # The classes that Windows needs a moment for are asked all at once, so one
    # measurement takes half a second instead of two and all values are from the same
    # moment. A class that could not be read throws its error where it is used.
    $batch = Get-CimInstanceBatch -ClassName @(
        'Win32_PerfFormattedData_Counters_ProcessorInformation'
        'Win32_OperatingSystem'
        'Win32_PerfRawData_PerfOS_Memory'
        'Win32_PerfFormattedData_PerfOS_PagingFile'
        'Win32_PerfFormattedData_PerfDisk_PhysicalDisk'
        'Win32_PerfFormattedData_Tcpip_NetworkInterface'
        'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine'
        'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory'
        'Win32_PerfFormattedData_Counters_ThermalZoneInformation'
        'Win32_PerfFormattedData_PerfProc_Process'
    )
    $cim = {
        param([string]$Class)
        if ($batch[$Class].Error) {
            throw $batch[$Class].Error
        }
        $batch[$Class].Rows
    }

    # A counter can momentarily read above 100 or below 0; the display should not.
    $limit = { param($Number) [int][math]::Max(0, [math]::Min(100, [math]::Round([double]$Number))) }

    # --- Processor ---------------------------------------------------------------
    $cpu = $null
    $logicalCount = [Environment]::ProcessorCount
    try {
        $rows = @(& $cim 'Win32_PerfFormattedData_Counters_ProcessorInformation')

        # Logical processors are named "group,number" (for example "0,3"); the rows
        # "_Total" and "0,_Total" are sums.
        $logical = @($rows | Where-Object { $_.Name -match '^\d+,\d+$' } |
                Sort-Object -Property @{ Expression = { [int]($_.Name -split ',')[0] } }, @{ Expression = { [int]($_.Name -split ',')[1] } })
        $total = $rows | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1

        if ($logical.Count -gt 0) {
            $logicalCount = $logical.Count
        }

        # ProcessorFrequency is the base speed. "Processor performance" says how fast the
        # processor really runs compared with it: 150 means 1.5 times the base speed (turbo).
        $toSpeed = {
            param($Row)
            $speed = [double]$Row.ProcessorFrequency
            if ($Row.PercentProcessorPerformance -gt 0) {
                $speed = $speed * [double]$Row.PercentProcessorPerformance / 100
            }
            [int][math]::Round($speed)
        }

        $index = 0
        $processors = @(
            foreach ($row in $logical) {
                [PSCustomObject]@{
                    Name         = 'CPU {0}' -f $index
                    Percent      = & $limit $row.PercentProcessorUtility
                    FrequencyMHz = & $toSpeed $row
                    # Windows parks a processor it does not need, to save power.
                    Parked       = [bool]$row.ParkingStatus
                }
                $index++
            }
        )

        if ($total) {
            $cpu = [PSCustomObject]@{
                Percent          = & $limit $total.PercentProcessorUtility
                FrequencyMHz     = & $toSpeed $total
                BaseFrequencyMHz = [int]$total.ProcessorFrequency
                Processors       = $processors
            }
        }
    }
    catch {
        Write-Verbose "Processor data is not available: $($_.Exception.Message)"
    }

    # --- Memory (Win32_OperatingSystem reports kilobytes) -------------------------
    $memory = $null
    $os = $null
    try {
        $os = & $cim 'Win32_OperatingSystem'
        $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        $availableBytes = [double]$os.FreePhysicalMemory * 1KB
        $usedBytes = $totalBytes - $availableBytes
        $commitLimit = [double]$os.TotalVirtualMemorySize * 1KB

        $memory = [PSCustomObject]@{
            TotalBytes        = $totalBytes
            UsedBytes         = $usedBytes
            AvailableBytes    = $availableBytes
            Percent           = & $limit ($usedBytes / $totalBytes * 100)
            CommittedBytes    = $commitLimit - ([double]$os.FreeVirtualMemory * 1KB)
            CommitLimitBytes  = $commitLimit
            CachedBytes       = $null
            PagedPoolBytes    = $null
            NonPagedPoolBytes = $null
            PageFilePercent   = $null
        }
    }
    catch {
        Write-Verbose "Memory data is not available: $($_.Exception.Message)"
    }

    # The breakdown of the memory. These are plain amounts, so the "raw" class is used:
    # it answers at once, while a "formatted" class first measures for a moment.
    if ($memory) {
        try {
            $detail = & $cim 'Win32_PerfRawData_PerfOS_Memory' | Select-Object -First 1
            # "Cached" as in Task Manager: memory that holds data of files and closed
            # programs and is given back the moment a program needs it.
            $memory.CachedBytes = [double]$detail.StandbyCacheNormalPriorityBytes + [double]$detail.StandbyCacheReserveBytes +
                [double]$detail.StandbyCacheCoreBytes + [double]$detail.ModifiedPageListBytes
            $memory.PagedPoolBytes = [double]$detail.PoolPagedBytes
            $memory.NonPagedPoolBytes = [double]$detail.PoolNonpagedBytes

            $pageFile = & $cim 'Win32_PerfFormattedData_PerfOS_PagingFile' |
                Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
            if ($pageFile) {
                $memory.PageFilePercent = & $limit $pageFile.PercentUsage
            }
        }
        catch {
            Write-Verbose "Memory details are not available: $($_.Exception.Message)"
        }
    }

    # --- Disks -------------------------------------------------------------------
    $disks = @()
    try {
        $disks = @(
            & $cim 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' |
                Where-Object { $_.Name -ne '_Total' } |
                Sort-Object -Property Name |
                ForEach-Object {
                    # The name is the disk number followed by its drive letters: "0 C: D:"
                    $number, $letters = $_.Name -split ' ', 2
                    [PSCustomObject]@{
                        Name                = if ($letters) { 'Disk {0} ({1})' -f $number, $letters } else { 'Disk {0}' -f $number }
                        Percent             = & $limit (100 - [double]$_.PercentIdleTime)
                        ReadBytesPerSecond  = [double]$_.DiskReadBytesPersec
                        WriteBytesPerSecond = [double]$_.DiskWriteBytesPersec
                        # Requests waiting for the disk; a queue that stays long means the disk is the bottleneck.
                        QueueLength         = [int]$_.CurrentDiskQueueLength
                    }
                }
        )
    }
    catch {
        Write-Verbose "Disk data is not available: $($_.Exception.Message)"
    }

    # --- Volumes (drive letters on fixed disks) -----------------------------------
    $volumes = @()
    try {
        $volumes = @(
            Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop |
                Where-Object { $_.Size -gt 0 } |
                Sort-Object -Property DeviceID |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name       = [string]$_.DeviceID
                        Label      = [string]$_.VolumeName
                        TotalBytes = [double]$_.Size
                        FreeBytes  = [double]$_.FreeSpace
                        Percent    = & $limit (([double]$_.Size - [double]$_.FreeSpace) / [double]$_.Size * 100)
                    }
                }
        )
    }
    catch {
        Write-Verbose "Volume data is not available: $($_.Exception.Message)"
    }

    # --- Drive health (administrators only) ---------------------------------------
    # The drives are asked at most every 30 seconds: the values change slowly and the
    # question takes a moment.
    $driveHealth = [PSCustomObject]@{ State = 'RequiresAdmin'; Message = ''; Drives = @() }
    if (Test-IsAdministrator) {
        $cache = $script:DriveHealthCache
        if ($cache -and ((Get-Date) - $cache.At).TotalSeconds -lt 30) {
            $driveHealth = $cache.Value
        }
        else {
            try {
                $drives = @(
                    Get-DriveReliability | ForEach-Object {
                        [PSCustomObject]@{
                            Name         = $_.Name
                            TemperatureC = $_.Temperature
                            WearPercent  = $_.Wear
                            PowerOnHours = $_.PowerOnHours
                        }
                    }
                )
                $driveHealth = [PSCustomObject]@{ State = 'OK'; Message = ''; Drives = $drives }
            }
            catch {
                $driveHealth = [PSCustomObject]@{ State = 'Unavailable'; Message = $_.Exception.Message; Drives = @() }
            }
            $script:DriveHealthCache = @{ At = Get-Date; Value = $driveHealth }
        }
    }

    # --- Network -----------------------------------------------------------------
    $network = @()
    try {
        $network = @(
            & $cim 'Win32_PerfFormattedData_Tcpip_NetworkInterface' |
                Where-Object { $_.CurrentBandwidth -gt 0 } |
                Sort-Object -Property Name |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name                   = [string]$_.Name
                        ReceivedBytesPerSecond = [double]$_.BytesReceivedPersec
                        SentBytesPerSecond     = [double]$_.BytesSentPersec
                        LinkBitsPerSecond      = [double]$_.CurrentBandwidth
                    }
                }
        )
    }
    catch {
        Write-Verbose "Network data is not available: $($_.Exception.Message)"
    }

    # --- Graphics ----------------------------------------------------------------
    # Windows counts graphics load per program and per engine (3D, video decode, ...).
    # An adapter is identified by its "luid". Like Task Manager, the load of an adapter
    # is taken from its busiest engine.
    $gpu = @()
    try {
        $adapterPattern = 'luid_0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+_phys_\d+'
        $engineNames = [ordered]@{ '3D' = '3D'; 'Copy' = 'Copy'; 'VideoDecode' = 'Video decode'; 'VideoEncode' = 'Video encode' }
        $load = @{}
        $engineLoad = @{}
        $engines = @(& $cim 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' |
                Where-Object { $_.Name -match $adapterPattern })

        foreach ($group in ($engines | Group-Object -Property { [regex]::Match($_.Name, $adapterPattern).Value })) {
            # Load per engine type, added up over all programs
            $perEngine = @{}
            foreach ($engineGroup in ($group.Group | Group-Object -Property { ($_.Name -split 'engtype_')[-1] })) {
                $perEngine[$engineGroup.Name] = ($engineGroup.Group | Measure-Object -Property UtilizationPercentage -Sum).Sum
            }
            $load[$group.Name] = ($perEngine.Values | Measure-Object -Maximum).Maximum
            $engineLoad[$group.Name] = @(
                foreach ($type in $engineNames.Keys) {
                    if ($perEngine.ContainsKey($type)) {
                        [PSCustomObject]@{ Name = $engineNames[$type]; Percent = & $limit $perEngine[$type] }
                    }
                }
            )
        }

        $adapters = @(& $cim 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory')
        # The installed adapters do not change while the module is loaded, so the
        # registry is only read for the first snapshot.
        if ($null -eq $script:VideoMemoryCache) {
            $script:VideoMemoryCache = @(Get-VideoMemory)
        }
        $known = @($script:VideoMemoryCache)

        # Software adapters (such as the Microsoft Basic Render Driver) use no dedicated
        # memory and do no work; they are left out.
        $active = @($adapters | Where-Object { $_.DedicatedUsage -gt 0 -or $load[$_.Name] -gt 0 } |
                Sort-Object -Property DedicatedUsage -Descending)

        $index = 1
        $gpu = @(
            foreach ($adapter in $active) {
                # With exactly one real adapter its name and memory size are known for sure.
                $single = $active.Count -eq 1 -and $known.Count -eq 1
                [PSCustomObject]@{
                    Name                = if ($single) { $known[0].Name } else { 'GPU {0}' -f $index }
                    Percent             = & $limit $load[$adapter.Name]
                    Engines             = @($engineLoad[$adapter.Name] | Where-Object { $_ })
                    DedicatedUsedBytes  = [double]$adapter.DedicatedUsage
                    DedicatedTotalBytes = if ($single) { [double]$known[0].Bytes } else { 0 }
                    # Ordinary RAM the adapter borrows when its own memory is not enough.
                    SharedUsedBytes     = [double]$adapter.SharedUsage
                }
                $index++
            }
        )
    }
    catch {
        Write-Verbose "Graphics data is not available: $($_.Exception.Message)"
    }

    # --- Sensors of the graphics card (NVIDIA only) -------------------------------
    $gpuSensors = @()
    try {
        $gpuSensors = @(Get-NvidiaGpuStatus)
    }
    catch {
        Write-Verbose "Graphics sensors are not available: $($_.Exception.Message)"
    }

    # --- Thermal zones -------------------------------------------------------------
    # Temperatures the firmware itself reports, in tenths of a kelvin. Laptops usually
    # have them, desktops rarely. Zones that report nothing useful are left out.
    $thermal = @()
    try {
        $thermal = @(
            & $cim 'Win32_PerfFormattedData_Counters_ThermalZoneInformation' |
                Sort-Object -Property Name |
                ForEach-Object {
                    $kelvin = if ($_.HighPrecisionTemperature -gt 0) { [double]$_.HighPrecisionTemperature / 10 } else { [double]$_.Temperature }
                    if ($kelvin -gt 273) {
                        [PSCustomObject]@{
                            # "\_TZ.TZ00" is shown as "TZ00"
                            Name         = ([string]$_.Name -split '\.')[-1].Trim('\', '_')
                            TemperatureC = [int][math]::Round($kelvin - 273.15)
                        }
                    }
                }
        )
    }
    catch {
        Write-Verbose "Thermal zone data is not available: $($_.Exception.Message)"
    }

    # --- Battery -----------------------------------------------------------------
    $battery = $null
    try {
        $cell = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1
        if ($cell) {
            # Status 1, 4 and 5 mean the computer runs on the battery.
            $pluggedIn = [int]$cell.BatteryStatus -notin 1, 4, 5
            # While plugged in, the remaining time is reported as a very large number.
            $minutes = if (-not $pluggedIn -and $cell.EstimatedRunTime -gt 0 -and $cell.EstimatedRunTime -lt 6000) { [int]$cell.EstimatedRunTime } else { $null }
            $battery = [PSCustomObject]@{
                Percent          = & $limit $cell.EstimatedChargeRemaining
                PluggedIn        = $pluggedIn
                MinutesRemaining = $minutes
            }
        }
    }
    catch {
        Write-Verbose "Battery data is not available: $($_.Exception.Message)"
    }

    # --- Programs ----------------------------------------------------------------
    $processes = @()
    $memoryProcesses = @()
    $ioProcesses = @()
    $threads = $null
    $handles = $null
    try {
        $processRows = @(& $cim 'Win32_PerfFormattedData_PerfProc_Process')

        $allProcesses = $processRows | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        if ($allProcesses) {
            $threads = [int]$allProcesses.ThreadCount
            $handles = [int]$allProcesses.HandleCount
        }

        $programs = @(
            $processRows |
                Where-Object { $_.Name -notin '_Total', 'Idle' } |
                # Several processes of one program are named "chrome", "chrome#1", ...
                Group-Object -Property { $_.Name -replace '#\d+$', '' } |
                ForEach-Object {
                    $processorTime = ($_.Group | Measure-Object -Property PercentProcessorTime -Sum).Sum
                    [PSCustomObject]@{
                        Name             = $_.Name
                        # The counter adds up all logical processors: 200 means two of them
                        # fully used. Divided by their number it matches Task Manager.
                        Percent          = & $limit ($processorTime / $logicalCount)
                        MemoryBytes      = [double]($_.Group | Measure-Object -Property WorkingSetPrivate -Sum).Sum
                        # Data read and written per second: files, network and devices together
                        IoBytesPerSecond = [double]($_.Group | Measure-Object -Property IOReadBytesPersec -Sum).Sum +
                            [double]($_.Group | Measure-Object -Property IOWriteBytesPersec -Sum).Sum
                    }
                }
        )
        $processes = @($programs | Sort-Object -Property Percent, MemoryBytes -Descending | Select-Object -First $TopProcessCount)
        $memoryProcesses = @($programs | Sort-Object -Property MemoryBytes -Descending | Select-Object -First $TopProcessCount)
        $ioProcesses = @($programs | Where-Object { $_.IoBytesPerSecond -gt 0 } |
                Sort-Object -Property IoBytesPerSecond -Descending | Select-Object -First $TopProcessCount)
    }
    catch {
        Write-Verbose "Process data is not available: $($_.Exception.Message)"
    }

    # --- System ------------------------------------------------------------------
    $system = $null
    if ($os) {
        $system = [PSCustomObject]@{
            Processes     = [int]$os.NumberOfProcesses
            Threads       = $threads
            Handles       = $handles
            UptimeSeconds = if ($os.LastBootUpTime) { [long]((Get-Date) - $os.LastBootUpTime).TotalSeconds } else { $null }
        }
    }

    # --- Answer time of the router and the internet --------------------------------
    $latency = $null
    if ($IncludeLatency) {
        try {
            $latency = Get-NetworkLatency -TimeoutMs (Get-HealthThreshold).Monitor.LatencyTimeoutMs
        }
        catch {
            Write-Verbose "The answer times could not be measured: $($_.Exception.Message)"
        }
    }

    [PSCustomObject]@{
        PSTypeName      = 'HelpdeskToolkit.PerformanceSnapshot'
        TakenAt         = Get-Date
        Cpu             = $cpu
        System          = $system
        Memory          = $memory
        Gpu             = $gpu
        GpuSensors      = $gpuSensors
        Disks           = $disks
        Volumes         = $volumes
        DriveHealth     = $driveHealth
        Network         = $network
        Latency         = $latency
        Thermal         = $thermal
        Battery         = $battery
        Processes       = $processes
        MemoryProcesses = $memoryProcesses
        IoProcesses     = $ioProcesses
    }
}
