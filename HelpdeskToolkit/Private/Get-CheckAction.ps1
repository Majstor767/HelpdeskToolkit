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

        An entry can depend on the value of the result: with a "Vendors" table instead
        of a target, the place is the one whose key (a regular expression) fits the
        value. The support pages of the computer makers are listed that way; a maker
        that is not in the table has no place, so nothing can be opened that is not
        written in the configuration file.

        Returns a table with Label, Target and Arguments, or nothing when the check has
        no such place. Opening it is done by Invoke-CheckAction.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Category = '',

        # The value of the result, for entries that depend on it.
        [string]$Value = ''
    )

    if (-not $script:Actions) {
        $script:Actions = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Actions.psd1')
    }

    $keys = @($Check, ($Check -replace '\s*[:(].*$', ''))
    if ($Category) {
        $keys += 'Category:{0}' -f $Category
    }

    foreach ($key in $keys) {
        if ($script:Actions.ContainsKey($key)) {
            $action = $script:Actions[$key]

            if ($action.ContainsKey('Vendors')) {
                $vendor = $action.Vendors.Keys | Sort-Object | Where-Object { $Value -match $_ } | Select-Object -First 1
                if (-not $vendor) {
                    return
                }
                return @{
                    Label     = [string]$action.Label
                    Target    = [string]$action.Vendors[$vendor]
                    Arguments = ''
                }
            }

            return @{
                Label     = [string]$action.Label
                Target    = [string]$action.Target
                Arguments = if ($action.ContainsKey('Arguments')) { [string]$action.Arguments } else { '' }
            }
        }
    }
}
