function Receive-WindowFeedback {
    <#
    .SYNOPSIS
        Takes over the result of a feedback message that was sent in the background.
    .DESCRIPTION
        Called by a timer while a message is on its way (see Send-WindowFeedback).
        Does nothing until the background work is done or has taken longer than it
        may.

        - Sent: the form is emptied and closed, and the status line of the window
          thanks the user.
        - Not sent: the form stays open with the text in it and says why, so nothing
          the user wrote is lost and "Send" can be tried again. The reason is also
          written to the log of the application; the text of the message never is.

        Returns "Waiting", "Sent" or "Failed", or nothing when no message is on its way.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls
    $worker = $Gui['FeedbackWorker']
    if (-not $worker) {
        if ($Gui['FeedbackTimer']) {
            $Gui.FeedbackTimer.Stop()
        }
        return
    }

    $handle = $Gui['FeedbackHandle']
    $late = $Gui['FeedbackDeadline'] -and (Get-Date) -gt $Gui['FeedbackDeadline']
    if ($handle -and -not $handle.IsCompleted -and -not $late) {
        return 'Waiting'
    }

    $result = $null
    $problem = ''
    try {
        if ($handle -and $handle.IsCompleted) {
            $result = @($worker.EndInvoke($handle)) | Where-Object { $_ -and $_.PSObject.Properties['Sent'] } | Select-Object -Last 1
            if (-not $result -and $worker.Streams.Error.Count -gt 0) {
                $problem = [string]$worker.Streams.Error[0]
            }
        }
        else {
            $problem = Get-LocalizedText 'The service did not answer in time.'
            # Without waiting for it: a request that hangs must not hang the window.
            [void]$worker.BeginStop($null, $null)
        }
    }
    catch {
        $problem = $_.Exception.Message
    }
    finally {
        if ($handle -and $handle.IsCompleted) {
            $worker.Dispose()
        }
        $Gui.FeedbackWorker = $null
        $Gui.FeedbackHandle = $null
        $Gui.FeedbackDeadline = $null
        if ($Gui['FeedbackTimer']) {
            $Gui.FeedbackTimer.Stop()
        }
    }

    if ($result -and $result.Sent) {
        [void](Close-WindowFeedback -Gui $Gui -Clear)
        $controls.StatusText.Text = Get-LocalizedText 'Thank you. Your feedback was sent to the author.'
        return 'Sent'
    }

    if ($result -and $result.Error) {
        $problem = [string]$result.Error
    }
    if (-not $problem) {
        $problem = Get-LocalizedText 'The service did not accept the message.'
    }
    [void](Write-AppLog -Message ('Feedback could not be sent: {0}' -f $problem))
    $controls.FeedbackStatus.Text = (Get-LocalizedText 'The message could not be sent: {0} Your text is still here; check the internet connection and try again.') -f $problem
    $controls.FeedbackStatus.Visibility = [System.Windows.Visibility]::Visible
    Update-WindowFeedback -Gui $Gui
    'Failed'
}
