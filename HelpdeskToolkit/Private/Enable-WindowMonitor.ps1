function Enable-WindowMonitor {
    <#
    .SYNOPSIS
        Starts (or resumes) the measurements for the Live monitor page.
    .DESCRIPTION
        One measurement takes about two seconds, far too long for the thread that draws
        the window. A second PowerShell runspace therefore measures in a loop and puts
        each snapshot into a table that both threads can use safely (a synchronized
        hashtable). A timer on the window thread looks into that table a few times per
        second and displays a new snapshot when there is one (Receive-WindowMonitor).

        The same table carries the wishes of the window to the loop: Paused, Stop and
        IntervalSeconds, the time from the start of one measurement to the start of the
        next. The loop waits in short steps, so it reacts to a change within a moment.

        The runspace is created once per window. Leaving the page only pauses it
        (Disable-WindowMonitor), so coming back shows data again without a delay. When
        the user pressed Pause, opening the page does not resume by itself.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    if (-not $Gui.Monitor) {
        $shared = [hashtable]::Synchronized(@{
                Paused          = $false
                Stop            = $false
                IntervalSeconds = [int]$Gui.Settings.MonitorIntervalSeconds
                Snapshot        = $null
                Error           = $null
                Sequence        = 0
            })

        $work = {
            param($ManifestPath, $Shared)
            Import-Module -Name $ManifestPath
            while (-not $Shared.Stop) {
                if ($Shared.Paused) {
                    Start-Sleep -Milliseconds 200
                    continue
                }

                $started = Get-Date
                try {
                    $Shared.Snapshot = Get-PerformanceSnapshot
                    $Shared.Error = $null
                }
                catch {
                    $Shared.Error = $_.Exception.Message
                }
                $Shared.Sequence++

                # Wait for the rest of the interval, but at least a moment, so the loop
                # never keeps the processor busy all the time.
                Start-Sleep -Milliseconds 300
                while (-not $Shared.Stop -and -not $Shared.Paused -and ((Get-Date) - $started).TotalSeconds -lt $Shared.IntervalSeconds) {
                    Start-Sleep -Milliseconds 200
                }
            }
        }

        $worker = [powershell]::Create()
        [void]$worker.AddScript($work.ToString()).AddArgument($Gui.ManifestPath).AddArgument($shared)

        $Gui.Monitor = @{
            Worker       = $worker
            Handle       = $worker.BeginInvoke()
            Shared       = $shared
            LastSequence = 0
        }
    }

    if (-not $Gui.MonitorUserPaused) {
        $Gui.Monitor.Shared.Paused = $false
    }
    if ($Gui.MonitorTimer) {
        $Gui.MonitorTimer.Start()
    }
}
