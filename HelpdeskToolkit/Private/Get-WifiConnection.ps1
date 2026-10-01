function Get-WifiConnection {
    <#
    .SYNOPSIS
        Returns the Wi-Fi network the computer is connected to, with signal strength and security.
    .DESCRIPTION
        Windows only tells this through "netsh wlan show interfaces", whose labels are
        translated on non-English Windows. The values, however, look the same in every
        language, so they are recognized by their shape instead of their label:

        - SSID:     the line whose label is "SSID" (never translated; "BSSID" is skipped)
        - Signal:   the only value that is a percentage
        - Radio:    a value like "802.11ax"
        - Band:     a value like "5 GHz" (reported by Windows 11)
        - Security: a value that names WPA3, WPA2, WPA or WEP; a connected network
                    without such a value is an open network

        Returns one object per connected Wi-Fi adapter with Ssid, SignalPercent, Radio,
        Band and Security, or nothing when there is no Wi-Fi connection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $lines = @(Invoke-NetshWlan)
    $current = $null

    # A blank line ends the block of one adapter.
    foreach ($line in ($lines + '')) {
        if ($line -match '^\s*([^:]+?)\s*:\s(.*)$') {
            if (-not $current) {
                $current = @{ Ssid = ''; SignalPercent = $null; Radio = ''; Band = ''; Security = '' }
            }
            $label = $Matches[1]
            $value = $Matches[2].Trim()

            if ($label -eq 'SSID') {
                $current.Ssid = $value
            }
            elseif ($value -match '^(\d{1,3})\s*%$') {
                $current.SignalPercent = [int]$Matches[1]
            }
            elseif ($value -match '^802\.11\w+$') {
                $current.Radio = $value
            }
            elseif ($value -match '^[\d.,]+\s*GHz$') {
                $current.Band = $value
            }
            elseif (-not $current.Security -and $value -match 'WPA3|WPA2|WPA|WEP') {
                $current.Security = $value
            }
        }
        elseif (-not $line.Trim() -and $current) {
            # Only a connected adapter has a network name and a signal.
            if ($current.Ssid -and $null -ne $current.SignalPercent) {
                if (-not $current.Security) {
                    $current.Security = 'Open'
                }
                [PSCustomObject]$current
            }
            $current = $null
        }
    }
}
