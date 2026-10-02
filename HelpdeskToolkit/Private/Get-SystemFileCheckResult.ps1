function Get-SystemFileCheckResult {
    <#
    .SYNOPSIS
        Returns the outcome of the last "sfc /scannow" that is still on record; nothing when there is none.
    .DESCRIPTION
        The System File Checker compares the files of Windows with their originals
        and repairs damaged ones. It has no result that could be queried; what it did
        is written into the servicing log (%windir%\Logs\CBS\CBS.log) in lines marked
        "[SR]". Those lines are read here, the check itself is never started.

        The lines of the last day on which the checker ran are judged:

        Unrepaired  a damaged file could not be repaired ("Cannot repair member file")
        Repaired    damaged files were found and repaired
        Clean       nothing was damaged

        Windows replaces the log when it grows large, so an older check may no longer
        be on record. Returns an object with CheckedAt and Verdict.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $path = Join-Path -Path $env:windir -ChildPath 'Logs\CBS\CBS.log'
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $lines = @(Select-String -LiteralPath $path -SimpleMatch '[SR]' -ErrorAction Stop | ForEach-Object { $_.Line })
    if ($lines.Count -eq 0) {
        return
    }

    # Every line starts with its time: "2026-01-15 10:30:12, Info  CSI  0000012a [SR] ..."
    $stamp = '^(?<day>\d{4}-\d{2}-\d{2}) (?<time>\d{2}:\d{2}:\d{2})'
    if ($lines[-1] -notmatch $stamp) {
        return
    }
    $day = $Matches.day
    $checkedAt = [datetime]::ParseExact(('{0} {1}' -f $day, $Matches.time), 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
    $session = @($lines | Where-Object { $_.StartsWith($day) })

    $verdict = if (@($session | Where-Object { $_ -match 'Cannot repair member file' }).Count -gt 0) {
        'Unrepaired'
    }
    elseif (@($session | Where-Object { $_ -match 'Repairing corrupted file|Repaired file|Repairing [1-9]\d* components' }).Count -gt 0) {
        'Repaired'
    }
    else {
        'Clean'
    }

    [PSCustomObject]@{
        CheckedAt = $checkedAt
        Verdict   = $verdict
    }
}
