BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-NetworkHealth' {
    BeforeAll {
        # No test in this file sends anything over the network: the adapter data,
        # ping, DNS and HTTPS are all replaced with mocks.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance {
            [PSCustomObject]@{
                Description          = 'Contoso Ethernet'
                IPAddress            = @('10.20.30.57', 'fe80::1234')
                DefaultIPGateway     = @('10.20.30.1')
                DNSServerSearchOrder = @('10.20.30.10', '10.20.30.11')
                DHCPEnabled          = $true
                MACAddress           = '00:00:5E:00:53:2A'
                InterfaceIndex       = 7
            }
        }
        # The link speed comes from a second WMI class and is matched by interface index.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapter' } {
            [PSCustomObject]@{ InterfaceIndex = 7; Speed = 1000000000 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_NetConnectionProfile' } {
            [PSCustomObject]@{ InterfaceAlias = 'Ethernet'; NetworkCategory = 1; Name = 'Office' }
        }
        Mock -ModuleName HelpdeskToolkit Get-HostsFileEntry { }
        Mock -ModuleName HelpdeskToolkit Get-MappedDrive { }
        # Connected by cable: no Wi-Fi.
        Mock -ModuleName HelpdeskToolkit Get-WifiConnection { }
        Mock -ModuleName HelpdeskToolkit Get-ProxySetting { 'Not configured' }
        Mock -ModuleName HelpdeskToolkit Test-PingHost { [PSCustomObject]@{ Success = $true; AverageMs = 12; Text = '12 ms' } }
        Mock -ModuleName HelpdeskToolkit Resolve-HostAddress { '203.0.113.25' }
        # The server time is two seconds behind the clock of the computer.
        Mock -ModuleName HelpdeskToolkit Test-HttpsEndpoint { [PSCustomObject]@{ Success = $true; Detail = 'HTTP 200'; ServerTime = [datetime]::UtcNow.AddSeconds(-2) } }
    }

    Context 'with a working connection' {
        BeforeAll {
            $results = Get-NetworkHealth
        }

        It 'reports the adapter configuration with IPv4 addresses only' {
            $adapter = $results | Where-Object Check -eq 'Adapter: Contoso Ethernet'
            $adapter.Status | Should -Be 'Info'
            $adapter.Value | Should -Be 'IPv4: 10.20.30.57 | Gateway: 10.20.30.1 | DNS: 10.20.30.10, 10.20.30.11 | DHCP: Yes | MAC: 00:00:5E:00:53:2A | Speed: 1 Gbps'
        }

        It 'reports <Check> as OK with value "<Value>"' -ForEach @(
            @{ Check = 'Ping default gateway'; Value = '10.20.30.1 replied in 12 ms' }
            @{ Check = 'Ping internet'; Value = '192.0.2.1 replied in 12 ms' }
            @{ Check = 'DNS resolution'; Value = 'test.example -> 203.0.113.25' }
            @{ Check = 'HTTPS access'; Value = 'https://test.example reachable (HTTP 200)' }
        ) {
            $result = $results | Where-Object Check -eq $Check
            $result.Status | Should -Be 'OK'
            $result.Value | Should -Be $Value
        }

        It 'reports <Check> as <Status> with value "<Value>"' -ForEach @(
            @{ Check = 'Network profile'; Status = 'Info'; Value = 'Ethernet: Private (Office)' }
            @{ Check = 'Hosts file'; Status = 'OK'; Value = 'No custom entries' }
            @{ Check = 'Mapped network drives'; Status = 'Info'; Value = 'None' }
            @{ Check = 'Clock accuracy'; Status = 'OK'; Value = 'Differs from internet time by 2 seconds' }
        ) {
            $result = $results | Where-Object Check -eq $Check
            $result.Status | Should -Be $Status
            $result.Value | Should -Be $Value
        }

        It 'reports the proxy setting' {
            ($results | Where-Object Check -eq 'Proxy').Value | Should -Be 'Not configured'
        }

        It 'pings the gateway of the adapter and the configured internet target' {
            Should -Invoke -ModuleName HelpdeskToolkit Test-PingHost -Times 1 -Exactly -Scope Context -ParameterFilter { $Target -eq '10.20.30.1' }
            Should -Invoke -ModuleName HelpdeskToolkit Test-PingHost -Times 1 -Exactly -Scope Context -ParameterFilter { $Target -eq '192.0.2.1' }
        }

        It 'adds the allowed range and typical value to the internet ping' {
            $ping = $results | Where-Object Check -eq 'Ping internet'
            $ping.Allowed | Should -Be '0 - 150 ms'
            $ping.Typical | Should -Be 'typical internet'
        }
    }

    Context 'network profile, hosts file and mapped drives' {
        It 'names the profile of every connection' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_NetConnectionProfile' } {
                [PSCustomObject]@{ InterfaceAlias = 'Wi-Fi'; NetworkCategory = 0; Name = 'CafeGuest' }
                [PSCustomObject]@{ InterfaceAlias = 'Ethernet'; NetworkCategory = 2; Name = 'corp.test.example' }
            }
            (Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Network profile').Value |
                Should -Be 'Wi-Fi: Public (CafeGuest), Ethernet: Domain (corp.test.example)'
        }

        It 'says "Not connected" when no network is connected' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_NetConnectionProfile' } { }
            (Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Network profile').Value | Should -Be 'Not connected'
        }

        It 'lists entries of the hosts file with advice, the first three in the value' {
            Mock -ModuleName HelpdeskToolkit Get-HostsFileEntry { '10.0.0.5 intranet', '127.0.0.1 ads.test.example', '10.0.0.6 wiki', '10.0.0.7 mail' }
            $hosts = Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Hosts file'
            $hosts.Status | Should -Be 'Info'
            $hosts.Value | Should -Be '4 custom entries: 10.0.0.5 intranet, 127.0.0.1 ads.test.example, 10.0.0.6 wiki and 1 more'
            $hosts.Details | Should -Be @('10.0.0.7 mail')
            $hosts.Recommendation | Should -Match 'hosts'
        }

        It 'lists mapped network drives' {
            Mock -ModuleName HelpdeskToolkit Get-MappedDrive { 'S: -> \\fileserver\shared', 'Z: -> \\fileserver\home' }
            (Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Mapped network drives').Value |
                Should -Be 'S: -> \\fileserver\shared, Z: -> \\fileserver\home'
        }
    }

    Context 'clock accuracy' {
        It 'is a Warning when the clock is off by more than the limit' {
            Mock -ModuleName HelpdeskToolkit Test-HttpsEndpoint { [PSCustomObject]@{ Success = $true; Detail = 'HTTP 200'; ServerTime = [datetime]::UtcNow.AddMinutes(-7) } }
            $clock = Get-NetworkHealth | Where-Object Check -eq 'Clock accuracy'
            $clock.Status | Should -Be 'Warning'
            $clock.Value | Should -Be 'Differs from internet time by 7 minutes'
            $clock.Allowed | Should -Be '0 - 120 seconds'
            $clock.Recommendation | Should -Match 'Sync now'
        }

        It 'treats a clock that runs ahead the same as one that runs behind' {
            Mock -ModuleName HelpdeskToolkit Test-HttpsEndpoint { [PSCustomObject]@{ Success = $true; Detail = 'HTTP 200'; ServerTime = [datetime]::UtcNow.AddMinutes(10) } }
            (Get-NetworkHealth | Where-Object Check -eq 'Clock accuracy').Status | Should -Be 'Warning'
        }

        It 'is left out when the server did not report its time' {
            Mock -ModuleName HelpdeskToolkit Test-HttpsEndpoint { [PSCustomObject]@{ Success = $true; Detail = 'HTTP 403'; ServerTime = $null } }
            Get-NetworkHealth | Where-Object Check -eq 'Clock accuracy' | Should -BeNullOrEmpty
        }
    }

    Context 'link speed' {
        It 'shows <Bits> bits per second as "<Text>"' -ForEach @(
            @{ Bits = 100000000; Text = 'Speed: 100 Mbps' }
            @{ Bits = 2500000000; Text = 'Speed: 2.5 Gbps' }
            @{ Bits = 866700000; Text = 'Speed: 867 Mbps' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapter' } {
                [PSCustomObject]@{ InterfaceIndex = 7; Speed = $Bits }
            }
            (Get-NetworkHealth -SkipConnectivity | Where-Object Check -like 'Adapter:*').Value | Should -Match ([regex]::Escape($Text) + '$')
        }

        It 'still reports the adapter when the link speed cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_NetworkAdapter' } { throw 'Query failed' }
            $adapter = Get-NetworkHealth -SkipConnectivity | Where-Object Check -like 'Adapter:*'
            $adapter.Value | Should -Match 'MAC: 00:00:5E:00:53:2A$'
        }
    }

    Context 'with -SkipConnectivity' {
        BeforeAll {
            $results = Get-NetworkHealth -SkipConnectivity
        }

        It 'still reports the adapter and the proxy' {
            $results | Where-Object Check -like 'Adapter:*' | Should -Not -BeNullOrEmpty
            $results | Where-Object Check -eq 'Proxy' | Should -Not -BeNullOrEmpty
        }

        It 'reports the connectivity tests as skipped' {
            ($results | Where-Object Check -eq 'Connectivity tests').Value | Should -Be 'Skipped'
            $results | Where-Object Check -like 'Ping*' | Should -BeNullOrEmpty
        }

        It 'sends nothing over the network' {
            Should -Invoke -ModuleName HelpdeskToolkit Test-PingHost -Times 0 -Exactly -Scope Context
            Should -Invoke -ModuleName HelpdeskToolkit Resolve-HostAddress -Times 0 -Exactly -Scope Context
            Should -Invoke -ModuleName HelpdeskToolkit Test-HttpsEndpoint -Times 0 -Exactly -Scope Context
        }
    }

    Context 'when the adapter got no address from DHCP' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance {
                [PSCustomObject]@{
                    Description = 'Contoso Wi-Fi'; IPAddress = @('169.254.10.20'); DefaultIPGateway = $null
                    DNSServerSearchOrder = $null; DHCPEnabled = $true; MACAddress = $null; InterfaceIndex = 12
                }
            }
            $results = Get-NetworkHealth
        }

        It 'flags the automatic 169.254.x.x address as a Warning' {
            $adapter = $results | Where-Object Check -eq 'Adapter: Contoso Wi-Fi'
            $adapter.Status | Should -Be 'Warning'
            $adapter.Value | Should -Be 'IPv4: 169.254.10.20 | Gateway: none | DNS: none | DHCP: Yes | MAC: none'
            $adapter.Recommendation | Should -Match 'DHCP'
        }

        It 'warns that there is no default gateway instead of pinging one' {
            $gateway = $results | Where-Object Check -eq 'Ping default gateway'
            $gateway.Status | Should -Be 'Warning'
            $gateway.Value | Should -Be 'No default gateway'
        }
    }

    Context 'when there is no active adapter' {
        It 'reports that as Critical' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance { }
            $adapters = Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Network adapters'
            $adapters.Status | Should -Be 'Critical'
            $adapters.Value | Should -Be 'No active adapter'
        }
    }

    Context 'when the connection is down' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Test-PingHost { [PSCustomObject]@{ Success = $false; AverageMs = $null; Text = '' } }
            Mock -ModuleName HelpdeskToolkit Resolve-HostAddress { }
            Mock -ModuleName HelpdeskToolkit Test-HttpsEndpoint { [PSCustomObject]@{ Success = $false; Detail = 'Connection timed out'; ServerTime = $null } }
            $results = Get-NetworkHealth
        }

        It 'reports a missing ping reply only as a Warning, because ping is often blocked' {
            ($results | Where-Object Check -eq 'Ping default gateway').Status | Should -Be 'Warning'
            ($results | Where-Object Check -eq 'Ping internet').Status | Should -Be 'Warning'
        }

        It 'reports failed name resolution as Critical' {
            $dns = $results | Where-Object Check -eq 'DNS resolution'
            $dns.Status | Should -Be 'Critical'
            $dns.Value | Should -Be 'test.example could not be resolved'
        }

        It 'reports failed HTTPS access as Critical and includes the error' {
            $https = $results | Where-Object Check -eq 'HTTPS access'
            $https.Status | Should -Be 'Critical'
            $https.Recommendation | Should -Match 'Connection timed out'
        }
    }

    Context 'when the connection is slow' {
        It 'reports a high ping time to the internet as a Warning' {
            Mock -ModuleName HelpdeskToolkit Test-PingHost { [PSCustomObject]@{ Success = $true; AverageMs = 400; Text = '400 ms' } }
            $ping = Get-NetworkHealth | Where-Object Check -eq 'Ping internet'
            $ping.Status | Should -Be 'Warning'
            $ping.Recommendation | Should -Match 'slowly'
        }
    }

    Context 'when the adapter configuration cannot be read' {
        It 'reports it as unavailable' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'Query failed' }
            (Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Network adapters').Value | Should -Be 'Unavailable'
        }
    }

    Context 'Wi-Fi' {
        It 'reports nothing for a computer that is connected by cable' {
            Get-NetworkHealth -SkipConnectivity | Where-Object Check -like 'Wi-Fi*' | Should -BeNullOrEmpty
        }

        It 'reports the network with signal, band, standard and security' {
            Mock -ModuleName HelpdeskToolkit Get-WifiConnection {
                [PSCustomObject]@{ Ssid = 'Office'; SignalPercent = 87; Radio = '802.11ax'; Band = '5 GHz'; Security = 'WPA2-Personal' }
            }
            $wifi = Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Wi-Fi: Office'

            $wifi.Status | Should -Be 'OK'
            $wifi.Value | Should -Be '87 % signal, 5 GHz, 802.11ax, security: WPA2-Personal'
            $wifi.Allowed | Should -Be 'signal 40 - 100 %'
            $wifi.Typical | Should -Be 'typical wifi'
            $wifi.Description | Should -Not -BeNullOrEmpty
        }

        It 'leaves out the band and the standard when Windows does not report them' {
            Mock -ModuleName HelpdeskToolkit Get-WifiConnection {
                [PSCustomObject]@{ Ssid = 'Office'; SignalPercent = 60; Radio = ''; Band = ''; Security = 'WPA3-Personal' }
            }
            (Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Wi-Fi: Office').Value | Should -Be '60 % signal, security: WPA3-Personal'
        }

        It 'is a Warning when the signal is weak' {
            Mock -ModuleName HelpdeskToolkit Get-WifiConnection {
                [PSCustomObject]@{ Ssid = 'Office'; SignalPercent = 25; Radio = '802.11n'; Band = '2.4 GHz'; Security = 'WPA2-Personal' }
            }
            $wifi = Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Wi-Fi: Office'
            $wifi.Status | Should -Be 'Warning'
            $wifi.Recommendation | Should -Match 'signal is weak'
            $wifi.Recommendation | Should -Not -Match 'not protected'
        }

        It 'is a Warning on a network with the security "<Security>"' -ForEach @(
            @{ Security = 'Open' }
            @{ Security = 'WEP' }
            @{ Security = 'WPA-Personal' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-WifiConnection {
                [PSCustomObject]@{ Ssid = 'Cafe'; SignalPercent = 90; Radio = '802.11n'; Band = ''; Security = $Security }
            }
            $wifi = Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Wi-Fi: Cafe'
            $wifi.Status | Should -Be 'Warning'
            $wifi.Recommendation | Should -Match 'not protected well'
        }

        It 'gives both pieces of advice when the network is weak and badly protected' {
            Mock -ModuleName HelpdeskToolkit Get-WifiConnection {
                [PSCustomObject]@{ Ssid = 'Cafe'; SignalPercent = 20; Radio = ''; Band = ''; Security = 'Open' }
            }
            $wifi = Get-NetworkHealth -SkipConnectivity | Where-Object Check -eq 'Wi-Fi: Cafe'
            $wifi.Recommendation | Should -Match 'not protected well'
            $wifi.Recommendation | Should -Match 'signal is weak'
        }

        It 'reports Wi-Fi as unavailable when it cannot be read, and still reports the rest' {
            Mock -ModuleName HelpdeskToolkit Get-WifiConnection { throw 'The tool failed' }
            $results = Get-NetworkHealth -SkipConnectivity
            ($results | Where-Object Check -eq 'Wi-Fi').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Proxy').Value | Should -Be 'Not configured'
        }
    }
}
