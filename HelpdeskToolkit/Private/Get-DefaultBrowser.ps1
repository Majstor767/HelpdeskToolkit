function Get-DefaultBrowser {
    <#
    .SYNOPSIS
        Returns the default web browser of the user, whether it still exists, and what to use when it does not.
    .DESCRIPTION
        The default browser is a choice Windows wrote down (see Get-BrowserAssociation).
        It can outlive the browser: when a browser is removed and its uninstaller
        leaves its registration behind, Windows goes on handing every link to a
        program file that is gone. A click on a link in any program then fails with
        "Application not found".

        This function follows the choice to the program file and looks whether the
        file is there. When it is not, it looks for a browser that can be used
        instead: the one the older setting of Windows names, then the installed
        browsers (see Get-InstalledBrowserPath).

        Returns an object with:
        - ProgId:   the choice as Windows wrote it down; empty when nothing is chosen
        - Path:     the program file the choice leads to, whether it exists or not
        - Exists:   whether that file is there
        - IsBroken: a browser is chosen, but its file is gone
        - Usable:   the program file to open pages with: the default browser when it
                    exists, another browser otherwise; empty when none was found
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $association = Get-BrowserAssociation
    $progId = if ($association.Latest) { [string]$association.Latest } else { [string]$association.Chosen }
    $path = Get-ProgramIdPath -ProgId $progId
    $exists = [bool]$path -and (Test-Path -LiteralPath $path -PathType Leaf)

    $usable = ''
    if ($exists) {
        $usable = $path
    }
    else {
        $candidates = @(
            # What the older setting names, when it is something else
            if ($association.Chosen -and $association.Chosen -ne $progId) {
                Get-ProgramIdPath -ProgId ([string]$association.Chosen)
            }
            Get-InstalledBrowserPath
        )
        foreach ($candidate in $candidates) {
            if (-not $usable -and $candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $usable = [string]$candidate
            }
        }
    }

    [PSCustomObject]@{
        ProgId   = $progId
        Path     = [string]$path
        Exists   = $exists
        IsBroken = [bool]$progId -and -not $exists
        Usable   = $usable
    }
}
