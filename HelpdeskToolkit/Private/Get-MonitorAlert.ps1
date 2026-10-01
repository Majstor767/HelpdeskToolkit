function Get-MonitorAlert {
    <#
    .SYNOPSIS
        Returns warnings about values of the Live monitor that have stayed high for a while.
    .DESCRIPTION
        A single high value means little: a processor at 100 % for a second is normal.
        A warning is therefore only given when every one of the last measurements was
        above the limit (ten of them by default, which is about 20 seconds at the
        fastest refresh rate):

        - processor load, with the program that uses the most processor time
        - memory in use, with the program that uses the most memory
        - disk activity, with the program that reads and writes the most data

        The temperature of the graphics card is judged at once, as it does not jump.

        The limits are in the Monitor section of Config\Thresholds.psd1. Returns the
        warnings as texts in the language of the window; nothing when all is well.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The histories kept by the window: tables of percentages, oldest first.
        [Parameter(Mandatory)]
        [hashtable]$History,

        # The newest snapshot, as returned by Get-PerformanceSnapshot.
        [Parameter(Mandatory)]
        [PSCustomObject]$Snapshot
    )

    $limits = (Get-HealthThreshold).Monitor
    $samples = [int]$limits.AlertSamples

    # True when the history has enough values and each of the last ones is above the limit.
    $stayedAbove = {
        param($Values, $Limit)
        $recent = @($Values | Select-Object -Last $samples)
        $recent.Count -ge $samples -and @($recent | Where-Object { $_ -lt $Limit }).Count -eq 0
    }

    $first = { param($List) @($List | Where-Object { $_ }) | Select-Object -First 1 }

    if (& $stayedAbove $History.Cpu $limits.CpuAlertPercent) {
        $text = (Get-LocalizedText 'The processor has been above {0} % for the last {1} measurements.') -f $limits.CpuAlertPercent, $samples
        $program = & $first $Snapshot.Processes
        if ($program) {
            $text = '{0} {1}' -f $text, ((Get-LocalizedText 'Busiest program: {0} ({1} %).') -f $program.Name, $program.Percent)
        }
        $text
    }

    if (& $stayedAbove $History.Memory $limits.MemoryAlertPercent) {
        $text = (Get-LocalizedText 'The memory has been more than {0} % full for the last {1} measurements.') -f $limits.MemoryAlertPercent, $samples
        $program = & $first $Snapshot.MemoryProcesses
        if ($program) {
            $text = '{0} {1}' -f $text, ((Get-LocalizedText 'Program using the most memory: {0} ({1}).') -f $program.Name, (Format-Gigabyte -Bytes $program.MemoryBytes))
        }
        $text
    }

    if (& $stayedAbove $History.Disk $limits.DiskAlertPercent) {
        $text = (Get-LocalizedText 'A disk has been busy above {0} % for the last {1} measurements.') -f $limits.DiskAlertPercent, $samples
        $program = & $first $Snapshot.IoProcesses
        if ($program) {
            $text = '{0} {1}' -f $text, ((Get-LocalizedText 'Program reading and writing the most: {0} ({1}).') -f $program.Name, (Format-DataRate -BytesPerSecond $program.IoBytesPerSecond))
        }
        $text
    }

    foreach ($sensor in @($Snapshot.GpuSensors | Where-Object { $_ })) {
        if ($null -ne $sensor.TemperatureC -and $sensor.TemperatureC -ge $limits.GpuTemperatureAlert) {
            (Get-LocalizedText 'The graphics card {0} is at {1} {2}C. Check that its fans turn and that the air can flow through the case.') -f
                $sensor.Name, $sensor.TemperatureC, [char]176
        }
    }
}
