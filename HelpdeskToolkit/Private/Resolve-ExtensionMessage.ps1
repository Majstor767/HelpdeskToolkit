function Resolve-ExtensionMessage {
    <#
    .SYNOPSIS
        Looks up a text of a browser extension in its language files.
    .DESCRIPTION
        An extension that supports several languages writes its name as "__MSG_key__"
        and keeps the real text in _locales\<language>\messages.json. The English text
        is preferred, then the default language of the extension. The key is compared
        without regard to upper and lower case, as the browsers do.

        Returns the text, or nothing when it cannot be found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Folder of the extension version, the one that contains manifest.json.
        [Parameter(Mandatory)]
        [string]$Folder,

        [Parameter(Mandatory)]
        [string]$Key,

        [string]$DefaultLocale = ''
    )

    foreach ($locale in @('en', 'en_US', 'en_GB', $DefaultLocale) | Where-Object { $_ } | Select-Object -Unique) {
        $path = Join-Path -Path $Folder -ChildPath ('_locales\{0}\messages.json' -f $locale)
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        try {
            $messages = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $entry = $messages.PSObject.Properties | Where-Object { $_.Name -eq $Key } | Select-Object -First 1
            if ($entry -and $entry.Value.message) {
                return [string]$entry.Value.message
            }
        }
        catch {
            Write-Verbose "Unreadable language file ${path}: $($_.Exception.Message)"
        }
    }
}
