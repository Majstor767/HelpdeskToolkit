function Get-DefaultBrowserPath {
    <#
    .SYNOPSIS
        Returns the path of the web browser to open pages and reports with; nothing when there is none.
    .DESCRIPTION
        That is the default browser of the user, as long as its program file exists.
        When Windows still names a browser that was removed, another browser that is
        installed is returned instead (see Get-DefaultBrowser).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $browser = Get-DefaultBrowser
    if ($browser.Usable) {
        [string]$browser.Usable
    }
}
