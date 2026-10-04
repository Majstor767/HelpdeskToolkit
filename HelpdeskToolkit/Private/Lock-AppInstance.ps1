function Lock-AppInstance {
    <#
    .SYNOPSIS
        Claims the right to be the one running window of the application.
    .DESCRIPTION
        An application that stays next to the clock when its window is closed must
        not be started a second time by a click on its shortcut: two copies would both
        check the computer and both announce the same problem.

        The first copy opens the file "instance.lock" in the application folder (see
        Get-AppDataPath) for itself alone and keeps it open; a second copy cannot open
        it and knows from that. A file is used rather than a named object of Windows
        because it is seen the same by a copy that runs with administrator rights and
        by one that does not. The file is empty and is deleted when it is closed.

        Returns the open file, which the caller closes (Dispose) when the window is
        gone, or nothing when another copy holds it. When the file cannot be opened
        for any other reason (a folder that cannot be written to, for example), an
        empty stream is returned instead: the application then starts without this
        protection rather than not at all.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileStream], [System.IO.MemoryStream])]
    param()

    try {
        $folder = Get-AppDataPath
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
        [System.IO.FileStream]::new((Get-AppDataPath -ChildPath 'instance.lock'), [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 1, [System.IO.FileOptions]::DeleteOnClose)
    }
    catch {
        # 0x80070020: "The process cannot access the file because it is being used by another process."
        $cause = $_.Exception.GetBaseException()
        if ($cause -is [System.IO.IOException] -and $cause.HResult -eq -2147024864) {
            Write-Verbose 'Another copy of the application is running.'
            return
        }
        Write-Verbose "The instance file could not be opened; starting without it: $($cause.Message)"
        New-Object -TypeName System.IO.MemoryStream
    }
}
