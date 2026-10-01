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
    $pending = New-Object -TypeName 'System.Collections.Generic.Stack[string]'
    if (Test-Path -LiteralPath $Path) {
        $pending.Push($Path)
    }

    while ($pending.Count -gt 0 -and $stopwatch.ElapsedMilliseconds -lt $TimeoutMs) {
        $folder = $pending.Pop()
        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($folder)) {
                try {
                    $bytes += (New-Object -TypeName System.IO.FileInfo -ArgumentList $file).Length
                    $fileCount++
                }
                catch {
                    Write-Verbose "Skipped file ${file}: $($_.Exception.Message)"
                }
            }

            foreach ($subfolder in [System.IO.Directory]::EnumerateDirectories($folder)) {
                $attributes = [System.IO.File]::GetAttributes($subfolder)
                if (-not ($attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    $pending.Push($subfolder)
                }
            }
        }
        catch {
            Write-Verbose "Skipped folder ${folder}: $($_.Exception.Message)"
        }
    }

    [PSCustomObject]@{
        Bytes     = $bytes
        FileCount = $fileCount
        Complete  = $pending.Count -eq 0
    }
}
