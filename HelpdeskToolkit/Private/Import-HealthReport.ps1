function Import-HealthReport {
    <#
    .SYNOPSIS
        Reads a report that was saved as JSON.
    .DESCRIPTION
        Reads the file as UTF-8, which is how Export-HealthReportJson writes it, and
        restores the report object (see ConvertTo-HealthReport). Throws when the file
        does not exist or does not contain a report.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.HealthReport')]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "The report file was not found: $Path"
    }

    $data = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $data -or -not $data.PSObject.Properties['Results']) {
        throw "The file is not a HelpdeskToolkit report: $Path"
    }

    ConvertTo-HealthReport -InputObject $data
}
