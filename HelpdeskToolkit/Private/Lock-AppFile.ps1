function Lock-AppFile {
    <#
    .SYNOPSIS
        Keeps a file of the application open, so the installer can tell that the application is running.
    .DESCRIPTION
        An update replaces the folder of the module. Done while the window is open, it
        would take the files away from under the running application, whose background
        work loads the module from that folder.

        The installer therefore tries to open the icon of the application for writing
        before it changes anything (see installer\HelpdeskToolkit.iss). That fails
        while the file returned here is open. Looking for the process instead would
        not be enough: a window that runs with administrator rights is hidden from an
        installer that runs without them, but a file that is in use is not.

        The file is opened for reading and other programs can still read it; nothing
        is written. The caller closes the file (Dispose) when the window closes.
        Returns nothing when the file cannot be opened; the window then simply works
        without this protection.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileStream])]
    param(
        # The file to keep open. Defaults to the icon of the application.
        [string]$Path = (Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\HelpdeskToolkit.ico')
    )

    try {
        [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    }
    catch {
        Write-Verbose "The file $Path could not be kept open: $($_.Exception.Message)"
    }
}
