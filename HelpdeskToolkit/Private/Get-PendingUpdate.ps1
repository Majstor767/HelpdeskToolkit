function Get-PendingUpdate {
    <#
    .SYNOPSIS
        Returns the titles of the updates Windows Update has found but not installed yet.
    .DESCRIPTION
        Asks the Windows Update Agent for updates that are not installed and not
        hidden. The question is answered from the result of the last search Windows
        made on its own ("offline"), so nothing is sent to Microsoft, nothing is
        downloaded and nothing is installed, and the answer comes within seconds.

        Throws when the Windows Update Agent cannot be used (for example when the
        service is disabled). No administrator rights are needed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $searcher.Online = $false

    $found = $searcher.Search('IsInstalled=0 and IsHidden=0')
    foreach ($update in $found.Updates) {
        [string]$update.Title
    }
}
