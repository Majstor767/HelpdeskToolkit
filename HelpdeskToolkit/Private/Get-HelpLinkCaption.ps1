function Get-HelpLinkCaption {
    <#
    .SYNOPSIS
        Returns the text of a link below the recommended fix of a problem.
    .DESCRIPTION
        The window and the HTML report show the same links (see Get-CheckHelpLink)
        and name them the same way; the window in its language, the report in
        English like the rest of it.

        - Page:    "What this means and how to fix it"
        - Article: "About update KB5050009"
        - Code:    "Search the web for error 0x80070005"
        - Program: "Search the web for crashes of contoso.exe"
        - Search:  "Search the web for this problem"
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # A link as returned by Get-CheckHelpLink.
        [Parameter(Mandatory)]
        [PSCustomObject]$Link,

        # Return the text in the language of the window.
        [switch]$Translate
    )

    $format = switch ([string]$Link.Kind) {
        'Page' { 'What this means and how to fix it' }
        'Article' { 'About update {0}' }
        'Code' { 'Search the web for error {0}' }
        'Program' { 'Search the web for crashes of {0}' }
        default { 'Search the web for this problem' }
    }
    if ($Translate) {
        $format = Get-LocalizedText $format
    }
    $format -f [string]$Link.Text
}
