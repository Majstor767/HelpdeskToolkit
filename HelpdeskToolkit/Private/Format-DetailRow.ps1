function Format-DetailRow {
    <#
    .SYNOPSIS
        Builds one line of a detail page: a name and its value.
    .DESCRIPTION
        The detail pages of the Live monitor (processor, memory, graphics card) are
        lists of such lines. A value that is missing or empty yields no line, so the
        functions that collect the details can list everything they know to ask for
        and only what the computer really reports is shown.

        With -Unit the unit is added to the value ("3600" becomes "3600 MHz").
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Position = 1)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Value,

        [string]$Unit = ''
    )

    $text = ([string]$Value).Trim()
    if (-not $text) {
        return
    }
    if ($Unit) {
        $text = '{0} {1}' -f $text, $Unit
    }

    [PSCustomObject]@{ Name = $Name; Text = $text }
}
