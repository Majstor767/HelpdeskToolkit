function Format-DetailSection {
    <#
    .SYNOPSIS
        Builds one section of a detail page: a title and its lines.
    .DESCRIPTION
        A section without lines yields nothing, so a part of the computer that does
        not exist (a second graphics card, a page file) leaves no empty box behind.

        -Raw marks a section that lists what Windows reports exactly as it reports it
        (see ConvertTo-DetailRow). Its title is the name of the source, and its lines
        are not translated.

        -KeepNames marks a section whose lines are named after things of the computer
        (a program, a display) and not after a label; those names are not translated.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Row,

        [switch]$Raw,

        [switch]$KeepNames
    )

    $rows = @($Row | Where-Object { $_ })
    if ($rows.Count -eq 0) {
        return
    }

    [PSCustomObject]@{ Title = $Title; Raw = [bool]$Raw; KeepNames = [bool]$KeepNames; Rows = $rows }
}
