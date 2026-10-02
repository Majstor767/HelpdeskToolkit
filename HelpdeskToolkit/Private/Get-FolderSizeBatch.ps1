function Get-FolderSizeBatch {
    <#
    .SYNOPSIS
        Measures several folders with a few threads at the same time and returns the size of each.
    .DESCRIPTION
        Finding out what fills a drive means walking through hundreds of thousands of
        folders. One thread that takes folder after folder needs a quarter of a minute
        for a full drive; several threads that share the work need a few seconds,
        because the drive answers several questions at once.

        Every thread walks through folders of its own: it adds up the files that lie
        in a folder directly and remembers the subfolders it still has to visit. When
        another thread runs out of work, it hands over half of what it remembers. So
        no thread waits for another, and a single huge folder does not keep one
        thread busy while the others have nothing left to do.

        The threads are small runspaces that only get this loop as text; they do not
        load the module, so they start in a few milliseconds.

        The loop calls as few .NET methods as it can: one per folder, for its listing.
        In PowerShell 7 a method call from a script costs about a hundred times what
        it costs in Windows PowerShell (every call is reported to the antimalware
        interface of Windows), and the threads have to take turns for it; with a few
        calls per folder eight threads were no faster than one there. The piles of
        folders are therefore tables with a counter, not Stack objects with Push and
        Pop, and work is handed over as one package instead of folder by folder.

        -BudgetMs limits the whole measurement. When the time is over, the folders
        whose subfolders were not all visited are returned with Complete = $false and
        the size counted so far.

        Like Get-FolderSize: files and folders that cannot be read are skipped, links
        to other folders (reparse points) are not followed, and only sizes are read.

        Returns one object per folder, in the order of -Path, with Path, Bytes,
        FileCount and Complete.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Path,

        [int]$BudgetMs = 15000,

        # How many threads walk through the folders. The default is one per logical
        # processor, but not more than eight: beyond that the drive is the limit.
        [ValidateRange(0, 16)]
        [int]$ThrottleLimit = 0
    )

    if ($ThrottleLimit -eq 0) {
        $ThrottleLimit = [math]::Max(2, [math]::Min(8, [Environment]::ProcessorCount))
    }

    $paths = @($Path | Where-Object { $_ })
    if ($paths.Count -eq 0) {
        return
    }

    $deadline = [datetime]::UtcNow.AddMilliseconds($BudgetMs)

    # Work that is waiting for a thread: packages of pairs, each pair being the number
    # of the folder it belongs to and the folder itself. Busy counts the threads that
    # have work of their own.
    $queue = New-Object -TypeName 'System.Collections.Concurrent.ConcurrentQueue[object]'
    $state = [hashtable]::Synchronized(@{ Busy = 0 })
    for ($index = 0; $index -lt $paths.Count; $index++) {
        if (Test-Path -LiteralPath $paths[$index] -PathType Container) {
            $queue.Enqueue(@(, @($index, (New-Object -TypeName System.IO.DirectoryInfo -ArgumentList $paths[$index]))))
        }
    }

    $work = {
        param($Queue, $State, $Deadline, $Count)

        $bytes = New-Object -TypeName 'long[]' -ArgumentList $Count
        $files = New-Object -TypeName 'int[]' -ArgumentList $Count
        $directory = [System.IO.FileAttributes]::Directory
        $link = [System.IO.FileAttributes]::ReparsePoint

        # The folders this thread still has to visit, and for each one the number of the
        # folder it belongs to. A thread works through its own pile without asking
        # anybody; only when another thread has nothing to do does it hand over a part.
        # The pile is a table with the places 0 to $top - 1 (see the description).
        $folders = @{}
        $owners = @{}
        $top = 0
        $package = $null
        $busy = $false
        $setBusy = {
            param([int]$Change)
            [System.Threading.Monitor]::Enter($State.SyncRoot)
            try { $State.Busy += $Change } finally { [System.Threading.Monitor]::Exit($State.SyncRoot) }
        }

        while ([datetime]::UtcNow -lt $Deadline) {
            if ($top -eq 0) {
                # Busy is raised before the look into the queue: a thread that has just
                # taken the last package must not look idle to the others for a moment,
                # or they would go home while there is still work to hand over.
                if (-not $busy) {
                    & $setBusy 1
                    $busy = $true
                }
                if ($Queue.TryDequeue([ref]$package)) {
                    foreach ($pair in $package) {
                        $owners[$top] = [int]$pair[0]
                        $folders[$top] = $pair[1]
                        $top++
                    }
                }
                else {
                    & $setBusy -1
                    $busy = $false
                    if ($State.Busy -le 0) {
                        # Nothing waits and nobody is working: everything is measured.
                        break
                    }
                    Start-Sleep -Milliseconds 10
                    continue
                }
            }

            $top--
            $folder = $folders[$top]
            $index = $owners[$top]
            try {
                # One listing returns the files with their sizes and the subfolders with
                # their attributes, so no file has to be asked a second time.
                foreach ($entry in $folder.EnumerateFileSystemInfos()) {
                    if ($entry.Attributes -band $directory) {
                        if (-not ($entry.Attributes -band $link)) {
                            $folders[$top] = $entry
                            $owners[$top] = $index
                            $top++
                        }
                    }
                    else {
                        $bytes[$index] += $entry.Length
                        $files[$index]++
                    }
                }
            }
            catch {
                # A folder that cannot be read is skipped.
                $null = $_
            }

            # Another thread is out of work: it gets half of what is waiting here.
            if ($top -gt 3 -and $Queue.IsEmpty) {
                $Queue.Enqueue(@(
                        for ($share = [int]($top / 2); $share -gt 0; $share--) {
                            $top--
                            , @($owners[$top], $folders[$top])
                        }
                    ))
            }
        }

        if ($busy) {
            & $setBusy -1
        }

        # What this thread could not visit before the time was over
        $left = @(for ($place = 0; $place -lt $top; $place++) { $owners[$place] }) | Select-Object -Unique
        [PSCustomObject]@{ Bytes = $bytes; Files = $files; Unfinished = @($left) }
    }
    $unfinished = @{}
    $failed = $false
    $shells = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $totalBytes = New-Object -TypeName 'long[]' -ArgumentList $paths.Count
    $totalFiles = New-Object -TypeName 'int[]' -ArgumentList $paths.Count
    $pool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
    $pool.Open()

    try {
        for ($worker = 0; $worker -lt $ThrottleLimit; $worker++) {
            $shell = [powershell]::Create()
            $shell.RunspacePool = $pool
            [void]$shell.AddScript($work.ToString()).AddArgument($queue).AddArgument($state).AddArgument($deadline).AddArgument($paths.Count)
            $shells.Add(@{ Shell = $shell; Handle = $shell.BeginInvoke() })
        }

        foreach ($entry in $shells) {
            try {
                $part = @($entry.Shell.EndInvoke($entry.Handle)) | Select-Object -Last 1
            }
            catch {
                Write-Verbose "A thread that measured folders failed: $($_.Exception.Message)"
                $part = $null
            }
            if ($part) {
                for ($index = 0; $index -lt $paths.Count; $index++) {
                    $totalBytes[$index] += $part.Bytes[$index]
                    $totalFiles[$index] += $part.Files[$index]
                }
                foreach ($index in $part.Unfinished) {
                    $unfinished[[int]$index] = $true
                }
            }
            else {
                # What a thread counted is lost with it, so nothing can be called complete.
                $failed = $true
            }
        }
    }
    finally {
        foreach ($entry in $shells) {
            $entry.Shell.Dispose()
        }
        $pool.Dispose()
    }

    # What is left in the queue was not visited either: the time was over.
    $package = $null
    while ($queue.TryDequeue([ref]$package)) {
        foreach ($pair in $package) {
            $unfinished[[int]$pair[0]] = $true
        }
    }

    for ($index = 0; $index -lt $paths.Count; $index++) {
        [PSCustomObject]@{
            Path      = $paths[$index]
            Bytes     = [long]$totalBytes[$index]
            FileCount = [int]$totalFiles[$index]
            Complete  = -not $failed -and -not $unfinished.ContainsKey($index)
        }
    }
}
