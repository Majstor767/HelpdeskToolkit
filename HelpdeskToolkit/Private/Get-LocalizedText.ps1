function Get-LocalizedText {
    <#
    .SYNOPSIS
        Returns a text of the window in the language the user chose.
    .DESCRIPTION
        The texts are written in English in the code. For another language, the
        translation is looked up in Lang\<language>.psd1, in two steps:

        1. Text:     the English text as a whole, for example 'Run check'.
        2. Patterns: texts that contain numbers or names, described by a regular
                     expression, for example '^(\d+) in the last (\d+) days$' with the
                     translation '$1 u zadnjih $2 dana'. The first pattern that matches
                     is used.

        A text without a translation is returned unchanged, so a missing entry shows
        English instead of breaking anything. With the language "en" nothing is looked
        up at all.

        The language is kept in $script:Language; the table of a language is read
        once and cached in $script:Translations.
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

    if ($table.Text.ContainsKey($Text)) {
        return [string]$table.Text[$Text]
    }

    foreach ($pattern in $table.Patterns) {
        if ($Text -match $pattern.Match) {
            return [regex]::Replace($Text, $pattern.Match, $pattern.Text)
        }
    }

    $Text
}
