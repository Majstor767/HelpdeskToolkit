function Send-WindowFeedback {
    <#
    .SYNOPSIS
        Sends what is written in the form "Send feedback", in the background.
    .DESCRIPTION
        The action of "Send" (and of Ctrl+Enter in the form). Nothing is sent before
        this click, and only what the form shows and names (see New-FeedbackMessage).

        The form is checked first: a text must be there, and an address, when one was
        typed in, must look like one, because the author would answer to it. What is
        wrong is said in the form and nothing is sent.

        The request can take seconds, or as long as the timeout when the computer is
        offline, so it runs in a background runspace like the other slow work of the
        window; a timer asks a few times per second whether it is done
        (Receive-WindowFeedback). Until then the form cannot be edited or closed.

        Returns whether sending was started.
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
    if (-not $setting.Enabled -or $Gui['FeedbackWorker']) {
        return $false
    }

    $say = {
        param([string]$Text)
        $controls.FeedbackStatus.Text = $Text
        $controls.FeedbackStatus.Visibility = [System.Windows.Visibility]::Visible
    }

    $text = ([string]$controls.FeedbackText.Text).Trim()
    if (-not $text) {
        & $say (Get-LocalizedText 'Write your message first.')
        [void]$controls.FeedbackText.Focus()
        return $false
    }
    if ($text.Length -gt $setting.MaximumLength) {
        & $say ((Get-LocalizedText 'The message is too long: at most {0} characters.') -f $setting.MaximumLength)
        return $false
    }
    $address = ([string]$controls.FeedbackAddress.Text).Trim()
    if ($address -and $address -notmatch '^[^@\s]+@[^@\s]+\.[^@\s.]+$') {
        & $say (Get-LocalizedText 'That does not look like an e-mail address. Correct it, or leave the field empty.')
        [void]$controls.FeedbackAddress.Focus()
        return $false
    }

    $body = New-FeedbackMessage -Text $text -Address $address -Field $setting.Fields

    $work = {
        param($ManifestPath, $Body, $Endpoint, $TimeoutSeconds)
        $module = Import-Module -Name $ManifestPath -PassThru
        & $module { param($Body, $Endpoint, $TimeoutSeconds) Send-FeedbackMessage -Body $Body -Endpoint $Endpoint -TimeoutSeconds $TimeoutSeconds } $Body $Endpoint $TimeoutSeconds
    }
    $worker = [powershell]::Create()
    [void]$worker.AddScript($work.ToString()).AddArgument($Gui.ManifestPath).AddArgument($body).AddArgument($setting.Endpoint).AddArgument($setting.TimeoutSeconds)
    $Gui.FeedbackWorker = $worker
    $Gui.FeedbackHandle = $worker.BeginInvoke()
    # The service gets its timeout, and the runspace a little more to load the module.
    $Gui.FeedbackDeadline = (Get-Date).AddSeconds($setting.TimeoutSeconds + 20)

    & $say (Get-LocalizedText 'Sending ...')
    Update-WindowFeedback -Gui $Gui

    if (-not $Gui['FeedbackTimer']) {
        # A timer that catches its own errors: Windows never calls one again whose
        # handler has failed.
        $timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $timer.Interval = [timespan]::FromMilliseconds(250)
        $timer.Add_Tick({
                try {
                    Receive-WindowFeedback -Gui $script:HealthCheckWindow
                }
                catch {
                    [void](Write-WindowError -Gui $script:HealthCheckWindow -ErrorRecord $_)
                }
            })
        $Gui.FeedbackTimer = $timer
    }
    $Gui.FeedbackTimer.Start()
    $true
}
