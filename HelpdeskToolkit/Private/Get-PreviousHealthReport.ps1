function Get-PreviousHealthReport {
    <#
    .SYNOPSIS
        Returns the report of the check that was made before the given one.
    .DESCRIPTION
        Looks into the History folder (see Save-HealthReportHistory) for the newest
        report of the same computer that is older than the given report, and loads it.

        Returns nothing when this is the first check of the computer or when the
        stored report cannot be read.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.HealthReport')]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report
    )

    $folder = Get-AppDataPath -ChildPath 'History'
    if (-not (Test-Path -LiteralPath $folder)) {
        return
    }

    # File names carry the time of the check and therefore sort by time.
    $current = '{0}.json' -f (Get-ReportFileName -Report $Report)
    $pattern = 'PCHealth_{0}_*.json' -f $Report.ComputerName
    $previous = Get-ChildItem -LiteralPath $folder -Filter $pattern -File |
        Where-Object { [string]::CompareOrdinal($_.Name, $current) -lt 0 } |
        Sort-Object -Property Name -Descending |
        Select-Object -First 1

    if ($previous) {
        try {
            Import-HealthReport -Path $previous.FullName
        }
        catch {
            Write-Verbose "The previous report cannot be read: $($_.Exception.Message)"
        }
    }
}
