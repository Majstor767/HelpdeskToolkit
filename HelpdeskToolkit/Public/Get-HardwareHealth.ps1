function Get-HardwareHealth {
    <#
    .SYNOPSIS
        Checks CPU load, memory usage, free disk space and the battery.
    .DESCRIPTION
        Reads everything through CIM (WMI), which needs no administrator rights and
        changes nothing on the system:

        - CPU load at the time of the check
        - used physical memory
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
        Objects with the properties Category, Check, Status, Value and Recommendation.
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
                -Value ('{0} % ({1})' -f $load, ([string]$processors[0].Name).Trim()) -Recommendation $recommendation
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
            -Recommendation $recommendation
    }
    catch {
        New-FailureResult -Category $category -Check 'Memory usage' -ErrorRecord $_
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
                -Recommendation $recommendation
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Disk space' -ErrorRecord $_
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
                -Value ('{0} % ({1})' -f $charge, $power) -Recommendation $recommendation
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Battery' -ErrorRecord $_
    }
}
