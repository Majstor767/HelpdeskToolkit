function Get-ComputerSpecification {
    <#
    .SYNOPSIS
        Lists the hardware specification of the computer.
    .DESCRIPTION
        Collects what a technician usually has to look up before answering "can this
        computer run it?" or "what do we need to order?":

        - processor model, cores, threads and clock speed
        - installed memory, module layout, type, speed and free slots
        - graphics adapters with driver version and current resolution
        - connected displays with manufacturer code and year of manufacture
        - motherboard, BIOS/UEFI version and date
        - serial number, for warranty and inventory lookups

        Everything is informational (status Info); health verdicts are produced by
        Get-HardwareHealth. The data is read through CIM (WMI) without administrator
        rights and nothing on the system is changed.
    .EXAMPLE
        Get-ComputerSpecification

        Returns one result per component.
    .EXAMPLE
        Get-ComputerSpecification | Format-Table Check, Value -AutoSize

        Shows the specification as a compact table.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'Specifications'

    # Processor
    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        $cores = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
        $threads = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $clockGhz = [string][math]::Round([double]$processors[0].MaxClockSpeed / 1000, 1)
        New-CheckResult -Category $category -Check 'Processor' -Status Info `
            -Value ('{0}, {1} cores / {2} threads, {3} GHz' -f ([string]$processors[0].Name).Trim(), $cores, $threads, $clockGhz)
    }
    catch {
        New-FailureResult -Category $category -Check 'Processor' -ErrorRecord $_
    }

    # Memory modules
    try {
        $modules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        if ($modules.Count -eq 0) {
            # Typical for virtual machines, which have no physical modules.
            New-CheckResult -Category $category -Check 'Memory' -Status Info -Value 'No module information available'
        }
        else {
            $totalBytes = ($modules | Measure-Object -Property Capacity -Sum).Sum
            $sizes = @($modules | ForEach-Object { Format-Gigabyte -Bytes $_.Capacity })
            $layout = if (@($sizes | Select-Object -Unique).Count -eq 1) {
                '{0} x {1}' -f $modules.Count, $sizes[0]
            }
            else {
                $sizes -join ' + '
            }

            # SMBIOS memory type codes of the generations still found in the field.
            $typeNames = @{ 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5' }
            $type = $typeNames[[int]$modules[0].SMBIOSMemoryType]
            if ($type) {
                $layout = '{0} {1}' -f $layout, $type
            }

            # ConfiguredClockSpeed is the speed the module really runs at (for example
            # with XMP enabled); Speed is only the default speed of the module.
            $speeds = @($modules | ForEach-Object { if ($_.ConfiguredClockSpeed) { $_.ConfiguredClockSpeed } else { $_.Speed } } | Where-Object { $_ })
            if ($speeds.Count -gt 0) {
                $layout = '{0}, {1} MHz' -f $layout, ($speeds | Measure-Object -Maximum).Maximum
            }

            $value = '{0} ({1})' -f (Format-Gigabyte -Bytes $totalBytes), $layout

            $slots = (Get-CimInstance -ClassName Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue |
                    Measure-Object -Property MemoryDevices -Sum).Sum
            if ($slots) {
                $value = '{0}, {1} of {2} slots used' -f $value, $modules.Count, $slots
            }

            New-CheckResult -Category $category -Check 'Memory' -Status Info -Value $value
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Memory' -ErrorRecord $_
    }

    # Graphics adapters
    try {
        $adapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        foreach ($adapter in $adapters) {
            $value = '{0} (driver {1})' -f $adapter.Name, $adapter.DriverVersion
            # An adapter without a connected display reports no resolution.
            if ($adapter.CurrentHorizontalResolution) {
                $value = '{0}, {1} x {2} @ {3} Hz' -f $value, $adapter.CurrentHorizontalResolution,
                    $adapter.CurrentVerticalResolution, $adapter.CurrentRefreshRate
            }
            New-CheckResult -Category $category -Check 'Graphics' -Status Info -Value $value
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Graphics' -ErrorRecord $_
    }

    # Displays. A monitor describes itself to Windows; the texts arrive as lists of
    # character codes padded with zeros.
    try {
        $monitors = @(Get-CimInstance -Namespace 'root/wmi' -ClassName WmiMonitorID -ErrorAction Stop)
        foreach ($monitor in $monitors) {
            $name = -join ($monitor.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            $maker = -join ($monitor.ManufacturerName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            if (-not $name) {
                $name = 'Built-in or generic display'
            }
            $details = @($maker, $monitor.YearOfManufacture) | Where-Object { $_ }
            $value = if ($details) { '{0} ({1})' -f $name.Trim(), ($details -join ', ') } else { $name.Trim() }
            New-CheckResult -Category $category -Check 'Display' -Status Info -Value $value
        }
    }
    catch {
        # Virtual machines and remote sessions have no monitor information; that is not a fault.
        Write-Verbose "No monitor information available: $($_.Exception.Message)"
    }

    # Motherboard
    try {
        $board = Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1
        New-CheckResult -Category $category -Check 'Motherboard' -Status Info `
            -Value ('{0} {1}' -f $board.Manufacturer, $board.Product)
    }
    catch {
        New-FailureResult -Category $category -Check 'Motherboard' -ErrorRecord $_
    }

    # BIOS / UEFI and serial number
    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop | Select-Object -First 1

        $value = '{0} {1}' -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion
        if ($bios.ReleaseDate) {
            $value = '{0} ({1:yyyy-MM-dd})' -f $value, $bios.ReleaseDate
        }
        # Windows exposes the boot mode (UEFI or Legacy) as an environment variable.
        if ($env:firmware_type) {
            $value = '{0}, {1} mode' -f $value, $env:firmware_type
        }
        New-CheckResult -Category $category -Check 'BIOS' -Status Info -Value $value

        # Self-built desktops often carry a placeholder instead of a real serial number.
        $placeholders = @('', 'To Be Filled By O.E.M.', 'Default string', 'System Serial Number', 'None', '0')
        $serial = ([string]$bios.SerialNumber).Trim()
        if ($placeholders -contains $serial) {
            $serial = 'Not set by the manufacturer'
        }
        New-CheckResult -Category $category -Check 'Serial number' -Status Info -Value $serial
    }
    catch {
        New-FailureResult -Category $category -Check 'BIOS' -ErrorRecord $_
    }
}
