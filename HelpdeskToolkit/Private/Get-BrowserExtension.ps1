function Get-BrowserExtension {
    <#
    .SYNOPSIS
        Returns the extensions installed in the browsers of the current user.
    .DESCRIPTION
        Chrome, Edge, Brave and Opera keep every extension in a folder of the browser
        profile, with a file "manifest.json" that holds its name and version. A name
        written as "__MSG_key__" is a reference into the language files of the
        extension and is looked up there.

        Only those files are read; the browser is not started and nothing is changed.
        Returns one object per browser and extension with Browser, Name and Version.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Folder that contains the browser profiles
    $browsers = [ordered]@{
        'Chrome'   = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Google\Chrome\User Data'
        'Edge'     = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Edge\User Data'
        'Brave'    = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'BraveSoftware\Brave-Browser\User Data'
        'Opera'    = Join-Path -Path $env:APPDATA -ChildPath 'Opera Software\Opera Stable'
        'Opera GX' = Join-Path -Path $env:APPDATA -ChildPath 'Opera Software\Opera GX Stable'
    }

    foreach ($browser in $browsers.Keys) {
        $root = $browsers[$browser]
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        # The profiles are the subfolders that have an "Extensions" folder; Opera keeps
        # the default profile directly in the root.
        $profileFolders = @($root) + @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        $seen = @{}

        foreach ($profileFolder in $profileFolders) {
            $extensionRoot = Join-Path -Path $profileFolder -ChildPath 'Extensions'
            if (-not (Test-Path -LiteralPath $extensionRoot)) {
                continue
            }

            foreach ($extension in Get-ChildItem -LiteralPath $extensionRoot -Directory -ErrorAction SilentlyContinue) {
                # One subfolder per installed version; the newest one is in use.
                $versionFolder = Get-ChildItem -LiteralPath $extension.FullName -Directory -ErrorAction SilentlyContinue |
                    Sort-Object -Property Name -Descending | Select-Object -First 1
                if (-not $versionFolder) {
                    continue
                }

                try {
                    $manifestPath = Join-Path -Path $versionFolder.FullName -ChildPath 'manifest.json'
                    $manifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

                    # A manifest need not have every field; a missing one reads as empty.
                    $field = { param($Name) $property = $manifest.PSObject.Properties[$Name]; if ($property) { [string]$property.Value } else { '' } }
                    $name = & $field 'name'

                    if ($name -match '^__MSG_(.+)__$') {
                        $name = Resolve-ExtensionMessage -Folder $versionFolder.FullName -Key $Matches[1] -DefaultLocale (& $field 'default_locale')
                    }
                    if (-not $name) {
                        $name = $extension.Name
                    }

                    # The same extension in several profiles of one browser is listed once.
                    if (-not $seen.ContainsKey($name)) {
                        $seen[$name] = $true
                        [PSCustomObject]@{
                            Browser = $browser
                            Name    = $name
                            Version = & $field 'version'
                        }
                    }
                }
                catch {
                    Write-Verbose "Unreadable extension $($extension.FullName): $($_.Exception.Message)"
                }
            }
        }
    }
}
