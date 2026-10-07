function Get-SearchAddress {
    <#
    .SYNOPSIS
        Returns the address of a web search for the given words.
    .DESCRIPTION
        An error Windows offers no place to fix (a program that keeps crashing, an
        update that fails with a code, a blue screen) is looked up on the web. The
        address of the search engine is "SearchUrl" in Config\Help.psd1; the words are
        escaped, so whatever they contain stays inside the search and cannot change the
        address.

        Nothing is opened here, and nothing is sent anywhere: the address is only
        used when the user clicks the link that carries it (see Open-WindowHelpLink).
        The callers decide what the words may be (see Get-CheckHelpLink and
        Get-TimelineHelpLink).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The search words, as they would be typed into the search field.
        [Parameter(Mandatory)]
        [string]$Words
    )

    if (-not $script:Help) {
        $script:Help = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Help.psd1')
    }
    ([string]$script:Help.SearchUrl) -f [uri]::EscapeDataString($Words)
}
