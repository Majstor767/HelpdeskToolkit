function ConvertFrom-DataFileText {
    <#
    .SYNOPSIS
        Turns the text of a PowerShell data file (.psd1) into the table it describes.
    .DESCRIPTION
        Does what Import-PowerShellDataFile does, but from text instead of a file. It
        is needed where the configuration arrives as text because the files are not
        there: on another computer, see Get-RemoteHealthReport.

        The text is parsed, not executed: only plain data (texts, numbers, lists and
        tables) is accepted, and anything else makes the function throw.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "The configuration text cannot be read: $($errors[0].Message)"
    }

    $table = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)
    if (-not $table) {
        throw 'The configuration text does not contain a table.'
    }

    $table.SafeGetValue()
}
