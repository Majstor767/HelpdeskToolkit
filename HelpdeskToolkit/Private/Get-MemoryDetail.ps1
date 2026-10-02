function Get-MemoryDetail {
    <#
    .SYNOPSIS
        Returns everything Windows knows about the memory, as sections of a detail page.
    .DESCRIPTION
        Used by the Live monitor when its Memory tile is clicked. The sections:

        - Memory:          how much is installed, how much of it Windows can use, the
                           slots of the motherboard and what it supports at most
        - Module:          one section per memory module, with everything needed to
                           order a matching one
        - Usage right now: what the memory is used for at this moment, and how often
                           Windows has to fetch data from the disk
        - Page file:       the files Windows moves data to when the memory is full
        - and, marked as raw, every property of the WMI objects these values come from

        A source that cannot be read is left out; the other sections are still
        returned. Only WMI is read.
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

    $size = { param($Bytes) if ($Bytes -gt 0) { Format-ByteSize -Bytes ([double]$Bytes) } }

    # Codes of the SMBIOS standard, as far as they are found in computers that run Windows 10 or 11
    $typeNames = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'; 29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $formFactors = @{ 8 = 'DIMM (desktop)'; 12 = 'SODIMM (laptop)' }
    $corrections = @{ 3 = 'None'; 4 = 'Parity'; 5 = 'Single-bit ECC'; 6 = 'Multi-bit ECC'; 7 = 'CRC' }

    $modules = @(& $read 'Win32_PhysicalMemory')
    $arrays = @(& $read 'Win32_PhysicalMemoryArray')
    $os = & $read 'Win32_OperatingSystem' | Select-Object -First 1

    # --- Overview ----------------------------------------------------------------------
    $installed = if ($modules.Count -gt 0) { [double]($modules | Measure-Object -Property Capacity -Sum).Sum } else { 0 }
    $usable = if ($os) { [double]$os.TotalVisibleMemorySize * 1KB } else { 0 }
    $slots = if ($arrays.Count -gt 0) { [int]($arrays | Measure-Object -Property MemoryDevices -Sum).Sum } else { 0 }

    # The largest amount is given in kilobytes; older firmware only fills the 32-bit field.
    $maximum = 0
    foreach ($array in $arrays) {
        $maximum += if ($array.MaxCapacityEx) { [double]$array.MaxCapacityEx * 1KB } else { [double]$array.MaxCapacity * 1KB }
    }

    $types = @($modules | ForEach-Object { $typeNames[[int]$_.SMBIOSMemoryType] } | Where-Object { $_ } | Select-Object -Unique)

    Format-DetailSection -Title 'Memory' -Row @(
        Format-DetailRow 'Installed' (& $size $installed)
        Format-DetailRow 'Usable by Windows' (& $size $usable)
        if ($installed -gt $usable -and $usable -gt 0) {
            Format-DetailRow 'Reserved for hardware' (& $size ($installed - $usable))
        }
        Format-DetailRow 'Type' ($types -join ', ')
        if ($slots -gt 0) {
            Format-DetailRow 'Slots' ('{0} of {1} used' -f $modules.Count, $slots)
        }
        Format-DetailRow 'Largest amount the motherboard supports' (& $size $maximum)
        if ($arrays.Count -gt 0) {
            Format-DetailRow 'Error correction' $corrections[[int]$arrays[0].MemoryErrorCorrection]
        }
    )

    # --- One section per module ----------------------------------------------------------
    foreach ($module in $modules) {
        $voltage = if ($module.ConfiguredVoltage) { '{0} V' -f [string]([double]$module.ConfiguredVoltage / 1000) } else { '' }

        Format-DetailSection -Title ('Module: {0}' -f ([string]$module.DeviceLocator).Trim()) -Row @(
            Format-DetailRow 'Size' (& $size $module.Capacity)
            Format-DetailRow 'Type' $typeNames[[int]$module.SMBIOSMemoryType]
            Format-DetailRow 'Form' $formFactors[[int]$module.FormFactor]
            # Speed is what the module is built for; the configured speed is what it
            # really runs at, for example with a memory profile (XMP) turned on.
            Format-DetailRow 'Speed of the module' $module.Speed -Unit 'MHz'
            Format-DetailRow 'Speed it runs at' $module.ConfiguredClockSpeed -Unit 'MHz'
            Format-DetailRow 'Voltage' $voltage
            Format-DetailRow 'Maker' $module.Manufacturer
            Format-DetailRow 'Part number' $module.PartNumber
            Format-DetailRow 'Serial number' $module.SerialNumber
            Format-DetailRow 'Bank' $module.BankLabel
            Format-DetailRow 'Data width' $module.DataWidth -Unit 'bit'
            Format-DetailRow 'Total width' $module.TotalWidth -Unit 'bit'
        )
    }

    # --- Usage -------------------------------------------------------------------------
    $usage = & $read 'Win32_PerfFormattedData_PerfOS_Memory' | Select-Object -First 1
    Format-DetailSection -Title 'Usage right now' -Row @(
        if ($usage) {
            if ($usable -gt 0) {
                Format-DetailRow 'In use' (& $size ($usable - [double]$usage.AvailableBytes))
            }
            Format-DetailRow 'Available' (& $size $usage.AvailableBytes)
            Format-DetailRow 'Standby (kept for reuse, given back at once)' (& $size ([double]$usage.StandbyCacheNormalPriorityBytes + [double]$usage.StandbyCacheReserveBytes + [double]$usage.StandbyCacheCoreBytes))
            Format-DetailRow 'Modified (waits to be written to the disk)' (& $size $usage.ModifiedPageListBytes)
            Format-DetailRow 'Free' (& $size $usage.FreeAndZeroPageListBytes)
            Format-DetailRow 'Committed' (& $size $usage.CommittedBytes)
            Format-DetailRow 'Commit limit (RAM plus page file)' (& $size $usage.CommitLimit)
            Format-DetailRow 'Paged pool' (& $size $usage.PoolPagedBytes)
            Format-DetailRow 'Non-paged pool' (& $size $usage.PoolNonpagedBytes)
            Format-DetailRow 'Page faults per second' $usage.PageFaultsPersec
            Format-DetailRow 'Pages read from the disk per second' $usage.PagesInputPersec
            Format-DetailRow 'Pages written to the disk per second' $usage.PagesOutputPersec
        }
    )

    # --- Page files (sizes in megabytes) -------------------------------------------------
    $pageFiles = @(& $read 'Win32_PageFileUsage')
    foreach ($pageFile in $pageFiles) {
        Format-DetailSection -Title ('Page file: {0}' -f $pageFile.Name) -Row @(
            Format-DetailRow 'Size' (& $size ([double]$pageFile.AllocatedBaseSize * 1MB))
            Format-DetailRow 'In use' ('{0} MB' -f $pageFile.CurrentUsage)
            Format-DetailRow 'Highest use since Windows started' ('{0} MB' -f $pageFile.PeakUsage)
        )
    }

    # --- Everything Windows reports ----------------------------------------------------
    foreach ($module in $modules) {
        Format-DetailSection -Raw -Title ('Win32_PhysicalMemory ({0})' -f ([string]$module.DeviceLocator).Trim()) -Row @($module | ConvertTo-DetailRow)
    }
    foreach ($array in $arrays) {
        Format-DetailSection -Raw -Title 'Win32_PhysicalMemoryArray' -Row @($array | ConvertTo-DetailRow)
    }
    Format-DetailSection -Raw -Title 'Win32_PerfFormattedData_PerfOS_Memory' -Row @($usage | ConvertTo-DetailRow)
    foreach ($pageFile in $pageFiles) {
        Format-DetailSection -Raw -Title 'Win32_PageFileUsage' -Row @($pageFile | ConvertTo-DetailRow)
    }
}
