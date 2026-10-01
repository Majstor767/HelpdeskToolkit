function Get-HardwareHealth {
    <#
    .SYNOPSIS
        Checks CPU load, memory usage, free disk space and the battery.
    .DESCRIPTION
        Reads everything through CIM (WMI), which needs no administrator rights and
        changes nothing on the system:

        - CPU load at the time of the check
        - used physical memory and the five programs that use the most of it
        - health reported by every physical drive (SSD/HDD)
        - devices without a working driver
        - free space on every local fixed disk
        - battery charge, when the computer has a battery

        The limits for Warning and Critical come from Config\Thresholds.psd1.
    .EXAMPLE
        Get-HardwareHealth

        Returns one result per check, including one per local disk.
    .EXAMPLE
        Get-HardwareHealth | Where-Object Check -like 'Disk*'

        Shows only the disk space results.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'Hardware'
    $thresholds = Get-HealthThreshold

    # CPU. Win32_Processor is used instead of performance counters because counter
    # names are translated on non-English Windows and would break the query.
    try {
        $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        $loads = @($processors | Where-Object { $null -ne $_.LoadPercentage } | ForEach-Object { $_.LoadPercentage })

        if ($loads.Count -eq 0) {
            New-CheckResult -Category $category -Check 'CPU load' -Status Info -Value 'Unavailable'
        }
        else {
            $load = [int][math]::Round(($loads | Measure-Object -Average).Average)
            $status = Get-ThresholdStatus -Value $load -Warning $thresholds.Cpu.WarningPercent -Critical $thresholds.Cpu.CriticalPercent
            $recommendation = if ($status -ne 'OK') {
                'CPU load was high at the time of the check. Open Task Manager (Ctrl+Shift+Esc) and look for the process using the most CPU.'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'CPU load' -Status $status `
                -Value ('{0} % ({1})' -f $load, ([string]$processors[0].Name).Trim()) -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Cpu.WarningPercent -Critical $thresholds.Cpu.CriticalPercent -Unit '%') `
                -Typical $thresholds.Cpu.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'CPU load' -ErrorRecord $_
    }

    # Memory. Both values are reported by WMI in kilobytes.
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        $usedBytes = $totalBytes - ([double]$os.FreePhysicalMemory * 1KB)
        $usedPercent = [int][math]::Round($usedBytes / $totalBytes * 100)

        $status = Get-ThresholdStatus -Value $usedPercent -Warning $thresholds.Memory.WarningPercent -Critical $thresholds.Memory.CriticalPercent
        $recommendation = if ($status -ne 'OK') {
            'Memory is almost full. Close unused applications and browser tabs; if this happens regularly, the computer needs more RAM.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Memory usage' -Status $status `
            -Value ('{0} % ({1} of {2} used)' -f $usedPercent, (Format-Gigabyte -Bytes $usedBytes), (Format-Gigabyte -Bytes $totalBytes)) `
            -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $thresholds.Memory.WarningPercent -Critical $thresholds.Memory.CriticalPercent -Unit '%') `
            -Typical $thresholds.Memory.Typical
    }
    catch {
        New-FailureResult -Category $category -Check 'Memory usage' -ErrorRecord $_
    }

    # Which programs hold the memory. Processes are grouped by name because browsers
    # and similar applications run as many processes.
    try {
        $consumers = @(
            Get-Process -ErrorAction Stop |
                Group-Object -Property ProcessName |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name  = $_.Name
                        Bytes = ($_.Group | Measure-Object -Property WorkingSet64 -Sum).Sum
                    }
                } |
                Sort-Object -Property Bytes -Descending |
                Select-Object -First 5 |
                ForEach-Object { '{0} ({1})' -f $_.Name, (Format-Gigabyte -Bytes $_.Bytes) }
        )
        New-CheckResult -Category $category -Check 'Top memory consumers' -Status Info -Value ($consumers -join ', ')
    }
    catch {
        New-FailureResult -Category $category -Check 'Top memory consumers' -ErrorRecord $_
    }

    # Physical drives and the health state they report themselves (based on SMART).
    try {
        $mediaTypes = @{ 3 = 'HDD'; 4 = 'SSD' }
        $busTypes = @{ 7 = 'USB'; 11 = 'SATA'; 17 = 'NVMe' }
        $drives = @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop)

        foreach ($drive in $drives) {
            $media = $mediaTypes[[int]$drive.MediaType]
            $bus = $busTypes[[int]$drive.BusType]
            $kind = (@($media, $bus) | Where-Object { $_ }) -join ', '
            if (-not $kind) {
                $kind = 'Unknown type'
            }

            switch ([int]$drive.HealthStatus) {
                0 { $status = 'OK'; $health = 'Healthy' }
                1 { $status = 'Warning'; $health = 'Warning' }
                2 { $status = 'Critical'; $health = 'Unhealthy' }
                default { $status = 'Info'; $health = 'Unknown' }
            }
            $recommendation = if ($status -in 'Warning', 'Critical') {
                'The drive reports a problem and may fail. Back up the data now and plan to replace the drive.'
            }
            else {
                ''
            }

            New-CheckResult -Category $category -Check ('Drive: {0}' -f $drive.FriendlyName) -Status $status `
                -Value ('{0}, {1}, health: {2}' -f $kind, (Format-Gigabyte -Bytes $drive.Size), $health) `
                -Recommendation $recommendation
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Drive health' -ErrorRecord $_
    }

    # Disks. DriveType 3 = local fixed disk (no USB sticks, network or optical drives).
    try {
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop)
        foreach ($disk in $disks) {
            $check = 'Disk ({0})' -f $disk.DeviceID
            if (-not $disk.Size) {
                New-CheckResult -Category $category -Check $check -Status Info -Value 'Size unknown'
                continue
            }

            $freePercent = [math]::Round([double]$disk.FreeSpace / [double]$disk.Size * 100, 1)
            $status = Get-ThresholdStatus -Value $freePercent -LowerIsWorse `
                -Warning $thresholds.Disk.WarningFreePercent -Critical $thresholds.Disk.CriticalFreePercent
            $recommendation = switch ($status) {
                'Critical' { 'The disk is almost full. Free up space now: Windows updates and applications can fail without free space.' }
                'Warning' { 'Free space is low. Run Disk Cleanup, empty the Recycle Bin and remove programs and files that are no longer needed.' }
                default { '' }
            }
            New-CheckResult -Category $category -Check $check -Status $status `
                -Value ('{0} % free ({1} of {2})' -f [string]$freePercent, (Format-Gigabyte -Bytes $disk.FreeSpace), (Format-Gigabyte -Bytes $disk.Size)) `
                -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Disk.WarningFreePercent -Critical $thresholds.Disk.CriticalFreePercent -Unit '% free' -LowerIsWorse) `
                -Typical $thresholds.Disk.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Disk space' -ErrorRecord $_
    }

    # Devices that Device Manager marks with a yellow warning sign. Error code 0 means
    # the device works; code 22 means it was disabled on purpose, which is not a fault.
    try {
        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 22' -ErrorAction Stop)
        if ($devices.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Devices with problems' -Status OK -Value 'None'
        }
        else {
            $names = @($devices | ForEach-Object {
                    $name = if ($_.Name) { $_.Name } else { 'Unknown device' }
                    '{0} (code {1})' -f $name, $_.ConfigManagerErrorCode
                })
            $shown = 5
            $remaining = @($names | Select-Object -Skip $shown)
            $value = '{0} devices: {1}' -f $devices.Count, (($names | Select-Object -First $shown) -join ', ')
            if ($remaining.Count -gt 0) {
                $value = '{0} and {1} more' -f $value, $remaining.Count
            }
            New-CheckResult -Category $category -Check 'Devices with problems' -Status Warning -Value $value -Details $remaining `
                -Recommendation 'These devices have no working driver. Open Device Manager (devmgmt.msc), find the devices with a yellow mark and install the driver from Windows Update or from the web site of the manufacturer.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Devices with problems' -ErrorRecord $_
    }

    # Battery. Desktops simply have no Win32_Battery instance.
    try {
        $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
        if ($batteries.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Battery' -Status Info -Value 'No battery (desktop computer)'
        }

        foreach ($battery in $batteries) {
            $charge = [int]$battery.EstimatedChargeRemaining
            # BatteryStatus 1, 4 and 5 mean the computer is running on battery power.
            $onBattery = $battery.BatteryStatus -in 1, 4, 5

            if ($onBattery) {
                $status = Get-ThresholdStatus -Value $charge -LowerIsWorse `
                    -Warning $thresholds.Battery.WarningPercent -Critical $thresholds.Battery.CriticalPercent
                $power = 'on battery'
            }
            else {
                $status = 'OK'
                $power = 'plugged in'
            }

            $recommendation = if ($status -ne 'OK') { 'Battery charge is low. Connect the charger.' } else { '' }
            New-CheckResult -Category $category -Check 'Battery' -Status $status `
                -Value ('{0} % ({1})' -f $charge, $power) -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Battery.WarningPercent -Critical $thresholds.Battery.CriticalPercent -Unit '%' -LowerIsWorse)
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Battery' -ErrorRecord $_
    }
}
