function Export-HealthReportCsv {
    <#
    .SYNOPSIS
        Saves the results of a health report as a CSV file and returns the file path.
    .DESCRIPTION
        One line per check, with the columns Category, Check, Status, Value, Details,
        Allowed, Typical, Recommendation and Description. The items of a long list
        (Details) are joined into one cell.

        The file is meant to be opened in a spreadsheet program, which decides two things:

        - It is written as UTF-8 with a byte order mark, because Excel otherwise guesses
          the encoding wrong and shows special characters as garbage.
        - The separator is the one of the regional settings of this computer (a comma
          in English, a semicolon in most of Europe), because that is what Excel on
          this computer expects. -Delimiter overrides it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        # Full path of the file to create.
        [Parameter(Mandatory)]
        [string]$Path,

        [char]$Delimiter = [char][cultureinfo]::CurrentCulture.TextInfo.ListSeparator
    )

    $rows = @(
        foreach ($result in @($Report.Results)) {
            [PSCustomObject][ordered]@{
                Category       = $result.Category
                Check          = $result.Check
                Status         = $result.Status
                Value          = $result.Value
                Details        = @($result.Details) -join '; '
                Allowed        = $result.Allowed
                Typical        = $result.Typical
                Recommendation = $result.Recommendation
                Description    = $result.Description
            }
        }
    )

    $lines = @($rows | ConvertTo-Csv -NoTypeInformation -Delimiter $Delimiter)
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true
    [System.IO.File]::WriteAllLines($Path, [string[]]$lines, $encoding)

    $Path
}
