function Get-LargestFolder {
    <#
    .SYNOPSIS
        Finds out what takes up the space on a drive: its largest folders and files.
    .DESCRIPTION
        Measures every folder in the root of the drive, and the large files that lie
        there directly (such as the hibernation file and the page file). On the drive
        that holds the profile of the current user, the folders inside that profile
        (Documents, Downloads, AppData, ...) are measured one by one instead of the
        "Users" folder as a whole, because that is where a user can actually clean up.

        -BudgetMs limits the measuring, so a huge drive cannot hold up the health
        check: a folder that was not walked through to the end by then has a size that
        is a lower bound, and Complete is $false.

        The folders are measured together, by several threads that share the work. A
        drive that took a quarter of a minute folder by folder is done in a few
        seconds that way, and large folders are measured to the end instead of being
        cut off.

        Folders that the current user may not read are counted as far as possible.
        Only sizes are read; nothing is opened or changed.

        Returns objects with Name, Bytes and Complete, largest first.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Root of the drive, for example "C:\".
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$BudgetMs = 15000,

        # Files in the root of the drive are only listed from this size on.
        [long]$MinimumFileBytes = 1GB
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $root = New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $Path
    $results = New-Object -TypeName 'System.Collections.Generic.List[object]'

    # What to measure: display name and full path
    $candidates = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $userProfile = [string]$env:USERPROFILE
    $usersFolder = if ($userProfile) { Split-Path -Path $userProfile -Parent } else { '' }

    try {
        foreach ($entry in $root.EnumerateFileSystemInfos()) {
            if ($entry.Attributes -band [System.IO.FileAttributes]::Directory) {
                if ($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    continue
                }
                if ($usersFolder -and $entry.FullName -eq $usersFolder) {
                    # The profile of the current user, folder by folder
                    foreach ($inner in (New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $userProfile).EnumerateDirectories()) {
                        if (-not ($inner.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                            $name = '{0}\{1}\{2}' -f $entry.Name, (Split-Path -Path $userProfile -Leaf), $inner.Name
                            $candidates.Add([PSCustomObject]@{ Name = $name; Path = $inner.FullName })
                        }
                    }
                }
                else {
                    $candidates.Add([PSCustomObject]@{ Name = $entry.Name; Path = $entry.FullName })
                }
            }
            elseif ($entry.Length -ge $MinimumFileBytes) {
                $results.Add([PSCustomObject]@{ Name = $entry.Name; Bytes = [long]$entry.Length; Complete = $true })
            }
        }
    }
    catch {
        Write-Verbose "Could not list ${Path}: $($_.Exception.Message)"
    }

    # All folders are measured together, by a few threads that share the work (see
    # Get-FolderSizeBatch).
    $remaining = $BudgetMs - $stopwatch.ElapsedMilliseconds
    if ($candidates.Count -gt 0 -and $remaining -gt 0) {
        $sizes = @{}
        foreach ($size in Get-FolderSizeBatch -Path @($candidates | ForEach-Object { $_.Path }) -BudgetMs $remaining) {
            $sizes[$size.Path] = $size
        }
        foreach ($candidate in $candidates) {
            $size = $sizes[$candidate.Path]
            if ($size -and $size.Bytes -gt 0) {
                $results.Add([PSCustomObject]@{ Name = $candidate.Name; Bytes = [long]$size.Bytes; Complete = $size.Complete })
            }
        }
    }
    $results | Sort-Object -Property Bytes -Descending
}
