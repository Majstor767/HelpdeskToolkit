function Receive-WindowCheck {
    <#
    .SYNOPSIS
        Updates the window with the progress or the result of the background check.
    .DESCRIPTION
        Called by a timer on the window thread a few times per second. While the
        background runspace is still working, the latest Write-Progress record it
        produced is shown in the progress panel. Once it has finished, the report is
        collected and displayed, and the runspace is released.

        A finished report is also added to the history of the application (see
        Save-HealthReportHistory), after the report of the previous check was looked
        up, so the Overview can show what changed since then.
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

        if ($latest -and $controls.RunPercent.Text -ne ('{0} %' -f $latest.PercentComplete)) {
            $controls.RunTitle.Text = (Get-LocalizedText 'Checking: {0}') -f (Get-LocalizedText $latest.StatusDescription)
            $controls.RunStep.Text = Get-LocalizedText ([string]$latest.CurrentOperation)
            $controls.RunPercent.Text = '{0} %' -f $latest.PercentComplete

            # The bar glides to its new value instead of jumping.
            $animation = New-Object -TypeName System.Windows.Media.Animation.DoubleAnimation
            $animation.To = [double]$latest.PercentComplete
            $animation.Duration = New-Object -TypeName System.Windows.Duration -ArgumentList ([timespan]::FromMilliseconds(450))
            $animation.EasingFunction = New-Object -TypeName System.Windows.Media.Animation.QuadraticEase
            $controls.ProgressBar.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $animation)
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

        $previous = Get-PreviousHealthReport -Report $report
        [void](Save-HealthReportHistory -Report $report)

        if ($previous) {
            Show-WindowReport -Gui $Gui -Report $report -Previous $previous
        }
        else {
            Show-WindowReport -Gui $Gui -Report $report
        }
    }
    catch {
        $controls.StatusText.Text = (Get-LocalizedText 'The check failed: {0}') -f $_.Exception.Message
    }
    finally {
        $worker.Dispose()
        $Gui.Worker = $null
        $Gui.Handle = $null
        $controls.RunButton.IsEnabled = $true
        $controls.RunButton.Content = Get-LocalizedText 'Run check'
        $controls.RunPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }
}
