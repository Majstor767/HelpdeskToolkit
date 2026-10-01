function Get-LocalizedText {
    <#
    .SYNOPSIS
        Returns a text of the window in the language the user chose.
    .DESCRIPTION
        The texts are written in English in the code. For another language, the
        translation is looked up in Lang\<language>.psd1 (see Import-TranslationTable),
        in this order:

        1. The whole text, for example 'Run check'. Upper and lower case do not matter;
           a text written in capitals ("WARNING") gets its translation in capitals.
        2. A text with placeholders, for example 'Restart the computer; it has been
           running for more than {0} days.' The checks have already put the number in,
           so the text is recognized by everything around the placeholders, and the
           number is put into the translation at the same place.
        3. Several known sentences in a row, as some recommendations are.
        4. Small pieces of a text, such as " and 12 more" or " in the last 7 days",
           which are replaced one after the other (the Patterns of the language file).
           This is how values that consist mostly of names and numbers are translated.

        A text without a translation is returned unchanged, so a missing entry shows
        English instead of breaking anything. With the language "en" nothing is looked
        up at all.

        The language is kept in $script:Language; the table of a language is read
        once and cached in $script:Translations, together with every text that had to
        be worked out by steps 2 to 4.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Text
    )

    if (-not $Text -or -not $script:Language -or $script:Language -eq 'en') {
        return $Text
    }

    if (-not $script:Translations -or $script:Translations.Language -ne $script:Language) {
        $script:Translations = Import-TranslationTable -Language $script:Language
    }
    $table = $script:Translations

    # 1. The whole text
    if ($table.Text.ContainsKey($Text)) {
        $translation = [string]$table.Text[$Text]
        if ($Text -cmatch '[A-Z]{2}' -and $Text -ceq $Text.ToUpperInvariant() -and $Text -cne [string]($table.Text.Keys | Where-Object { $_ -eq $Text } | Select-Object -First 1)) {
            return $translation.ToUpper()
        }
        return $translation
    }

    if ($table.Cache.ContainsKey($Text)) {
        return $table.Cache[$Text]
    }

    $result = $null

    # 2. A text with placeholders that were filled in already
    foreach ($template in $table.Templates) {
        $match = $template.Regex.Match($Text)
        if ($match.Success) {
            $result = [regex]::Replace($template.Translation, '\{(\d+)(:[^}]*)?\}', {
                    param($placeholder)
                    # What stood at the placeholder may be a text of its own, such as
                    # a second sentence.
                    Get-LocalizedText $match.Groups['p' + $placeholder.Groups[1].Value].Value
                })
            break
        }
    }

    # 3. Known sentences in a row
    if ($null -eq $result -and $Text.Length -gt 60) {
        $rest = $Text
        $parts = @()
        while ($rest) {
            $sentence = $table.Sentences | Where-Object { $rest.StartsWith($_, [System.StringComparison]::Ordinal) } | Select-Object -First 1
            if (-not $sentence) {
                break
            }
            $parts += [string]$table.Text[$sentence]
            $rest = $rest.Substring($sentence.Length).TrimStart()
        }
        if (-not $rest -and $parts.Count -gt 1) {
            $result = $parts -join ' '
        }
    }

    # 4. Pieces of the text
    if ($null -eq $result) {
        $result = $Text
        foreach ($pattern in $table.Patterns) {
            $result = [regex]::Replace($result, $pattern.Match, $pattern.Text)
        }
    }

    $table.Cache[$Text] = $result
    $result
}
