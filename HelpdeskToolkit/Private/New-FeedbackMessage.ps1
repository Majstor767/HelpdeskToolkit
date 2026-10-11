function New-FeedbackMessage {
    <#
    .SYNOPSIS
        Builds the message that "Send feedback" hands to the form service.
    .DESCRIPTION
        The whole of what leaves the computer when feedback is sent, in one place:

        - message:  the text the user wrote
        - email:    the address the user typed in, only when there is one. Form
                    services use a field of this name as the address to answer to.
        - version:  the version of the application
        - windows:  the version number of Windows ("10.0.26200")
        - language: the language of the window ("en" or "hr")
        - and the fields Config\Feedback.psd1 lists for the service, such as its
          access key. They cannot replace one of the fields above.

        Nothing about the computer goes into it: not its name, not the user, and none
        of the results of a check. The versions are there because "it does not work"
        can only be looked into when the version is known.

        Only builds the table; Send-FeedbackMessage sends it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds a table in memory; nothing is sent or changed.')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        # What the user wrote.
        [Parameter(Mandatory)]
        [string]$Text,

        # The address to answer to, or nothing.
        [AllowEmptyString()]
        [string]$Address = '',

        # The fields of the form service (see Get-FeedbackSetting).
        [hashtable]$Field = @{}
    )

    $message = [ordered]@{
        message = $Text.Trim()
    }
    if ($Address.Trim()) {
        $message['email'] = $Address.Trim()
    }
    $message['version'] = [string](Get-ToolVersion)
    $message['windows'] = [Environment]::OSVersion.Version.ToString(3)
    $message['language'] = [string]$script:Language

    foreach ($key in $Field.Keys | Sort-Object) {
        if (-not $message.Contains([string]$key)) {
            $message[[string]$key] = [string]$Field[$key]
        }
    }
    $message
}
