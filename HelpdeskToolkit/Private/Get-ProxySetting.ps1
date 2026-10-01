function Get-ProxySetting {
    <#
    .SYNOPSIS
        Returns the proxy configuration of the current user as text.
    .DESCRIPTION
        A forgotten proxy setting is a classic reason for "the internet does not work
        in the browser although the network is fine". The setting is stored per user
        in the registry.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    try {
        $settings = Get-ItemProperty -Path $key -ErrorAction Stop
        $names = $settings.PSObject.Properties.Name

        if ($names -contains 'ProxyEnable' -and $settings.ProxyEnable -eq 1 -and
            $names -contains 'ProxyServer' -and $settings.ProxyServer) {
            return 'Manual proxy: {0}' -f $settings.ProxyServer
        }

        if ($names -contains 'AutoConfigURL' -and $settings.AutoConfigURL) {
            return 'Automatic configuration script: {0}' -f $settings.AutoConfigURL
        }
    }
    catch {
        Write-Verbose "Could not read the proxy settings: $($_.Exception.Message)"
        return 'Unknown'
    }

    'Not configured'
}
