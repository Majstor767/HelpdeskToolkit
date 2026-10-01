function Get-LocalizedCheckName {
    <#
    .SYNOPSIS
        Returns the name of a check in the language of the window.
    .DESCRIPTION
        A name like "Disk (C:)" or "Adapter: Contoso Ethernet" is translated by its
        first part; the rest is the name of a thing on the computer and stays as it is.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Name of the check as written in the report.
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $text = Get-LocalizedText $Name
    if ($text -eq $Name -and $Name -match '^(.*?)(\s*[:(].*)$') {
        $prefix = $Matches[1]
        $suffix = $Matches[2]
        $text = '{0}{1}' -f (Get-LocalizedText $prefix), $suffix
    }

    $text
}
