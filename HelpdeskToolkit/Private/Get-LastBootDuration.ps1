function Get-LastBootDuration {
    <#
    .SYNOPSIS
        Returns how long the last measured startup of Windows took; nothing when unknown.
    .DESCRIPTION
        Windows records the duration of a startup as event 100 in the log
        "Microsoft-Windows-Diagnostics-Performance/Operational", which only
        administrators can read. BootTime in that event is the time in milliseconds from
        the start of Windows until the desktop was usable.

        Windows does not measure every startup, so the newest event can be old; the
        time of the measurement is returned with it.

        Returns an object with Seconds and MeasuredAt.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $filter = @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 }
        $entry = Get-WinEvent -FilterHashtable $filter -MaxEvents 1 -ErrorAction Stop
    }
    catch {
        Write-Verbose "No startup measurement found: $($_.Exception.Message)"
        return
    }

    # The values of an event are named in its XML form: <Data Name="BootTime">102766</Data>
    $xml = [xml]$entry.ToXml()
    $bootTime = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' } | Select-Object -First 1
    if (-not $bootTime) {
        return
    }

    [PSCustomObject]@{
        Seconds    = [int][math]::Round([double]$bootTime.'#text' / 1000)
        MeasuredAt = $entry.TimeCreated
    }
}
