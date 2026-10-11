function Show-WindowFeedback {
    <#
    .SYNOPSIS
        Opens the form "Send feedback" over the window.
    .DESCRIPTION
        The button at the bottom of the side bar opens a small form over the window,
        like the question at the start: a field for the text, one for an address to
        answer to (which may stay empty), "Send" and "Cancel". The window behind it
        cannot be used until the form is closed.

        The form says what is sent and through which service before anything is sent
        (see New-FeedbackMessage and Config\Feedback.psd1). A text that was written
        and not sent is still there when the form is opened again.

        Does nothing when feedback is switched off (see Get-FeedbackSetting).
        Returns whether the form was opened.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls
    $setting = Get-FeedbackSetting
    if (-not $setting.Enabled) {
        return $false
    }

    $controls.FeedbackText.MaxLength = $setting.MaximumLength
    $controls.FeedbackNote.Text = (Get-LocalizedText 'What is sent: your text, the address if you enter one, and the version of this application ({0}) and of Windows ({1}). Nothing else: not the name of this computer, not your user name and none of the results. The message is delivered by {2}, a service that passes it on to the author by e-mail.') -f `
        (Get-ToolVersion), [Environment]::OSVersion.Version.ToString(3), $setting.Service
    $controls.FeedbackStatus.Text = ''
    $controls.FeedbackStatus.Visibility = [System.Windows.Visibility]::Collapsed

    $controls.MainLayout.IsEnabled = $false
    $controls.FeedbackOverlay.Visibility = [System.Windows.Visibility]::Visible
    Update-WindowFeedback -Gui $Gui
    [void]$controls.FeedbackText.Focus()
    $true
}
