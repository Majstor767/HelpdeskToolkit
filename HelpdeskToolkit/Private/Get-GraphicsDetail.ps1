function Get-GraphicsDetail {
    <#
    .SYNOPSIS
        Returns everything Windows knows about the graphics cards, as sections of a detail page.
    .DESCRIPTION
        Used by the Live monitor when its Graphics tile is clicked. The sections:

        - Adapter:         one section per graphics adapter: what it is, its driver
                           and the picture it sends to the display
        - NVIDIA:          what the card reports through nvidia-smi, the status tool of
                           its driver: temperatures, fan, power, clock speeds (NVIDIA
                           cards only; other makes have no comparable tool)
        - Programs using the graphics card right now, with the graphics memory each
          of them holds
        - Displays:        the connected monitors with their size
        - and, marked as raw, every property of the WMI objects these values come from

        A source that cannot be read is left out; the other sections are still
        returned. WMI and the registry are read, and nvidia-smi is run.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # All objects of a WMI class, or nothing when the class cannot be read.
    $read = {
        param([string]$Class, [string]$Namespace = 'root/cimv2')
        try {
            @(Get-CimInstance -Namespace $Namespace -ClassName $Class -ErrorAction Stop)
        }
        catch {
            Write-Verbose "$Class is not available: $($_.Exception.Message)"
            @()
        }
    }

    $degree = [string][char]176

    # --- Adapters ----------------------------------------------------------------------
    $adapters = @(& $read 'Win32_VideoController')
    $videoMemory = @()
    try {
        $videoMemory = @(Get-VideoMemory)
    }
    catch {
        Write-Verbose "The graphics memory is not available: $($_.Exception.Message)"
    }

    foreach ($adapter in $adapters) {
        # WMI cannot report more than 4 GB of graphics memory; the driver can.
        $known = $videoMemory | Where-Object { $_.Name -eq $adapter.Name } | Select-Object -First 1
        $memory = if ($known) { Format-ByteSize -Bytes $known.Bytes } elseif ($adapter.AdapterRAM -gt 0) { Format-ByteSize -Bytes ([double]$adapter.AdapterRAM) } else { '' }

        $resolution = if ($adapter.CurrentHorizontalResolution) { '{0} x {1}' -f $adapter.CurrentHorizontalResolution, $adapter.CurrentVerticalResolution } else { '' }
        $range = if ($adapter.MinRefreshRate -and $adapter.MaxRefreshRate) { '{0} - {1} Hz' -f $adapter.MinRefreshRate, $adapter.MaxRefreshRate } else { '' }
        $driverDate = if ($adapter.DriverDate) { '{0:yyyy-MM-dd}' -f $adapter.DriverDate } else { '' }
        # The driver files are listed with their full paths; the names are enough.
        $files = @(([string]$adapter.InstalledDisplayDrivers) -split ',' | ForEach-Object { Split-Path -Path $_.Trim() -Leaf } | Where-Object { $_ } | Select-Object -Unique)

        Format-DetailSection -Title ('Adapter: {0}' -f $adapter.Name) -Row @(
            Format-DetailRow 'Maker' $adapter.AdapterCompatibility
            Format-DetailRow 'Graphics processor' $adapter.VideoProcessor
            Format-DetailRow 'Memory of its own' $memory
            Format-DetailRow 'Converter to the display signal' $adapter.AdapterDACType
            Format-DetailRow 'Driver version' $adapter.DriverVersion
            Format-DetailRow 'Driver date' $driverDate
            Format-DetailRow 'Driver files' ($files -join ', ')
            Format-DetailRow 'Driver setup file' $adapter.InfFilename
            Format-DetailRow 'Resolution' $resolution
            Format-DetailRow 'Refresh rate' $adapter.CurrentRefreshRate -Unit 'Hz'
            Format-DetailRow 'Refresh rates it supports' $range
            Format-DetailRow 'Color depth' $adapter.CurrentBitsPerPixel -Unit 'bit'
            Format-DetailRow 'Video mode' $adapter.VideoModeDescription
            Format-DetailRow 'Status' $adapter.Status
            Format-DetailRow 'Device ID' $adapter.PNPDeviceID
        )
    }

    # --- NVIDIA cards --------------------------------------------------------------------
    # Two questions: the second one uses fields that older drivers do not know, and
    # one unknown field makes the tool refuse the whole question.
    $fields = { param($Line) , @(([string]$Line) -split ',' | ForEach-Object { $_.Trim() }) }
    # A value the card does not have is printed as "[N/A]" or "[Not Supported]".
    $value = {
        param($List, [int]$Index)
        $items = @($List)
        if ($Index -lt $items.Count -and $items[$Index] -notmatch '^\[') {
            $items[$Index]
        }
    }

    $basic = @()
    $extended = @()
    try {
        $basic = @(Invoke-NvidiaSmi -Query 'name,driver_version,vbios_version,pci.bus_id,temperature.gpu,fan.speed,power.draw,power.limit,utilization.gpu,utilization.memory,memory.used,memory.total')
        $extended = @(Invoke-NvidiaSmi -Query 'clocks.current.graphics,clocks.current.memory,clocks.max.graphics,clocks.max.memory,pstate,utilization.encoder,utilization.decoder')
    }
    catch {
        Write-Verbose "nvidia-smi is not available: $($_.Exception.Message)"
    }

    for ($index = 0; $index -lt $basic.Count; $index++) {
        $card = & $fields $basic[$index]
        if ($card.Count -lt 12) {
            continue
        }
        $more = @()
        if ($index -lt $extended.Count) {
            $more = & $fields $extended[$index]
        }

        Format-DetailSection -Title ('NVIDIA: {0}' -f $card[0]) -Row @(
            Format-DetailRow 'Temperature' (& $value $card 4) -Unit ('{0}C' -f $degree)
            Format-DetailRow 'Fan' (& $value $card 5) -Unit '%'
            Format-DetailRow 'Power draw' (& $value $card 6) -Unit 'W'
            Format-DetailRow 'Power limit' (& $value $card 7) -Unit 'W'
            Format-DetailRow 'Load of the graphics processor' (& $value $card 8) -Unit '%'
            Format-DetailRow 'Load of the memory controller' (& $value $card 9) -Unit '%'
            Format-DetailRow 'Memory in use' (& $value $card 10) -Unit 'MB'
            Format-DetailRow 'Memory in total' (& $value $card 11) -Unit 'MB'
            Format-DetailRow 'Clock of the graphics processor' (& $value $more 0) -Unit 'MHz'
            Format-DetailRow 'Clock of the memory' (& $value $more 1) -Unit 'MHz'
            Format-DetailRow 'Highest clock of the graphics processor' (& $value $more 2) -Unit 'MHz'
            Format-DetailRow 'Highest clock of the memory' (& $value $more 3) -Unit 'MHz'
            Format-DetailRow 'Performance state (P0 is the fastest)' (& $value $more 4)
            Format-DetailRow 'Load of the video encoder' (& $value $more 5) -Unit '%'
            Format-DetailRow 'Load of the video decoder' (& $value $more 6) -Unit '%'
            Format-DetailRow 'Driver version' (& $value $card 1)
            Format-DetailRow 'Firmware version' (& $value $card 2)
            Format-DetailRow 'Place on the PCI bus' (& $value $card 3)
        )
    }

    # --- Programs ----------------------------------------------------------------------
    # Windows counts graphics load and graphics memory per process; the name of a
    # counter starts with "pid_<number>". Like in Task Manager, the load of a process is
    # that of its busiest engine. Processes of the same program are added up.
    $perProcess = @{}
    $note = {
        param([int]$Id)
        if (-not $perProcess.ContainsKey($Id)) {
            $perProcess[$Id] = @{ Engines = @{}; Bytes = [double]0 }
        }
        $perProcess[$Id]
    }

    foreach ($engine in (& $read 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine')) {
        if ($engine.Name -match '^pid_(\d+)_.*engtype_(.+)$') {
            $entry = & $note ([int]$Matches[1])
            $entry.Engines[$Matches[2]] = [double]$entry.Engines[$Matches[2]] + [double]$engine.UtilizationPercentage
        }
    }
    $processMemory = @(& $read 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory')
    foreach ($usage in $processMemory) {
        if ($usage.Name -match '^pid_(\d+)_') {
            $entry = & $note ([int]$Matches[1])
            $entry.Bytes += [double]$usage.DedicatedUsage
        }
    }

    $programs = @{}
    foreach ($id in $perProcess.Keys) {
        $entry = $perProcess[$id]
        $percent = if ($entry.Engines.Count -gt 0) { [double]($entry.Engines.Values | Measure-Object -Maximum).Maximum } else { 0 }
        if ($percent -lt 1 -and $entry.Bytes -lt 1MB) {
            continue
        }
        $process = Get-Process -Id $id -ErrorAction SilentlyContinue
        $name = if ($process) { [string]$process.ProcessName } else { 'Process {0}' -f $id }
        if (-not $programs.ContainsKey($name)) {
            $programs[$name] = @{ Percent = [double]0; Bytes = [double]0 }
        }
        $programs[$name].Percent += $percent
        $programs[$name].Bytes += $entry.Bytes
    }

    Format-DetailSection -Title 'Programs using the graphics card right now' -KeepNames -Row @(
        $programs.GetEnumerator() |
            Sort-Object -Property @{ Expression = { $_.Value.Percent }; Descending = $true }, @{ Expression = { $_.Value.Bytes }; Descending = $true }, Name |
            Select-Object -First 15 |
            ForEach-Object {
                Format-DetailRow $_.Key ('{0} %  |  {1} graphics memory' -f [int][math]::Min(100, [math]::Round($_.Value.Percent)), (Format-ByteSize -Bytes $_.Value.Bytes))
            }
    )

    # --- Displays ----------------------------------------------------------------------
    # A monitor describes itself to Windows; the texts arrive as lists of character
    # codes padded with zeros, the size of the picture in centimeters.
    $monitors = @(& $read 'WmiMonitorID' 'root/wmi')
    $sizes = @(& $read 'WmiMonitorBasicDisplayParams' 'root/wmi')
    Format-DetailSection -Title 'Displays' -KeepNames -Row @(
        foreach ($monitor in $monitors) {
            $name = (-join ($monitor.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })).Trim()
            $maker = (-join ($monitor.ManufacturerName | Where-Object { $_ } | ForEach-Object { [char]$_ })).Trim()
            if (-not $name) {
                $name = 'Built-in or generic display'
            }

            $parts = @()
            $screen = $sizes | Where-Object { $_.InstanceName -eq $monitor.InstanceName } | Select-Object -First 1
            if ($screen -and $screen.MaxHorizontalImageSize -gt 0 -and $screen.MaxVerticalImageSize -gt 0) {
                $diagonal = [math]::Sqrt([math]::Pow($screen.MaxHorizontalImageSize, 2) + [math]::Pow($screen.MaxVerticalImageSize, 2)) / 2.54
                $parts += '{0} inch ({1} x {2} cm)' -f [string][math]::Round($diagonal, 1), $screen.MaxHorizontalImageSize, $screen.MaxVerticalImageSize
            }
            if ($maker) {
                $parts += 'maker code {0}' -f $maker
            }
            if ($monitor.YearOfManufacture) {
                $parts += 'made in {0}' -f $monitor.YearOfManufacture
            }
            if ($parts.Count -eq 0) {
                $parts += 'connected'
            }
            Format-DetailRow $name ($parts -join ', ')
        }
    )

    # --- Everything Windows reports ----------------------------------------------------
    foreach ($adapter in $adapters) {
        Format-DetailSection -Raw -Title ('Win32_VideoController ({0})' -f $adapter.Name) -Row @($adapter | ConvertTo-DetailRow)
    }
    foreach ($usage in (& $read 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory')) {
        Format-DetailSection -Raw -Title ('Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory ({0})' -f $usage.Name) -Row @($usage | ConvertTo-DetailRow)
    }
}
