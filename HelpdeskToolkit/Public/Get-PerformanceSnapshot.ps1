function Get-PerformanceSnapshot {
    <#
    .SYNOPSIS
        Returns what the computer is doing right now: load per processor, memory, disks, network, graphics and the busiest programs.
    .DESCRIPTION
        Takes one measurement of the live performance data that Windows keeps:

        - Cpu:       total load and current clock speed, and the same for every logical
                     processor (a core with hyper-threading counts as two)
        - Memory:    physical memory in use, and committed memory against its limit
        - Disks:     how busy each physical disk is, and its read and write rate
        - Network:   receive and send rate of each network adapter
        - Gpu:       load and dedicated memory in use of each graphics adapter
        - Processes: the programs using the most processor time, grouped by name

        The window (Show-PCHealthCheck) calls this command again and again for its
        "Live monitor" page. In a script it can be used for logging or for a quick look.

        The data comes from the performance classes of WMI, whose names are the same in
        every Windows language. No administrator rights are needed and nothing is
        changed. One measurement takes about two seconds.

        Temperatures, fan speeds and voltages are not included: Windows does not expose
        them, and tools that show them install their own hardware driver.

        A part that cannot be read is returned empty; the other parts are still filled in.
    .PARAMETER TopProcessCount
        How many of the busiest programs to return. The default is 5.
    .EXAMPLE
        Get-PerformanceSnapshot

        Returns one snapshot object.
    .EXAMPLE
        (Get-PerformanceSnapshot).Cpu.Processors | Format-Table Name, Percent, FrequencyMHz

        Shows the load and the clock speed of every logical processor.
    .EXAMPLE
        while ($true) { (Get-PerformanceSnapshot).Processes | Format-Table; Start-Sleep -Seconds 5 }

        Prints the busiest programs every few seconds until Ctrl+C is pressed.
    .OUTPUTS
        HelpdeskToolkit.PerformanceSnapshot
        An object with the properties TakenAt, Cpu, Memory, Disks, Network, Gpu and Processes.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.PerformanceSnapshot')]
    param(
        [ValidateRange(1, 20)]
        [int]$TopProcessCount = 5
    )

    # A counter can momentarily read above 100 or below 0; the display should not.
    $limit = { param($Number) [int][math]::Max(0, [math]::Min(100, [math]::Round([double]$Number))) }

    # --- Processor ---------------------------------------------------------------
    $cpu = $null
    $logicalCount = [Environment]::ProcessorCount
    try {
        $rows = @(Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction Stop)

        # Logical processors are named "group,number" (for example "0,3"); the rows
        # "_Total" and "0,_Total" are sums.
        $logical = @($rows | Where-Object { $_.Name -match '^\d+,\d+$' } |
                Sort-Object -Property @{ Expression = { [int]($_.Name -split ',')[0] } }, @{ Expression = { [int]($_.Name -split ',')[1] } })
        $total = $rows | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1

        if ($logical.Count -gt 0) {
            $logicalCount = $logical.Count
        }

        $index = 0
        $processors = @(
            foreach ($row in $logical) {
                [PSCustomObject]@{
                    Name         = 'CPU {0}' -f $index
                    Percent      = & $limit $row.PercentProcessorUtility
                    FrequencyMHz = [int]$row.ProcessorFrequency
                }
                $index++
            }
        )

        if ($total) {
            $cpu = [PSCustomObject]@{
                Percent      = & $limit $total.PercentProcessorUtility
                FrequencyMHz = [int]$total.ProcessorFrequency
                Processors   = $processors
            }
        }
    }
    catch {
        Write-Verbose "Processor data is not available: $($_.Exception.Message)"
    }

    # --- Memory (both values are reported in kilobytes) --------------------------
    $memory = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        $usedBytes = $totalBytes - ([double]$os.FreePhysicalMemory * 1KB)
        $commitLimit = [double]$os.TotalVirtualMemorySize * 1KB

        $memory = [PSCustomObject]@{
            TotalBytes       = $totalBytes
            UsedBytes        = $usedBytes
            Percent          = & $limit ($usedBytes / $totalBytes * 100)
            CommittedBytes   = $commitLimit - ([double]$os.FreeVirtualMemory * 1KB)
            CommitLimitBytes = $commitLimit
        }
    }
    catch {
        Write-Verbose "Memory data is not available: $($_.Exception.Message)"
    }

    # --- Disks -------------------------------------------------------------------
    $disks = @()
    try {
        $disks = @(
            Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop |
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
                    }
                }
        )
    }
    catch {
        Write-Verbose "Disk data is not available: $($_.Exception.Message)"
    }

    # --- Network -----------------------------------------------------------------
    $network = @()
    try {
        $network = @(
            Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop |
                Where-Object { $_.CurrentBandwidth -gt 0 } |
                Sort-Object -Property Name |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name                   = [string]$_.Name
                        ReceivedBytesPerSecond = [double]$_.BytesReceivedPersec
                        SentBytesPerSecond     = [double]$_.BytesSentPersec
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
        $load = @{}
        $engines = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop |
                Where-Object { $_.Name -match $adapterPattern })

        foreach ($group in ($engines | Group-Object -Property { [regex]::Match($_.Name, $adapterPattern).Value })) {
            $perEngine = $group.Group | Group-Object -Property { ($_.Name -split 'engtype_')[-1] } |
                ForEach-Object { ($_.Group | Measure-Object -Property UtilizationPercentage -Sum).Sum }
            $load[$group.Name] = ($perEngine | Measure-Object -Maximum).Maximum
        }

        $adapters = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop)
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
                    DedicatedUsedBytes  = [double]$adapter.DedicatedUsage
                    DedicatedTotalBytes = if ($single) { [double]$known[0].Bytes } else { 0 }
                }
                $index++
            }
        )
    }
    catch {
        Write-Verbose "Graphics data is not available: $($_.Exception.Message)"
    }

    # --- Busiest programs --------------------------------------------------------
    $processes = @()
    try {
        $processes = @(
            Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop |
                Where-Object { $_.Name -notin '_Total', 'Idle' } |
                # Several processes of one program are named "chrome", "chrome#1", ...
                Group-Object -Property { $_.Name -replace '#\d+$', '' } |
                ForEach-Object {
                    $processorTime = ($_.Group | Measure-Object -Property PercentProcessorTime -Sum).Sum
                    [PSCustomObject]@{
                        Name        = $_.Name
                        # The counter adds up all logical processors: 200 means two of them
                        # fully used. Divided by their number it matches Task Manager.
                        Percent     = & $limit ($processorTime / $logicalCount)
                        MemoryBytes = [double]($_.Group | Measure-Object -Property WorkingSetPrivate -Sum).Sum
                    }
                } |
                Sort-Object -Property Percent, MemoryBytes -Descending |
                Select-Object -First $TopProcessCount
        )
    }
    catch {
        Write-Verbose "Process data is not available: $($_.Exception.Message)"
    }

    [PSCustomObject]@{
        PSTypeName = 'HelpdeskToolkit.PerformanceSnapshot'
        TakenAt    = Get-Date
        Cpu        = $cpu
        Memory     = $memory
        Disks      = $disks
        Network    = $network
        Gpu        = $gpu
        Processes  = $processes
    }
}
