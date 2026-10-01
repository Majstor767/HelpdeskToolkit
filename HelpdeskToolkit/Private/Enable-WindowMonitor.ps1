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

        The runspace is created once per window. Leaving the page only pauses it
        (Disable-WindowMonitor), so coming back shows data again without a delay.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    if (-not $Gui.Monitor) {
        $shared = [hashtable]::Synchronized(@{
                Paused   = $false
                Stop     = $false
                Snapshot = $null
                Error    = $null
                Sequence = 0
            })

        $work = {
            param($ManifestPath, $Shared)
            Import-Module -Name $ManifestPath
            while (-not $Shared.Stop) {
                if ($Shared.Paused) {
                    Start-Sleep -Milliseconds 300
                    continue
                }
                try {
                    $Shared.Snapshot = Get-PerformanceSnapshot
                    $Shared.Error = $null
                }
                catch {
                    $Shared.Error = $_.Exception.Message
                }
                $Shared.Sequence++
                Start-Sleep -Milliseconds 300
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

    $Gui.Monitor.Shared.Paused = $false
    if ($Gui.MonitorTimer) {
        $Gui.MonitorTimer.Start()
    }
}
