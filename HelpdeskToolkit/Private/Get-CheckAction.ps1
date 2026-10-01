function Get-CheckAction {
    <#
    .SYNOPSIS
        Returns the place in Windows where the problem of a check is fixed.
    .DESCRIPTION
        The recommendation of a result says what to do; this function knows where:
        a page of the Settings app, a management console or a system tool. The window
        shows it as a button next to the recommendation.

        The places are listed in Config\Actions.psd1 and are looked up like the
        descriptions: by the full name of the check, then by the part before the
        first colon or parenthesis ("Disk (C:)" -> "Disk"), and at last by the
        category ("Category:Printers").

        Returns a table with Label, Target and Arguments, or nothing when the check has
        no such place. Opening it is done by Invoke-CheckAction.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Category = ''
    )

    if (-not $script:Actions) {
        $script:Actions = Import-PowerShellDataFile -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Actions.psd1')
    }

    $keys = @($Check, ($Check -replace '\s*[:(].*$', ''))
    if ($Category) {
        $keys += 'Category:{0}' -f $Category
    }

    foreach ($key in $keys) {
        if ($script:Actions.ContainsKey($key)) {
            $action = $script:Actions[$key]
            return @{
                Label     = [string]$action.Label
                Target    = [string]$action.Target
                Arguments = if ($action.ContainsKey('Arguments')) { [string]$action.Arguments } else { '' }
            }
        }
    }
}
