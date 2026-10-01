function Save-HealthReportHistory {
    <#
    .SYNOPSIS
        Keeps a copy of a report, so the next check can be compared with it.
    .DESCRIPTION
        The window answers "what changed since the last check?". For that it stores
        every finished report as JSON in the History folder of the application folder
        (see Get-AppDataPath), named after the computer and the time of the check.

        Only the newest reports of a computer are kept (30 by default); older ones are
        removed, so the folder cannot grow without limit. These are files the
        application created itself.

        Returns the path of the stored file, or nothing when it could not be written;
        a missing history is not worth an error message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        # How many reports per computer are kept.
        [ValidateRange(1, 1000)]
        [int]$Keep = 30
    )

    try {
        $folder = Get-AppDataPath -ChildPath 'History'
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }

        $path = Join-Path -Path $folder -ChildPath ('{0}.json' -f (Get-ReportFileName -Report $Report))
        [void](Export-HealthReportJson -Report $Report -Path $path)

        # The time in the name sorts like the time itself, so the oldest come first.
        $pattern = 'PCHealth_{0}_*.json' -f $Report.ComputerName
        $files = @(Get-ChildItem -LiteralPath $folder -Filter $pattern -File | Sort-Object -Property Name)
        if ($files.Count -gt $Keep) {
            $files | Select-Object -First ($files.Count - $Keep) | Remove-Item -Force -Confirm:$false
        }

        $path
    }
    catch {
        Write-Verbose "The report could not be added to the history: $($_.Exception.Message)"
    }
}
