function Get-NetworkHealth {
    <#
    .SYNOPSIS
        Reports the network configuration and tests connectivity step by step.
    .DESCRIPTION
        Configuration (read from WMI, nothing is sent over the network):
        every active adapter with its IPv4 address, default gateway, DNS servers, MAC
        address, link speed and whether the address comes from DHCP, plus the proxy setting of
        the current user. An automatic 169.254.x.x address (APIPA) is reported as a
        Warning because it means no DHCP server answered.

        Connectivity tests, in the order a technician would troubleshoot:
        1. ping the default gateway  - is the local network working?
        2. ping a public IP address  - is there a route to the internet?
        3. resolve a host name       - is DNS working?
        4. HTTPS request             - can the computer actually reach a web site?

        The answer to the HTTPS request also carries the time of the server, which is
        used to check how accurate the clock of the computer is.

        Also reported: the Wi-Fi network in use with its signal strength and security
        (a weak signal or a badly protected network is a Warning), the network profile
        of each connection (Public, Private or Domain), active entries in the hosts
        file and permanently mapped network drives.

        The test targets are defined in Config\Thresholds.psd1. No administrator
        rights are needed.
    .PARAMETER SkipConnectivity
        Only report the adapter configuration and skip the four connectivity tests.
        Useful on computers that are offline on purpose, where the tests would only
        wait for timeouts.
    .EXAMPLE
        Get-NetworkHealth

        Reports the adapters and runs all connectivity tests.
    .EXAMPLE
        Get-NetworkHealth -SkipConnectivity

        Reports only the adapter configuration.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [switch]$SkipConnectivity
    )

    $category = 'Network'
    $settings = (Get-HealthThreshold).Network
    $gateway = $null

    try {
        $adapters = @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction Stop)

        if ($adapters.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Network adapters' -Status Critical -Value 'No active adapter' `
                -Recommendation 'Check the network cable or Wi-Fi connection and make sure the adapter is enabled in Settings > Network & internet.'
        }

        # Negotiated link speed of every connected adapter, by interface index. A gigabit
        # card that only reaches 100 Mbps usually points to a bad cable or switch port.
        $speeds = @{}
        try {
            foreach ($link in Get-CimInstance -ClassName Win32_NetworkAdapter -Filter 'NetEnabled = True' -ErrorAction Stop) {
                if ($link.Speed) {
                    $speeds[[int]$link.InterfaceIndex] = [double]$link.Speed
                }
            }
        }
        catch {
            Write-Verbose "Could not read the link speed: $($_.Exception.Message)"
        }

        foreach ($adapter in $adapters) {
            $ipv4 = @($adapter.IPAddress | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
            $gateways = @($adapter.DefaultIPGateway | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
            $dnsServers = @($adapter.DNSServerSearchOrder | Where-Object { $_ })

            if (-not $gateway -and $gateways.Count -gt 0) {
                $gateway = $gateways[0]
            }

            $parts = @(
                'IPv4: {0}' -f $(if ($ipv4.Count -gt 0) { $ipv4 -join ', ' } else { 'none' })
                'Gateway: {0}' -f $(if ($gateways.Count -gt 0) { $gateways -join ', ' } else { 'none' })
                'DNS: {0}' -f $(if ($dnsServers.Count -gt 0) { $dnsServers -join ', ' } else { 'none' })
                'DHCP: {0}' -f $(if ($adapter.DHCPEnabled) { 'Yes' } else { 'No' })
                'MAC: {0}' -f $(if ($adapter.MACAddress) { $adapter.MACAddress } else { 'none' })
            )

            $bitsPerSecond = $speeds[[int]$adapter.InterfaceIndex]
            if ($bitsPerSecond) {
                $speed = if ($bitsPerSecond -ge 1e9) {
                    '{0} Gbps' -f [string][math]::Round($bitsPerSecond / 1e9, 1)
                }
                else {
                    '{0} Mbps' -f [string][math]::Round($bitsPerSecond / 1e6)
                }
                $parts += 'Speed: {0}' -f $speed
            }

            $isApipa = @($ipv4 | Where-Object { $_ -like '169.254.*' }).Count -gt 0
            if ($isApipa) {
                $status = 'Warning'
                $recommendation = 'The adapter has an automatic 169.254.x.x address, so no DHCP server answered. Check the cable or Wi-Fi connection and the router.'
            }
            else {
                $status = 'Info'
                $recommendation = ''
            }

            New-CheckResult -Category $category -Check ('Adapter: {0}' -f $adapter.Description) -Status $status `
                -Value ($parts -join ' | ') -Recommendation $recommendation
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Network adapters' -ErrorRecord $_
    }

    # Wi-Fi: network name, signal strength and security. Only reported for a connected
    # Wi-Fi adapter; a computer on a cable has no such result.
    try {
        foreach ($wifi in @(Get-WifiConnection)) {
            $parts = @('{0} % signal' -f $wifi.SignalPercent)
            if ($wifi.Band) {
                $parts += $wifi.Band
            }
            if ($wifi.Radio) {
                $parts += $wifi.Radio
            }
            $parts += 'security: {0}' -f $wifi.Security

            $advice = @()
            $status = 'OK'
            # WEP and the first version of WPA can be broken within minutes; an open
            # network does not encrypt at all.
            if ($wifi.Security -eq 'Open' -or $wifi.Security -match 'WEP' -or $wifi.Security -match '^WPA(?![23])') {
                $status = 'Warning'
                $advice += 'This Wi-Fi network is not protected well: everybody nearby can read along or join it. Set the router to WPA2 or WPA3; on a public network, do not enter passwords on pages without https.'
            }
            if ($wifi.SignalPercent -lt $settings.WifiSignalWarningPercent) {
                $status = 'Warning'
                $advice += 'The Wi-Fi signal is weak, which makes the connection slow and unstable. Move closer to the router, remove obstacles between them, or use a cable.'
            }

            New-CheckResult -Category $category -Check ('Wi-Fi: {0}' -f $wifi.Ssid) -Status $status -Value ($parts -join ', ') `
                -Recommendation ($advice -join ' ') `
                -Allowed ('signal {0} - 100 %' -f $settings.WifiSignalWarningPercent) -Typical $settings.TypicalWifiSignal
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Wi-Fi' -ErrorRecord $_
    }

    # Network profile: decides which firewall profile applies to each connection.
    try {
        $categoryNames = @{ 0 = 'Public'; 1 = 'Private'; 2 = 'Domain' }
        $profiles = @(Get-CimInstance -Namespace 'root/StandardCimv2' -ClassName MSFT_NetConnectionProfile -ErrorAction Stop |
                ForEach-Object { '{0}: {1} ({2})' -f $_.InterfaceAlias, $categoryNames[[int]$_.NetworkCategory], $_.Name })
        $profileValue = if ($profiles.Count -gt 0) { $profiles -join ', ' } else { 'Not connected' }
        New-CheckResult -Category $category -Check 'Network profile' -Status Info -Value $profileValue
    }
    catch {
        New-FailureResult -Category $category -Check 'Network profile' -ErrorRecord $_
    }

    New-CheckResult -Category $category -Check 'Proxy' -Status Info -Value (Get-ProxySetting)

    # Hosts file: an entry there overrides DNS for that name.
    try {
        $hostEntries = @(Get-HostsFileEntry)
        if ($hostEntries.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Hosts file' -Status OK -Value 'No custom entries'
        }
        else {
            $shown = 3
            $remaining = @($hostEntries | Select-Object -Skip $shown)
            $value = '{0} custom entries: {1}' -f $hostEntries.Count, (($hostEntries | Select-Object -First $shown) -join ', ')
            if ($remaining.Count -gt 0) {
                $value = '{0} and {1} more' -f $value, $remaining.Count
            }
            New-CheckResult -Category $category -Check 'Hosts file' -Status Info -Value $value -Details $remaining `
                -Recommendation 'These names are not looked up in DNS but sent to the address written in the hosts file. If one of these sites does not open or shows the wrong content, remove its line from C:\Windows\System32\drivers\etc\hosts (needs administrator rights).'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Hosts file' -ErrorRecord $_
    }

    $mappedDrives = @(Get-MappedDrive)
    $mappedValue = if ($mappedDrives.Count -gt 0) { $mappedDrives -join ', ' } else { 'None' }
    New-CheckResult -Category $category -Check 'Mapped network drives' -Status Info -Value $mappedValue

    if ($SkipConnectivity) {
        New-CheckResult -Category $category -Check 'Connectivity tests' -Status Info -Value 'Skipped'
        return
    }

    # 1. Default gateway
    if ($gateway) {
        $ping = Test-PingHost -Target $gateway
        if ($ping.Success) {
            New-CheckResult -Category $category -Check 'Ping default gateway' -Status OK `
                -Value ('{0} replied in {1}' -f $gateway, $ping.Text) -Typical $settings.TypicalGatewayPing
        }
        else {
            New-CheckResult -Category $category -Check 'Ping default gateway' -Status Warning `
                -Value ('{0} did not reply' -f $gateway) `
                -Recommendation 'The router did not answer. Check the cable or Wi-Fi connection. If the tests below succeed, the router simply ignores ping.'
        }
    }
    else {
        New-CheckResult -Category $category -Check 'Ping default gateway' -Status Warning -Value 'No default gateway' `
            -Recommendation 'No adapter has a default gateway, so the computer cannot reach other networks. Check the IP settings or DHCP.'
    }

    # 2. Public IP address
    $ping = Test-PingHost -Target $settings.PingTarget
    if ($ping.Success) {
        $status = Get-ThresholdStatus -Value $ping.AverageMs -Warning $settings.PingWarningMs
        $recommendation = if ($status -ne 'OK') {
            'The connection responds slowly. Check the Wi-Fi signal and whether something on the network is using all the bandwidth.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Ping internet' -Status $status `
            -Value ('{0} replied in {1}' -f $settings.PingTarget, $ping.Text) -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $settings.PingWarningMs -Unit 'ms') -Typical $settings.TypicalInternetPing
    }
    else {
        New-CheckResult -Category $category -Check 'Ping internet' -Status Warning `
            -Value ('{0} did not reply' -f $settings.PingTarget) `
            -Recommendation 'No ping reply from the internet. Some networks block ping; the HTTPS test below shows whether the internet is really unreachable.'
    }

    # 3. DNS
    $addresses = @(Resolve-HostAddress -Name $settings.DnsTestName)
    if ($addresses.Count -gt 0) {
        New-CheckResult -Category $category -Check 'DNS resolution' -Status OK `
            -Value ('{0} -> {1}' -f $settings.DnsTestName, $addresses[0])
    }
    else {
        New-CheckResult -Category $category -Check 'DNS resolution' -Status Critical `
            -Value ('{0} could not be resolved' -f $settings.DnsTestName) `
            -Recommendation 'Names cannot be resolved, so web sites will not open even if the connection works. Check the DNS servers of the adapter and try "ipconfig /flushdns".'
    }

    # 4. HTTPS
    $https = Test-HttpsEndpoint -Uri $settings.HttpsTestUrl
    if ($https.Success) {
        New-CheckResult -Category $category -Check 'HTTPS access' -Status OK `
            -Value ('{0} reachable ({1})' -f $settings.HttpsTestUrl, $https.Detail)

        # Clock accuracy. Every web server states its current time in the answer, so the
        # request that was just made also tells how far the clock of this computer is off.
        if ($https.ServerTime) {
            $difference = [math]::Abs(([datetime]::UtcNow - $https.ServerTime).TotalSeconds)
            $status = Get-ThresholdStatus -Value $difference -Warning $settings.ClockWarningSeconds
            $differenceText = if ($difference -lt 60) {
                $seconds = [int][math]::Round($difference)
                '{0} second{1}' -f $seconds, $(if ($seconds -ne 1) { 's' })
            }
            else {
                '{0} minutes' -f [string][math]::Round($difference / 60, 1)
            }
            $recommendation = if ($status -ne 'OK') {
                'The clock of the computer is wrong, which breaks sign-in to company services and causes certificate errors in the browser. Open Settings > Time & language > Date & time and choose "Sync now".'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Clock accuracy' -Status $status `
                -Value ('Differs from internet time by {0}' -f $differenceText) -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $settings.ClockWarningSeconds -Unit 'seconds') -Typical $settings.TypicalClock
        }
    }
    else {
        New-CheckResult -Category $category -Check 'HTTPS access' -Status Critical `
            -Value ('{0} not reachable' -f $settings.HttpsTestUrl) `
            -Recommendation ('No web access. Check the proxy settings, the firewall and whether the network needs a sign-in page. Error: {0}' -f $https.Detail)
    }
}
