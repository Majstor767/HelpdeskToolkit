function Get-OSDisplayVersion {
    <#
    .SYNOPSIS
        Returns the Windows feature release (for example 24H2), or an empty string.
    .DESCRIPTION
        WMI only exposes the build number. The release name users and admins
        actually talk about is stored in the registry and is readable without
        administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    try {
        $properties = Get-ItemProperty -Path $key -ErrorAction Stop
        if ($properties.PSObject.Properties.Name -contains 'DisplayVersion') {
            return [string]$properties.DisplayVersion
        }
    }
    catch {
        Write-Verbose "Could not read the OS display version: $($_.Exception.Message)"
    }

    ''
}
