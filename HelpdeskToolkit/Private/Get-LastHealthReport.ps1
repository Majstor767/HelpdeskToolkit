function Get-LastHealthReport {
    <#
    .SYNOPSIS
        Returns the newest report of this computer that the application has kept.
    .DESCRIPTION
        Looks into the History folder (see Save-HealthReportHistory) for the newest
        report of the given computer and loads it. The window shows it the moment it
        opens, so there is something to read while the new check is still running.

        Returns nothing when there is no report yet or when the stored one cannot be read.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.HealthReport')]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )

    $folder = Get-AppDataPath -ChildPath 'History'
    if (-not (Test-Path -LiteralPath $folder)) {
        return
    }

    # File names carry the time of the check and therefore sort by time.
    $newest = Get-ChildItem -LiteralPath $folder -Filter ('PCHealth_{0}_*.json' -f $ComputerName) -File |
        Sort-Object -Property Name -Descending |
        Select-Object -First 1

    if ($newest) {
        try {
            Import-HealthReport -Path $newest.FullName
        }
        catch {
            Write-Verbose "The last report cannot be read: $($_.Exception.Message)"
        }
    }
}
