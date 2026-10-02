function Get-CheckRisk {
    <#
    .SYNOPSIS
        Returns why the problem of a check matters: what it leads to when it is left as it is.
    .DESCRIPTION
        The recommendation of a result says what to do; this text says why it is worth
        doing. The window and the HTML report show it next to every result with the
        status Warning or Critical.

        The texts are in Config\Risks.psd1 and are looked up from the most specific
        key to the most general one:

        0. for the drive Windows is installed on (the value of the result ends in
           "Windows drive"), the short name with ":Windows drive"   "Disk:Windows drive"
        1. the name of the check                       "Firewall - Public profile"
        2. the part before the first colon or parenthesis   "Disk" for "Disk (C:)"
        3. the part before " - "                            "Firewall"
        4. for a service, "Service:<name>", with the name that stands in parentheses
                                                 "Service:Spooler" for "Print Spooler (Spooler)"
        5. the category                                     "Category:Security"

        Returns an empty text when nothing fits.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Category = '',

        # The value of the result; it tells the drive of Windows from the other drives.
        [string]$Value = ''
    )

    if (-not $script:Risks) {
        $script:Risks = Import-PowerShellDataFile -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Risks.psd1')
    }

    $keys = @(
        if ($Value -match ', Windows drive$') {
            '{0}:Windows drive' -f ($Check -replace '\s*[:(].*$', '')
        }
        $Check
        $Check -replace '\s*[:(].*$', ''
        $Check -replace '\s+-\s+.*$', ''
    )
    if ($Check -match '\(([^()]+)\)\s*$') {
        $keys += 'Service:{0}' -f $Matches[1]
    }
    if ($Category) {
        $keys += 'Category:{0}' -f $Category
    }

    foreach ($key in $keys) {
        if ($key -and $script:Risks.ContainsKey($key)) {
            return [string]$script:Risks[$key]
        }
    }

    ''
}
