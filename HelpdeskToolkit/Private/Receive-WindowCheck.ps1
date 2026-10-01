function Receive-WindowCheck {
    <#
    .SYNOPSIS
        Updates the window with the progress or the result of the background check.
    .DESCRIPTION
        Called by a timer on the window thread a few times per second. While the
        background runspace is still working, the latest Write-Progress record it
        produced is shown in the status bar. Once it has finished, the report is
        collected and displayed, and the runspace is released.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls
    $worker = $Gui.Worker

    if (-not $worker) {
        $Gui.Timer.Stop()
        return
    }

    if (-not $Gui.Handle.IsCompleted) {
        # Windows cmdlets used inside the checks write progress records of their own,
        # so only the records of Get-PCHealthReport are used. The record that closes
        # its progress bar has a percentage of -1 and is skipped as well.
        $latest = @($worker.Streams.Progress) |
            Where-Object { $_.Activity -eq $script:ProgressActivity -and $_.PercentComplete -ge 0 } |
            Select-Object -Last 1

        if ($latest) {
            $controls.ProgressBar.Value = $latest.PercentComplete
            $controls.StatusText.Text = 'Checking: {0} ...' -f $latest.StatusDescription
        }
        return
    }

    $Gui.Timer.Stop()
    try {
        $output = @($worker.EndInvoke($Gui.Handle))
        $report = $output |
            Where-Object { $_ -and $_.PSObject.TypeNames -contains 'HelpdeskToolkit.HealthReport' } |
            Select-Object -Last 1

        if (-not $report) {
            $reason = if ($worker.Streams.Error.Count -gt 0) { $worker.Streams.Error[0].ToString() } else { 'No report was returned.' }
            throw $reason
        }

        Show-WindowReport -Gui $Gui -Report $report
    }
    catch {
        $controls.StatusText.Text = 'The check failed: {0}' -f $_.Exception.Message
    }
    finally {
        $worker.Dispose()
        $Gui.Worker = $null
        $Gui.Handle = $null
        $controls.RunButton.IsEnabled = $true
        $controls.RunButton.Content = 'Run check'
        $controls.ProgressBar.Visibility = [System.Windows.Visibility]::Hidden
    }
}
