function Get-InstalledBrowserPath {
    <#
    .SYNOPSIS
        Returns the program files of the web browsers that are installed.
    .DESCRIPTION
        Used when the default browser of Windows cannot be used (see
        Get-DefaultBrowser): something has to open the page all the same.

        Programs tell Windows where they are under "App Paths" in the registry, for
        the user or for everybody. The common browsers are looked up there by the
        name of their program. Microsoft Edge, which is part of Windows, comes first;
        the others follow in no order of preference.

        Returns the paths of the files that exist.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $names = 'msedge.exe', 'chrome.exe', 'firefox.exe', 'opera.exe', 'brave.exe', 'vivaldi.exe'
    $found = New-Object -TypeName 'System.Collections.Generic.List[string]'

    foreach ($name in $names) {
        foreach ($root in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths') {
            try {
                $path = [string](Get-Item -LiteralPath (Join-Path -Path $root -ChildPath $name) -ErrorAction Stop).GetValue('')
            }
            catch {
                continue
            }
            $path = $path.Trim().Trim('"')
            if ($path -and -not $found.Contains($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                $found.Add($path)
            }
        }
    }
    $found
}
