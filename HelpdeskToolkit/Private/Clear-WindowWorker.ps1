function Clear-WindowWorker {
    <#
    .SYNOPSIS
        Releases the background runspaces of the window that have ended.
    .DESCRIPTION
        A runspace that measures in a loop (the Live monitor) cannot be released the
        moment it is told to stop: it may be in the middle of a measurement, and
        waiting for it would freeze the window. Disable-WindowMonitor therefore only
        tells it to end and puts it on the list $Gui.RetiredWorkers.

        This function is called by a timer of the window. Every runspace on the list
        that has ended by now is released, together with the memory of the copy of
        the module it loaded; the others stay on the list for the next call. When
        something was released, the memory that became free is given back to Windows
        (Optimize-ProcessMemory).

        Returns the number of runspaces that were released.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $retired = $Gui['RetiredWorkers']
    if (-not $retired -or $retired.Count -eq 0) {
        return 0
    }

    $released = 0
    foreach ($entry in @($retired)) {
        if (-not $entry.Handle.IsCompleted) {
            continue
        }
        try {
            $entry.Worker.Dispose()
        }
        catch {
            Write-Verbose "A background runspace could not be released: $($_.Exception.Message)"
        }
        $retired.Remove($entry)
        $released++
    }

    if ($released -gt 0) {
        Optimize-ProcessMemory -Trim:([bool]$Gui['Hidden'])
    }
    $released
}
