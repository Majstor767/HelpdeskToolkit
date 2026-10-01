function Import-TranslationTable {
    <#
    .SYNOPSIS
        Reads the translations of one language from Lang\<language>.psd1.
    .DESCRIPTION
        The file is a PowerShell data file with two parts: Text, a table from the
        English text to its translation, and Patterns, a list of regular expressions
        with their replacement (see Get-LocalizedText).

        Unlike the other source files it contains letters outside the English
        alphabet. It is therefore read as UTF-8 here, explicitly, and not left to
        PowerShell, which would guess another encoding in Windows PowerShell 5.1 when
        the byte order mark is missing.

        Returns a table with Language, Text and Patterns. An unknown language or an
        unreadable file gives an empty table, so the window falls back to English.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Language
    )

    $table = @{ Language = $Language; Text = @{}; Patterns = @() }

    $path = Join-Path -Path $script:ModuleRoot -ChildPath ('Lang\{0}.psd1' -f $Language)
    if (-not (Test-Path -LiteralPath $path)) {
        return $table
    }

    try {
        $data = ConvertFrom-DataFileText -Text ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        if ($data.ContainsKey('Text')) {
            # A table that tells upper and lower case apart: "OK" and "Ok" are different texts.
            $text = New-Object -TypeName 'System.Collections.Generic.Dictionary[string,string]' -ArgumentList ([System.StringComparer]::Ordinal)
            foreach ($key in $data.Text.Keys) {
                $text[[string]$key] = [string]$data.Text[$key]
            }
            $table.Text = $text
        }
        if ($data.ContainsKey('Patterns')) {
            $table.Patterns = @($data.Patterns)
        }
    }
    catch {
        Write-Verbose "The translation file $path cannot be read: $($_.Exception.Message)"
    }

    $table
}
