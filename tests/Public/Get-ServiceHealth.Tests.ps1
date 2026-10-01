BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    # The test configuration monitors: Spooler, Dhcp, BITS and a service called Missing.
    Set-TestThreshold
}

Describe 'Get-ServiceHealth' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance {
            [PSCustomObject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; State = 'Running'; StartMode = 'Auto' }
            [PSCustomObject]@{ Name = 'Dhcp'; DisplayName = 'DHCP Client'; State = 'Running'; StartMode = 'Auto' }
            [PSCustomObject]@{ Name = 'BITS'; DisplayName = 'Background Intelligent Transfer Service'; State = 'Stopped'; StartMode = 'Manual' }
        }
        # The second query asks for every service that starts automatically.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $Filter -eq "StartMode = 'Auto'" } {
            [PSCustomObject]@{ DisplayName = 'Print Spooler'; State = 'Running'; PathName = "$env:SystemRoot\System32\spoolsv.exe" }
        }
    }

    Context 'with the services in their normal state' {
        BeforeAll {
            $results = Get-ServiceHealth
        }

        It 'returns one result per configured service, in the configured order' {
            $results.Check | Should -Be @(
                'Print Spooler (Spooler)'
                'DHCP Client (Dhcp)'
                'Background Intelligent Transfer Service (BITS)'
                'Missing'
                'Third-party services'
            )
        }

        It 'finds no service of another program' {
            ($results | Where-Object Check -eq 'Third-party services').Value | Should -Be '0 services'
        }

        It 'reports a running service as OK' {
            $spooler = $results | Where-Object Check -eq 'Print Spooler (Spooler)'
            $spooler.Status | Should -Be 'OK'
            $spooler.Value | Should -Be 'Running (start mode: Auto)'
        }

        It 'reports a stopped manual-start service as information, not as a problem' {
            $bits = $results | Where-Object Check -like '*(BITS)'
            $bits.Status | Should -Be 'Info'
            $bits.Value | Should -Be 'Stopped (start mode: Manual)'
            $bits.Recommendation | Should -Be ''
        }

        It 'reports a service that does not exist as "Not installed"' {
            $missing = $results | Where-Object Check -eq 'Missing'
            $missing.Status | Should -Be 'Info'
            $missing.Value | Should -Be 'Not installed'
        }

        It 'describes each service by its service name' {
            ($results | Where-Object Check -eq 'Print Spooler (Spooler)').Description | Should -Match 'print jobs'
            ($results | Where-Object Check -eq 'DHCP Client (Dhcp)').Description | Should -Match 'IP address'
        }

        It 'asks WMI for all configured services in a single query' {
            Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -Times 1 -Exactly -Scope Context -ParameterFilter {
                $ClassName -eq 'Win32_Service' -and $Filter -eq "Name = 'Spooler' OR Name = 'Dhcp' OR Name = 'BITS' OR Name = 'Missing'"
            }
        }
    }

    Context 'with services that should be running but are not' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance {
                [PSCustomObject]@{ Name = 'Spooler'; DisplayName = 'Print Spooler'; State = 'Stopped'; StartMode = 'Auto' }
                [PSCustomObject]@{ Name = 'Dhcp'; DisplayName = 'DHCP Client'; State = 'Stopped'; StartMode = 'Disabled' }
            }
            $results = Get-ServiceHealth
        }

        It 'reports a stopped automatic service as a Warning' {
            $spooler = $results | Where-Object Check -eq 'Print Spooler (Spooler)'
            $spooler.Status | Should -Be 'Warning'
            $spooler.Recommendation | Should -Match 'should start automatically'
        }

        It 'reports a disabled service as a Warning' {
            $dhcp = $results | Where-Object Check -eq 'DHCP Client (Dhcp)'
            $dhcp.Status | Should -Be 'Warning'
            $dhcp.Recommendation | Should -Match 'disabled'
        }
    }

    Context 'when the services cannot be queried' {
        It 'returns a single unavailable result' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'Query failed' }
            $results = @(Get-ServiceHealth)
            $results.Count | Should -Be 1
            $results[0].Value | Should -Be 'Unavailable'
        }
    }

    Context 'services installed by other programs' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $Filter -eq "StartMode = 'Auto'" } {
                [PSCustomObject]@{ DisplayName = 'Contoso Updater'; State = 'Stopped'; PathName = '"C:\Program Files\Contoso\updater.exe" --service' }
                [PSCustomObject]@{ DisplayName = 'Contoso Backup'; State = 'Running'; PathName = 'C:\Program Files\Contoso\backup.exe' }
                # Not listed: part of Windows, products of Microsoft outside the Windows
                # folder, and a service without a program path.
                [PSCustomObject]@{ DisplayName = 'Print Spooler'; State = 'Running'; PathName = "$env:SystemRoot\System32\spoolsv.exe" }
                [PSCustomObject]@{ DisplayName = 'Antivirus Service'; State = 'Running'; PathName = '"C:\ProgramData\Microsoft\Windows Defender\Platform\1.0\MsMpEng.exe"' }
                [PSCustomObject]@{ DisplayName = 'Browser Update'; State = 'Stopped'; PathName = '"C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe" /svc' }
                [PSCustomObject]@{ DisplayName = 'Store App Service'; State = 'Running'; PathName = 'C:\Program Files\WindowsApps\Microsoft.GamingServices_1.0\GamingServices.exe' }
                [PSCustomObject]@{ DisplayName = 'Driver Service'; State = 'Running'; PathName = $null }
            }
            $thirdParty = Get-ServiceHealth | Where-Object Check -eq 'Third-party services'
        }

        It 'lists only the services that do not belong to Windows or Microsoft' {
            $thirdParty.Status | Should -Be 'Info'
            $thirdParty.Value | Should -Be '2 services: Contoso Backup, Contoso Updater (not running)'
        }

        It 'reports them as unavailable when they cannot be read, and keeps the monitored services' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $Filter -eq "StartMode = 'Auto'" } { throw 'Query failed' }
            $results = Get-ServiceHealth
            ($results | Where-Object Check -eq 'Third-party services').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Print Spooler (Spooler)').Status | Should -Be 'OK'
        }
    }
}
