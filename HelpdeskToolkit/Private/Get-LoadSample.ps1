function Get-LoadSample {
    <#
    .SYNOPSIS
        Measures processor load, memory and the running programs at one moment, for later use.
    .DESCRIPTION
        When the check categories run side by side (see Get-PCHealthReport), the check
        itself keeps several processor cores busy and takes memory for its runspaces.
        Measured during that time, "CPU load" and "Memory usage" would describe the
        check, not the computer. So these three things are read first, while nothing
        else runs, and handed to Get-HardwareHealth:

        Processors       the Win32_Processor instances, with LoadPercentage
        OperatingSystem  the Win32_OperatingSystem instance, with the memory figures
        Processes        the running processes, for "Top memory consumers"

        A part that cannot be read is left empty; Get-HardwareHealth then reads it
        itself and reports the failure the usual way.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $read = {
        param([scriptblock]$Source)
        try {
            , @(& $Source)
        }
        catch {
            Write-Verbose "A part of the load sample could not be read: $($_.Exception.Message)"
            , @()
        }
    }

    $processors = & $read { Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop }
    $system = & $read { Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop }
    $processes = & $read { Get-Process -ErrorAction Stop }

    [PSCustomObject]@{
        TakenAt         = Get-Date
        Processors      = $processors
        OperatingSystem = $system | Select-Object -First 1
        Processes       = $processes
    }
}
