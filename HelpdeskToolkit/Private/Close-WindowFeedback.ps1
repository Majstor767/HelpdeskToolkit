function Close-WindowFeedback {
    <#
    .SYNOPSIS
        Closes the form "Send feedback" and gives the window back.
    .DESCRIPTION
        "Cancel" and Esc close the form without sending; what was written stays in it
        for the next time. After a message was sent the form is closed with -Clear,
        which empties both fields.

        While a message is on its way the form stays open: its result is shown in it.
        Returns whether the form was closed.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Empty the form; used after a message was sent.
        [switch]$Clear
    )

    $controls = $Gui.Controls
    if ($Gui['FeedbackWorker']) {
        return $false
    }

    if ($Clear) {
        $controls.FeedbackText.Text = ''
        $controls.FeedbackAddress.Text = ''
    }
    $controls.FeedbackStatus.Text = ''
    $controls.FeedbackStatus.Visibility = [System.Windows.Visibility]::Collapsed
    $controls.FeedbackOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $controls.MainLayout.IsEnabled = $true
    $true
}
