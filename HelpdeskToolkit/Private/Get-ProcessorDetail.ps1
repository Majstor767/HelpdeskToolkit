function Get-ProcessorDetail {
    <#
    .SYNOPSIS
        Returns everything Windows knows about the processor, as sections of a detail page.
    .DESCRIPTION
        Used by the Live monitor when its Processor tile is clicked. The sections:

        - Processor:          what the processor is (one section per socket)
        - Cache:              the cache memories of the processor
        - Activity right now: where the processor time goes (programs, Windows,
                              hardware) and how busy the scheduler is
        - Computer:           sockets, hypervisor and the power plan, which decides how
                              fast the processor may run
        - and, marked as raw, every property of the WMI objects these values come from

        A source that cannot be read is left out; the other sections are still
        returned. Only WMI and the registry are read.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # All objects of a WMI class, or nothing when the class cannot be read.
    $read = {
        param([string]$Class)
        try {
            @(Get-CimInstance -ClassName $Class -ErrorAction Stop)
        }
        catch {
            Write-Verbose "$Class is not available: $($_.Exception.Message)"
            @()
        }
    }

    $yesNo = { param($Value) if ($null -eq $Value) { '' } elseif ($Value) { 'Yes' } else { 'No' } }
    $architectures = @{ 0 = 'x86 (32 bit)'; 5 = 'ARM'; 9 = 'x64 (64 bit)'; 12 = 'ARM64' }

    # --- The processor itself --------------------------------------------------------
    $processors = @(& $read 'Win32_Processor')
    foreach ($processor in $processors) {
        $title = if ($processors.Count -gt 1) { 'Processor ({0})' -f $processor.SocketDesignation } else { 'Processor' }

        # The voltage is only meaningful when the highest bit of the field is set:
        # the rest is then the voltage in tenths of a volt.
        $voltage = ''
        if ($processor.CurrentVoltage -band 0x80) {
            $voltage = '{0} V' -f [string](($processor.CurrentVoltage -band 0x7F) / 10)
        }

        Format-DetailSection -Title $title -Row @(
            Format-DetailRow 'Name' $processor.Name
            Format-DetailRow 'Maker' $processor.Manufacturer
            Format-DetailRow 'Description' $processor.Description
            Format-DetailRow 'Architecture' $architectures[[int]$processor.Architecture]
            Format-DetailRow 'Socket' $processor.SocketDesignation
            Format-DetailRow 'Cores' $processor.NumberOfCores
            Format-DetailRow 'Cores in use' $processor.NumberOfEnabledCore
            Format-DetailRow 'Logical processors' $processor.NumberOfLogicalProcessors
            Format-DetailRow 'Base speed' $processor.MaxClockSpeed -Unit 'MHz'
            Format-DetailRow 'Speed of the bus' $processor.ExtClock -Unit 'MHz'
            if ($processor.L2CacheSize) { Format-DetailRow 'L2 cache' (Format-ByteSize -Bytes ([double]$processor.L2CacheSize * 1KB)) }
            if ($processor.L3CacheSize) { Format-DetailRow 'L3 cache' (Format-ByteSize -Bytes ([double]$processor.L3CacheSize * 1KB)) }
            Format-DetailRow 'Virtualization turned on in the firmware' (& $yesNo $processor.VirtualizationFirmwareEnabled)
            Format-DetailRow 'Extensions for virtual machines' (& $yesNo $processor.VMMonitorModeExtensions)
            Format-DetailRow 'Second level address translation' (& $yesNo $processor.SecondLevelAddressTranslationExtensions)
            Format-DetailRow 'Address width' $processor.AddressWidth -Unit 'bit'
            Format-DetailRow 'Data width' $processor.DataWidth -Unit 'bit'
            Format-DetailRow 'Voltage' $voltage
            Format-DetailRow 'Processor ID' $processor.ProcessorId
            Format-DetailRow 'Status' $processor.Status
        )
    }

    # --- Cache -----------------------------------------------------------------------
    $caches = @(& $read 'Win32_CacheMemory')
    Format-DetailSection -Title 'Cache' -KeepNames -Row @(
        foreach ($cache in $caches) {
            if ($cache.InstalledSize) {
                Format-DetailRow ([string]$cache.Purpose) (Format-ByteSize -Bytes ([double]$cache.InstalledSize * 1KB))
            }
        }
    )

    # --- Activity ----------------------------------------------------------------------
    $times = & $read 'Win32_PerfFormattedData_PerfOS_Processor' | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    $system = & $read 'Win32_PerfFormattedData_PerfOS_System' | Select-Object -First 1
    Format-DetailSection -Title 'Activity right now' -Row @(
        if ($times) {
            Format-DetailRow 'Time spent in programs' $times.PercentUserTime -Unit '%'
            Format-DetailRow 'Time spent in Windows itself' $times.PercentPrivilegedTime -Unit '%'
            Format-DetailRow 'Time spent on signals from hardware' $times.PercentInterruptTime -Unit '%'
            Format-DetailRow 'Time spent on postponed work of drivers' $times.PercentDPCTime -Unit '%'
            Format-DetailRow 'Idle' $times.PercentIdleTime -Unit '%'
            Format-DetailRow 'Signals from hardware per second' $times.InterruptsPersec
        }
        if ($system) {
            Format-DetailRow 'Switches between programs per second' $system.ContextSwitchesPersec
            Format-DetailRow 'Requests to Windows per second' $system.SystemCallsPersec
            Format-DetailRow 'Threads waiting for a free processor' $system.ProcessorQueueLength
            Format-DetailRow 'Processes' $system.Processes
            Format-DetailRow 'Threads' $system.Threads
        }
    )

    # --- The computer around it --------------------------------------------------------
    $computer = & $read 'Win32_ComputerSystem' | Select-Object -First 1
    $powerPlan = ''
    try {
        $powerPlan = Get-PowerPlanName
    }
    catch {
        Write-Verbose "The power plan is not available: $($_.Exception.Message)"
    }
    Format-DetailSection -Title 'Computer' -Row @(
        if ($computer) {
            Format-DetailRow 'Processor sockets in use' $computer.NumberOfProcessors
            Format-DetailRow 'Logical processors in total' $computer.NumberOfLogicalProcessors
            Format-DetailRow 'Runs under a hypervisor' (& $yesNo $computer.HypervisorPresent)
        }
        Format-DetailRow 'Power plan' $powerPlan
    )

    # --- Everything Windows reports ----------------------------------------------------
    foreach ($processor in $processors) {
        Format-DetailSection -Raw -Title 'Win32_Processor' -Row @($processor | ConvertTo-DetailRow)
    }
    foreach ($cache in $caches) {
        Format-DetailSection -Raw -Title ('Win32_CacheMemory ({0})' -f $cache.DeviceID) -Row @($cache | ConvertTo-DetailRow)
    }
    Format-DetailSection -Raw -Title 'Win32_PerfFormattedData_PerfOS_Processor (_Total)' -Row @($times | ConvertTo-DetailRow)
    $information = & $read 'Win32_PerfFormattedData_Counters_ProcessorInformation' | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
    Format-DetailSection -Raw -Title 'Win32_PerfFormattedData_Counters_ProcessorInformation (_Total)' -Row @($information | ConvertTo-DetailRow)
    Format-DetailSection -Raw -Title 'Win32_PerfFormattedData_PerfOS_System' -Row @($system | ConvertTo-DetailRow)
}
