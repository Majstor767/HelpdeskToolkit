function Get-HealthScoreHistory {
    <#
    .SYNOPSIS
        Returns the health scores of the earlier checks of a computer, oldest first.
    .DESCRIPTION
        The application keeps the reports of the last checks as JSON files in its
        History folder (see Save-HealthReportHistory). The Overview draws their scores
        as a line, which shows at a glance whether the computer is getting better or
        worse.

        A report is a hundred kilobytes and more, and only two values of it are
        needed. The time and the score stand in the first lines of every file, so only
        the beginning of each file is read instead of loading thirty whole reports.

        Returns objects with Time and Score. A file that cannot be read, or that does
        not start like a report, is left out.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        # How many of the newest reports are returned at most.
        [ValidateRange(2, 1000)]
        [int]$Maximum = 30
    )

    $folder = Get-AppDataPath -ChildPath 'History'
    if (-not (Test-Path -LiteralPath $folder)) {
        return
    }

    # The time in the name sorts like the time itself.
    $files = @(Get-ChildItem -LiteralPath $folder -Filter ('PCHealth_{0}_*.json' -f $ComputerName) -File |
            Sort-Object -Property Name | Select-Object -Last $Maximum)

    foreach ($file in $files) {
        try {
            $buffer = New-Object -TypeName byte[] -ArgumentList 1024
            $stream = [System.IO.File]::OpenRead($file.FullName)
            try {
                $read = $stream.Read($buffer, 0, $buffer.Length)
            }
            finally {
                $stream.Dispose()
            }
            $head = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)

            $time = [regex]::Match($head, '"GeneratedAt":\s*"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)"')
            $score = [regex]::Match($head, '"Score":\s*(\d{1,3})\b')
            if ($time.Success -and $score.Success) {
                [PSCustomObject]@{
                    Time  = [datetime]::ParseExact($time.Groups[1].Value, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
                    Score = [int]$score.Groups[1].Value
                }
            }
        }
        catch {
            Write-Verbose "The report '$($file.Name)' was left out of the history of the score: $($_.Exception.Message)"
        }
    }
}
