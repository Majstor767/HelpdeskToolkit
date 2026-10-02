function Get-ComputerSpecification {
    <#
    .SYNOPSIS
        Lists the hardware specification of the computer.
    .DESCRIPTION
        Collects what a technician usually has to look up before answering "can this
        computer run it?" or "what do we need to order?":

        - processor model, cores, threads and clock speed, cache sizes and whether
          hardware virtualization is switched on
        - installed memory, module layout, type, speed and free slots, and every
          module with its slot, manufacturer and part number
        - graphics adapters with their memory, driver version and date, and resolution
        - connected displays with manufacturer code and year of manufacture
        - physical drives with size, type and firmware version; optical drives
        - audio devices, keyboards and pointing devices
        - motherboard, BIOS/UEFI version and date, with the advice to look for a newer
          version when it is several years old
        - serial number, and where the warranty is looked up with it (the support page
          of the manufacturer, when it is one of the known makers)

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
        $processors = @()
    }

    # Processor details: cache sizes and hardware virtualization
    if ($processors.Count -gt 0) {
        try {
            # Cache sizes are reported in kilobytes.
            $toCacheSize = {
                param($Kilobytes)
                if ($Kilobytes -ge 1024) { '{0} MB' -f [string][math]::Round([double]$Kilobytes / 1024, 1) } else { '{0} KB' -f $Kilobytes }
            }
            $parts = @()
            if ($processors[0].L2CacheSize) {
                $parts += 'L2 cache {0}' -f (& $toCacheSize $processors[0].L2CacheSize)
            }
            if ($processors[0].L3CacheSize) {
                $parts += 'L3 cache {0}' -f (& $toCacheSize $processors[0].L3CacheSize)
            }
            if ($processors[0].AddressWidth) {
                $parts += '{0}-bit' -f $processors[0].AddressWidth
            }

            # While a hypervisor (Hyper-V, WSL 2, Windows Sandbox) is running, Windows
            # itself runs on top of it and the firmware setting reads as "off".
            $system = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            $parts += if ($processors[0].VirtualizationFirmwareEnabled) {
                'virtualization enabled in firmware'
            }
            elseif ($system.HypervisorPresent) {
                'virtualization in use by a hypervisor'
            }
            else {
                'virtualization disabled in firmware'
            }

            New-CheckResult -Category $category -Check 'Processor details' -Status Info -Value ($parts -join ', ')
        }
        catch {
            New-FailureResult -Category $category -Check 'Processor details' -ErrorRecord $_
        }
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

            # One row per module: the slot it sits in, its size, speed, maker and part
            # number. The part number is what is needed to order a matching module.
            foreach ($module in $modules) {
                $moduleType = $typeNames[[int]$module.SMBIOSMemoryType]
                $moduleSpeed = if ($module.ConfiguredClockSpeed) { $module.ConfiguredClockSpeed } else { $module.Speed }
                $parts = @(
                    (@((Format-Gigabyte -Bytes $module.Capacity), $moduleType) | Where-Object { $_ }) -join ' '
                    if ($moduleSpeed) { '{0} MHz' -f $moduleSpeed }
                    (@($module.Manufacturer, $module.PartNumber) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }) -join ' '
                ) | Where-Object { $_ }

                $slot = ([string]$module.DeviceLocator).Trim()
                $value = if ($slot) { '{0}: {1}' -f $slot, ($parts -join ', ') } else { $parts -join ', ' }
                New-CheckResult -Category $category -Check 'Memory module' -Status Info -Value $value
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Memory' -ErrorRecord $_
    }

    # Graphics adapters
    try {
        $adapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        $videoMemory = @(Get-VideoMemory)
        foreach ($adapter in $adapters) {
            $driver = 'driver {0}' -f $adapter.DriverVersion
            if ($adapter.DriverDate) {
                $driver = '{0} from {1:yyyy-MM-dd}' -f $driver, $adapter.DriverDate
            }
            $value = '{0} ({1})' -f $adapter.Name, $driver

            # WMI cannot report more than 4 GB of graphics memory; the driver can.
            $known = $videoMemory | Where-Object { $_.Name -eq $adapter.Name } | Select-Object -First 1
            if ($known) {
                $value = '{0}, {1} memory ({2})' -f $adapter.Name, (Format-Gigabyte -Bytes $known.Bytes), $driver
            }

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

    # Storage: one row per physical drive. The type and the connection are read with
    # Get-CimPropertyValue: once the Storage module of Windows is loaded in the
    # process, $drive.MediaType is the text "SSD" and no longer the number 4.
    try {
        $mediaTypes = @{ 3 = 'HDD'; 4 = 'SSD' }
        $busTypes = @{ 7 = 'USB'; 11 = 'SATA'; 17 = 'NVMe' }
        $drives = @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop |
                Sort-Object -Property DeviceId)

        foreach ($drive in $drives) {
            $value = '{0}, {1}' -f ([string]$drive.FriendlyName).Trim(), (Format-Gigabyte -Bytes $drive.Size)
            $media = $mediaTypes[[int](Get-CimPropertyValue -InputObject $drive -Name MediaType)]
            if ($media) {
                $value = '{0} {1}' -f $value, $media
            }
            $bus = $busTypes[[int](Get-CimPropertyValue -InputObject $drive -Name BusType)]
            if ($bus) {
                $value = '{0} ({1})' -f $value, $bus
            }
            $firmware = ([string]$drive.FirmwareVersion).Trim()
            if ($firmware) {
                $value = '{0}, firmware {1}' -f $value, $firmware
            }
            New-CheckResult -Category $category -Check 'Storage' -Status Info -Value $value
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Storage' -ErrorRecord $_
    }

    # Optical drives; most current computers have none, and then no row is shown.
    try {
        foreach ($optical in @(Get-CimInstance -ClassName Win32_CDROMDrive -ErrorAction Stop)) {
            $value = if ($optical.Drive) { '{0} ({1})' -f $optical.Name, $optical.Drive } else { [string]$optical.Name }
            New-CheckResult -Category $category -Check 'Optical drive' -Status Info -Value $value
        }
    }
    catch {
        Write-Verbose "No optical drive information available: $($_.Exception.Message)"
    }

    # Audio devices. Devices created by software (virtual microphones and speakers of
    # streaming or voice programs) are listed separately, after the real hardware.
    try {
        $sound = @(Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction Stop)
        if ($sound.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Audio devices' -Status Info -Value 'None found'
        }
        else {
            $hardware = @($sound | Where-Object { $_.PNPDeviceID -notlike 'ROOT\*' } | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
            $virtual = @($sound | Where-Object { $_.PNPDeviceID -like 'ROOT\*' } | ForEach-Object { '{0} (virtual)' -f $_.Name } | Sort-Object -Unique)

            $value = if ($hardware.Count -gt 0) { $hardware -join ', ' } else { 'No hardware device' }
            if ($virtual.Count -gt 0) {
                $value = '{0} and {1} virtual' -f $value, $virtual.Count
            }
            New-CheckResult -Category $category -Check 'Audio devices' -Status Info -Value $value -Details $virtual
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Audio devices' -ErrorRecord $_
    }

    # Keyboards and pointing devices. One device often registers several times, partly
    # under a generic name; generic names are dropped when a real name is known.
    try {
        $names = @(
            @(
                Get-CimInstance -ClassName Win32_Keyboard -ErrorAction Stop | ForEach-Object { [string]$_.Description }
                Get-CimInstance -ClassName Win32_PointingDevice -ErrorAction Stop | ForEach-Object { [string]$_.Name }
            ) | Where-Object { $_ } | Sort-Object -Unique
        )

        $generic = 'USB Input Device', 'HID Keyboard Device', 'HID-compliant mouse'
        $named = @($names | Where-Object { $_ -and $generic -notcontains $_ })
        $value = if ($named.Count -gt 0) {
            $named -join ', '
        }
        elseif ($names.Count -gt 0) {
            'Standard keyboard and mouse'
        }
        else {
            'None found'
        }
        New-CheckResult -Category $category -Check 'Input devices' -Status Info -Value $value
    }
    catch {
        New-FailureResult -Category $category -Check 'Input devices' -ErrorRecord $_
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
        # An old version is no fault, but makers fix security holes and compatibility
        # problems in newer ones, so it is worth a look.
        $oldYears = (Get-HealthThreshold).Bios.OldYears
        $recommendation = ''
        if ($bios.ReleaseDate -and $bios.ReleaseDate -lt (Get-Date).AddYears(-$oldYears)) {
            $recommendation = 'This BIOS/UEFI version is more than {0} years old. Makers fix security holes and problems with newer hardware and Windows versions in later versions; look for one on the support page of the manufacturer. An update is done with the charger connected and must not be interrupted.' -f $oldYears
        }
        New-CheckResult -Category $category -Check 'BIOS' -Status Info -Value $value -Recommendation $recommendation

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

    # Where the warranty is looked up. The makers whose support page is known are
    # listed in Config\Actions.psd1; the window opens that page with a button.
    try {
        $maker = ([string](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1).Manufacturer).Trim()
        if ($maker -and (Get-CheckAction -Check 'Warranty and support' -Category $category -Value $maker)) {
            New-CheckResult -Category $category -Check 'Warranty and support' -Status Info `
                -Value ('{0}: looked up with the serial number on the support page of the manufacturer' -f $maker) `
                -Recommendation 'The support page of the manufacturer shows, for the serial number of this computer, how long the warranty runs and which drivers and BIOS versions are current.'
        }
        else {
            New-CheckResult -Category $category -Check 'Warranty and support' -Status Info `
                -Value 'No support page known for this manufacturer (a self-built computer has a warranty per component)'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Warranty and support' -ErrorRecord $_
    }
}
