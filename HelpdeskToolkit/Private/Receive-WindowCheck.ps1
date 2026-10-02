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

        The report of an automatic check (Invoke-WindowCheck -Background) is handled
        differently:
        - It replaces the results without interrupting the user (Show-WindowReport
          -KeepPage) and is not added to the history, which would otherwise fill up
          with a report every few minutes.
        - It is compared with the report it replaces. What is new or worse is
          announced at the top of the window (Add-WindowNotice) and, while the window
          is not in front, with a Windows notification (Show-WindowToast).

        A check the user starts is a fresh look at everything, so it removes the notices.
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
    $background = [bool]$Gui.Background
    try {
        $output = @($worker.EndInvoke($Gui.Handle))
        $report = $output |
            Where-Object { $_ -and $_.PSObject.TypeNames -contains 'HelpdeskToolkit.HealthReport' } |
            Select-Object -Last 1

        if (-not $report) {
            $reason = if ($worker.Streams.Error.Count -gt 0) { $worker.Streams.Error[0].ToString() } else { 'No report was returned.' }
            throw $reason
        }

        if ($background -and $Gui.Report) {
            $worse = @(
                Compare-PCHealthReport -Reference $Gui.Report -Difference $report |
                    Where-Object { $_.Change -in 'New problem', 'Worse' }
            )

            $parameters = @{ Gui = $Gui; Report = $report; KeepPage = $true }
            if ($Gui.PreviousReport) {
                $parameters.Previous = $Gui.PreviousReport
            }
            Show-WindowReport @parameters

            $added = @(Add-WindowNotice -Gui $Gui -Change $worse)
            if ($added.Count -gt 0 -and -not $Gui.Window.IsActive) {
                $title = if ($added.Count -eq 1) {
                    Get-LocalizedText 'HelpdeskToolkit: a new problem'
                }
                else {
                    (Get-LocalizedText 'HelpdeskToolkit: {0} new problems') -f $added.Count
                }
                $lines = $added | Select-Object -First 3 | ForEach-Object {
                    '{0}: {1}' -f (Get-LocalizedCheckName $_.Check), (Get-LocalizedText $_.Value)
                }
                Show-WindowToast -Gui $Gui -Title $title -Text ($lines -join "`n")
            }
        }
        else {
            $previous = Get-PreviousHealthReport -Report $report
            [void](Save-HealthReportHistory -Report $report)

            if ($previous) {
                Show-WindowReport -Gui $Gui -Report $report -Previous $previous
            }
            else {
                Show-WindowReport -Gui $Gui -Report $report
            }
            Show-WindowNotice -Gui $Gui -Clear
        }
    }
    catch {
        $controls.StatusText.Text = (Get-LocalizedText 'The check failed: {0}') -f $_.Exception.Message
    }
    finally {
        $worker.Dispose()
        $Gui.Worker = $null
        $Gui.Handle = $null
        $Gui.Background = $false
        # The automatic check counts from here, also after a check that failed.
        $Gui.LastCheckAt = Get-Date
        $controls.RunButton.IsEnabled = $true
        $controls.RunButton.Content = Get-LocalizedText 'Run check'
        $controls.RunPanel.Visibility = [System.Windows.Visibility]::Collapsed

        # A first check that failed leaves the Overview empty; it shows its hint again.
        if (-not $Gui.Report -and $Gui.Page -notin 'Live monitor', 'Settings') {
            Show-WindowPage -Gui $Gui -Name 'Overview'
        }
    }
}
