function Get-NetworkHealth {
    <#
    .SYNOPSIS
        Reports the network configuration and tests connectivity step by step.
    .DESCRIPTION
        Configuration (read from WMI, nothing is sent over the network):
        every active adapter with its IPv4 address, default gateway, DNS servers, MAC
        address and whether the address comes from DHCP, plus the proxy setting of
        the current user. An automatic 169.254.x.x address (APIPA) is reported as a
        Warning because it means no DHCP server answered.

        Connectivity tests, in the order a technician would troubleshoot:
        1. ping the default gateway  - is the local network working?
        2. ping a public IP address  - is there a route to the internet?
        3. resolve a host name       - is DNS working?
        4. HTTPS request             - can the computer actually reach a web site?

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

    New-CheckResult -Category $category -Check 'Proxy' -Status Info -Value (Get-ProxySetting)

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
    }
    else {
        New-CheckResult -Category $category -Check 'HTTPS access' -Status Critical `
            -Value ('{0} not reachable' -f $settings.HttpsTestUrl) `
            -Recommendation ('No web access. Check the proxy settings, the firewall and whether the network needs a sign-in page. Error: {0}' -f $https.Detail)
    }
}
