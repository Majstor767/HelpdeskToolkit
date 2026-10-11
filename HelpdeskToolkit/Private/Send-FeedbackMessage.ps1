function Send-FeedbackMessage {
    <#
    .SYNOPSIS
        Sends a feedback message to the form service and says whether it was accepted.
    .DESCRIPTION
        The one place in the application that sends something the user wrote to the
        internet, and only after a click on "Send" (see Send-WindowFeedback). The
        message (see New-FeedbackMessage) goes as JSON in one https request to the
        address of the form; the service passes it on to the author by e-mail.

        A form service answers with JSON. The message counts as sent when the request
        succeeded and the answer does not say otherwise ("success" or "ok" being
        false). Every failure is returned, never thrown: no connection, a service that
        refuses the request, an answer that takes too long.

        Returns an object with Sent and, when it was not, Error: the reason in the
        words of Windows or of the service.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # The message, as built by New-FeedbackMessage.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Body,

        # The address of the form (see Get-FeedbackSetting).
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 20
    )

    if ($Endpoint -notmatch '^https://[^\s"<>]+$') {
        return [PSCustomObject]@{ Sent = $false; Error = 'The address of the form is not an https address.' }
    }

    try {
        # Windows PowerShell 5.1 on an older .NET offers only protocols form services
        # no longer accept.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        # As bytes: Windows PowerShell would otherwise send letters outside the
        # English alphabet in the code page of the computer.
        $json = $Body | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

        $request = @{
            Uri         = $Endpoint
            Method      = 'Post'
            Body        = $bytes
            ContentType = 'application/json; charset=utf-8'
            Headers     = @{ Accept = 'application/json' }
            UserAgent   = 'HelpdeskToolkit/{0}' -f (Get-ToolVersion)
            TimeoutSec  = $TimeoutSeconds
            ErrorAction = 'Stop'
        }
        $answer = Invoke-RestMethod @request

        foreach ($name in 'success', 'ok') {
            if ($answer -and $answer.PSObject.Properties[$name] -and $answer.$name -eq $false) {
                $reasons = @(
                    foreach ($text in 'message', 'error') {
                        if ($answer.PSObject.Properties[$text] -and $answer.$text) { [string]$answer.$text }
                    }
                )
                $reason = if ($reasons.Count -gt 0) { $reasons[0] } else { 'The service did not accept the message.' }
                return [PSCustomObject]@{ Sent = $false; Error = $reason }
            }
        }
        [PSCustomObject]@{ Sent = $true; Error = '' }
    }
    catch {
        [PSCustomObject]@{ Sent = $false; Error = $_.Exception.Message.Trim() }
    }
}
