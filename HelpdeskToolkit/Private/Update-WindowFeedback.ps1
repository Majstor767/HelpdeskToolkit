function Update-WindowFeedback {
    <#
    .SYNOPSIS
        Brings the form "Send feedback" in line with what is typed and with whether a message is on its way.
    .DESCRIPTION
        Called when the text changes, when the form opens and when sending starts or
        ends:

        - the counter below the text shows how much of the allowed length is used
        - "Send" can be clicked only when there is a text and nothing is being sent
        - while a message is on its way neither field can be edited and the form
          cannot be closed, so what is sent is what is shown
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only changes controls of the window; no system state is changed.')]
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls
    $sending = [bool]$Gui['FeedbackWorker']
    $text = [string]$controls.FeedbackText.Text

    $controls.FeedbackCount.Text = '{0} / {1}' -f $text.Length, (Get-FeedbackSetting).MaximumLength
    $controls.FeedbackSendButton.IsEnabled = -not $sending -and [bool]$text.Trim()
    $controls.FeedbackCancelButton.IsEnabled = -not $sending
    $controls.FeedbackText.IsReadOnly = $sending
    $controls.FeedbackAddress.IsReadOnly = $sending
}
