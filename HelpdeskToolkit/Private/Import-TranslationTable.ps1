function Import-TranslationTable {
    <#
    .SYNOPSIS
        Reads the translations of one language from Lang\<language>.psd1.
    .DESCRIPTION
        The file is a PowerShell data file with tables from the English text to its
        translation, and Patterns, a list of regular expressions with their
        replacement, for pieces of a text (see Get-LocalizedText). The translations
        are spread over several tables only because a data file may hold at most 500
        entries per table; here they are put together into one.

        Unlike the other source files it contains letters outside the English
        alphabet. It is therefore read as UTF-8 here, explicitly, and not left to
        PowerShell, which would guess another encoding in Windows PowerShell 5.1 when
        the byte order mark is missing.

        From the Text table two helpers are prepared once, because building them for
        every lookup would be slow:

        - Templates: for every text with placeholders ({0}, {1}) a regular expression
          that recognizes the text after the placeholders were filled in. Texts with
          hardly any words of their own ("{0} of {1}") are left out: they would match
          almost anything.
        - Sentences: the texts that end like a sentence, longest first, to take apart
          a recommendation that consists of several of them.

        Returns a table with Language, Text, Exact (the texts with their capital
        letters as written), Templates, Sentences, Patterns and an empty Cache. An unknown language or an unreadable file gives empty parts, so
        the window falls back to English.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Language
    )

    # Exact holds the texts as they are written, capital letters included: the table
    # Text finds "OK" and "Ok" alike, and Get-LocalizedText has to tell them apart.
    $table = @{
        Language  = $Language
        Text      = @{}
        Exact     = New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::Ordinal)
        Templates = @()
        Sentences = @()
        Patterns  = @()
        Cache     = @{}
    }

    $path = Join-Path -Path $script:ModuleRoot -ChildPath ('Lang\{0}.psd1' -f $Language)
    if (-not (Test-Path -LiteralPath $path)) {
        return $table
    }

    try {
        $data = ConvertFrom-DataFileText -Text ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
    }
    catch {
        Write-Verbose "The translation file $path cannot be read: $($_.Exception.Message)"
        return $table
    }

    foreach ($name in $data.Keys) {
        if ($name -eq 'Patterns') {
            $table.Patterns = @($data.Patterns)
        }
        elseif ($data[$name] -is [hashtable]) {
            foreach ($key in $data[$name].Keys) {
                $table.Text[[string]$key] = [string]$data[$name][$key]
                [void]$table.Exact.Add([string]$key)
            }
        }
    }

    $placeholder = '\{(\d+)(:[^}]*)?\}'
    $templates = foreach ($key in $table.Text.Keys) {
        if ($key -notmatch $placeholder) {
            continue
        }
        # Only texts with at least three words of their own are recognizable.
        $literal = [regex]::Replace($key, $placeholder, ' ')
        if (@($literal -split '\s+' | Where-Object { $_ -match '[A-Za-z]{2}' }).Count -lt 3) {
            continue
        }

        # The literal parts are taken as they are; every placeholder becomes a named group.
        $pattern = [regex]::Escape($key)
        $pattern = [regex]::Replace($pattern, '\\\{(\d+)(:[^}]*)?}', '(?<p$1>.*?)')
        [PSCustomObject]@{
            Regex       = New-Object -TypeName System.Text.RegularExpressions.Regex -ArgumentList ('^{0}$' -f $pattern), ([System.Text.RegularExpressions.RegexOptions]::Singleline)
            Translation = [string]$table.Text[$key]
            Length      = $literal.Length
        }
    }
    # The text with the most words of its own first: it is the most specific one.
    $table.Templates = @($templates | Sort-Object -Property Length -Descending)

    $table.Sentences = @($table.Text.Keys | Where-Object { $_ -notmatch $placeholder -and $_ -match '[.!?]$' -and $_.Length -gt 20 } |
            Sort-Object -Property Length -Descending)

    $table
}
