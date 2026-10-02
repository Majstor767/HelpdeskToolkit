function ConvertFrom-WingetTable {
    <#
    .SYNOPSIS
        Turns the table that "winget upgrade" prints into objects.
    .DESCRIPTION
        winget has no machine-readable output for its lists; it prints a table:

        Name          Id                 Version   Available
        -----------------------------------------------------
        Contoso Edit  Contoso.Edit       2.0.19    2.0.28

        The columns are found by position: every column starts where its heading
        starts. That works in every display language of winget, because the headings
        are not looked at by name, only the order counts: name, id, installed version,
        available version.

        The table ends at the first line that does not fit (an empty line, or the
        summary "34 upgrades available."). winget may print a second table, for
        packages that are pinned; it is read the same way.

        Returns one object per row with Name, Id, Version and Available.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $lines = @($Text -split "`r?`n")

    for ($index = 1; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -notmatch '^-{10,}\s*$') {
            continue
        }

        # A progress animation may stand before the headings, ended by a carriage return.
        $header = $lines[$index - 1]
        $header = $header.Substring($header.LastIndexOf("`r") + 1)
        $starts = @([regex]::Matches($header, '\S+') | ForEach-Object { $_.Index })
        if ($starts.Count -lt 4) {
            continue
        }

        for ($row = $index + 1; $row -lt $lines.Count; $row++) {
            $line = $lines[$row]
            if ($line.Length -le $starts[3]) {
                break
            }

            $cells = for ($column = 0; $column -lt 4; $column++) {
                $end = if ($column + 1 -lt $starts.Count) { $starts[$column + 1] } else { $line.Length }
                $line.Substring($starts[$column], [math]::Min($end, $line.Length) - $starts[$column]).Trim()
            }

            # An id has no spaces; anything else is not a row of the table.
            if (-not $cells[1] -or $cells[1] -match '\s' -or -not $cells[3]) {
                break
            }

            [PSCustomObject]@{
                Name      = $cells[0]
                Id        = $cells[1]
                Version   = $cells[2]
                Available = $cells[3]
            }
        }
    }
}
