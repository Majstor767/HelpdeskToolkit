function Get-AppDataPath {
    <#
    .SYNOPSIS
        Returns the folder in which the application keeps its own files.
    .DESCRIPTION
        The application never changes the computer it examines, but it remembers a few
        things of its own: the settings of the window, the reports of earlier checks
        (for the comparison "since the last check") and recordings of the Live monitor.
        They live in %LOCALAPPDATA%\HelpdeskToolkit, a place every program may write
        to without administrator rights and that belongs to the current user only.

        The folder is not created here; the functions that write into it do that.
        $script:AppDataRoot replaces the location, which the tests use.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # A file or folder inside the application folder.
        [string]$ChildPath = ''
    )

    $root = if ($script:AppDataRoot) { $script:AppDataRoot } else { Join-Path -Path $env:LOCALAPPDATA -ChildPath 'HelpdeskToolkit' }

    if ($ChildPath) {
        return Join-Path -Path $root -ChildPath $ChildPath
    }
    $root
}
