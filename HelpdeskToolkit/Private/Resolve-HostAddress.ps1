function Resolve-HostAddress {
    <#
    .SYNOPSIS
        Resolves a host name through DNS and returns its IP addresses; nothing on failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        [System.Net.Dns]::GetHostAddresses($Name) | ForEach-Object { $_.IPAddressToString }
    }
    catch {
        Write-Verbose "DNS resolution of $Name failed: $($_.Exception.Message)"
    }
}
