function Get-RegistryValue {
    <#
    .SYNOPSIS
        Returns one value from the registry; nothing when the key or the value is missing.
    .DESCRIPTION
        Several checks only need a single registry value (is UAC on, is Remote Desktop
        allowed, are updates paused). Reading it through one small function keeps
        those checks short and gives the tests one command to replace.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        $item = Get-ItemProperty -Path $Path -ErrorAction Stop
        if ($item.PSObject.Properties.Name -contains $Name) {
            return $item.$Name
        }
    }
    catch {
        Write-Verbose "Could not read $Name from ${Path}: $($_.Exception.Message)"
    }
}
