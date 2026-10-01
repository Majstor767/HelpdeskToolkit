function Get-FolderSize {
    <#
    .SYNOPSIS
        Adds up the size of all files in a folder and its subfolders.
    .DESCRIPTION
        Returns an object with Bytes, FileCount and Complete.

        Counting stops after -TimeoutMs so that an enormous folder cannot hold up the
        whole health check; Complete is then $false and Bytes is a lower bound.

        Files and folders that cannot be read are skipped, and links to other folders
        (reparse points) are not followed, which avoids counting twice and endless loops.
        Only file sizes are read; nothing is opened or changed.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$TimeoutMs = 3000
    )

    $bytes = [long]0
    $fileCount = 0
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # Folders still to visit. A stack instead of recursion keeps the function simple
    # and lets it stop at any moment.
    $pending = New-Object -TypeName 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    if (Test-Path -LiteralPath $Path) {
        $pending.Push((New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $Path))
    }

    while ($pending.Count -gt 0 -and $stopwatch.ElapsedMilliseconds -lt $TimeoutMs) {
        $folder = $pending.Pop()
        try {
            # One listing returns the files with their sizes and the subfolders with
            # their attributes, so no file has to be asked a second time.
            foreach ($entry in $folder.EnumerateFileSystemInfos()) {
                if ($entry.Attributes -band [System.IO.FileAttributes]::Directory) {
                    if (-not ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                        $pending.Push($entry)
                    }
                }
                else {
                    $bytes += $entry.Length
                    $fileCount++
                }
            }
        }
        catch {
            Write-Verbose "Skipped folder $($folder.FullName): $($_.Exception.Message)"
        }
    }

    [PSCustomObject]@{
        Bytes     = $bytes
        FileCount = $fileCount
        Complete  = $pending.Count -eq 0
    }
}