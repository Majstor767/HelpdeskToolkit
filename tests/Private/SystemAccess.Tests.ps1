# Tests for the small private functions that read the registry, WMI or the network.
# Everything they touch is replaced with a mock, so the tests give the same result
# on every computer.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
}

Describe 'Get-OSDisplayVersion' {
    It 'returns the DisplayVersion value from the registry' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ DisplayVersion = '24H2' } }
        InModuleScope HelpdeskToolkit { Get-OSDisplayVersion } | Should -Be '24H2'
    }

    It 'returns an empty string when the value does not exist (old Windows versions)' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ ProductName = 'Windows' } }
        InModuleScope HelpdeskToolkit { Get-OSDisplayVersion } | Should -Be ''
    }

    It 'returns an empty string when the registry cannot be read' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { throw 'Registry unavailable' }
        InModuleScope HelpdeskToolkit { Get-OSDisplayVersion } | Should -Be ''
    }
}

Describe 'Get-SecureBootState' {
    It 'returns Enabled when the registry value is 1' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ UEFISecureBootEnabled = 1 } }
        InModuleScope HelpdeskToolkit { Get-SecureBootState } | Should -Be 'Enabled'
    }

    It 'returns Disabled when the registry value is 0' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ UEFISecureBootEnabled = 0 } }
        InModuleScope HelpdeskToolkit { Get-SecureBootState } | Should -Be 'Disabled'
    }

    It 'returns Unsupported when the key does not exist (legacy BIOS)' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { throw 'Key not found' }
        InModuleScope HelpdeskToolkit { Get-SecureBootState } | Should -Be 'Unsupported'
    }
}

Describe 'Get-ProxySetting' {
    It 'reports a manual proxy' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ ProxyEnable = 1; ProxyServer = 'proxy.test.example:8080' } }
        InModuleScope HelpdeskToolkit { Get-ProxySetting } | Should -Be 'Manual proxy: proxy.test.example:8080'
    }

    It 'ignores a proxy server that is stored but switched off' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ ProxyEnable = 0; ProxyServer = 'proxy.test.example:8080' } }
        InModuleScope HelpdeskToolkit { Get-ProxySetting } | Should -Be 'Not configured'
    }

    It 'reports an automatic configuration script' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ ProxyEnable = 0; AutoConfigURL = 'http://test.example/proxy.pac' } }
        InModuleScope HelpdeskToolkit { Get-ProxySetting } | Should -Be 'Automatic configuration script: http://test.example/proxy.pac'
    }

    It 'reports Not configured when no proxy values exist' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ ProxyEnable = 0 } }
        InModuleScope HelpdeskToolkit { Get-ProxySetting } | Should -Be 'Not configured'
    }

    It 'reports Unknown when the registry cannot be read' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { throw 'Access denied' }
        InModuleScope HelpdeskToolkit { Get-ProxySetting } | Should -Be 'Unknown'
    }
}

Describe 'Get-PendingRebootReason' {
    It 'returns nothing when no reboot key exists' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        @(InModuleScope HelpdeskToolkit { Get-PendingRebootReason }).Count | Should -Be 0
    }

    It 'returns the reason of every key that exists' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
        InModuleScope HelpdeskToolkit { Get-PendingRebootReason } | Should -Be @('Windows Update', 'Component servicing')
    }

    It 'returns only Windows Update when only that key exists' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        Mock -ModuleName HelpdeskToolkit Test-Path -ParameterFilter { $Path -like '*WindowsUpdate*' } { $true }
        InModuleScope HelpdeskToolkit { Get-PendingRebootReason } | Should -Be @('Windows Update')
    }
}

Describe 'Get-AntivirusProduct' {
    It 'returns the display names registered in Security Center' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance {
            [PSCustomObject]@{ displayName = 'Windows Defender' }
            [PSCustomObject]@{ displayName = 'Contoso Antivirus' }
        }
        InModuleScope HelpdeskToolkit { Get-AntivirusProduct } | Should -Be @('Windows Defender', 'Contoso Antivirus')
    }

    It 'returns nothing when Security Center is not available (server editions)' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'Invalid namespace' }
        @(InModuleScope HelpdeskToolkit { Get-AntivirusProduct }).Count | Should -Be 0
    }
}

Describe 'Get-DefaultBrowserPath' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ ProgId = 'ContosoBrowserHTML' } }
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
    }

    It 'extracts the executable from a quoted command line' {
        Mock -ModuleName HelpdeskToolkit Get-Item {
            $key = [PSCustomObject]@{}
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { '"C:\Program Files\Contoso\browser.exe" --single-argument %1' }
            $key
        }
        InModuleScope HelpdeskToolkit { Get-DefaultBrowserPath } | Should -Be 'C:\Program Files\Contoso\browser.exe'
    }

    It 'extracts the executable from an unquoted command line' {
        Mock -ModuleName HelpdeskToolkit Get-Item {
            $key = [PSCustomObject]@{}
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { 'C:\Contoso\browser.exe -url %1' }
            $key
        }
        InModuleScope HelpdeskToolkit { Get-DefaultBrowserPath } | Should -Be 'C:\Contoso\browser.exe'
    }

    It 'returns nothing when the executable does not exist' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        Mock -ModuleName HelpdeskToolkit Get-Item {
            $key = [PSCustomObject]@{}
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { '"C:\Gone\browser.exe" %1' }
            $key
        }
        InModuleScope HelpdeskToolkit { Get-DefaultBrowserPath } | Should -BeNullOrEmpty
    }

    It 'returns nothing when no default browser is registered' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { throw 'Key not found' }
        InModuleScope HelpdeskToolkit { Get-DefaultBrowserPath } | Should -BeNullOrEmpty
    }
}

Describe 'Test-HttpsEndpoint' {
    It 'reports success with the status code when the request succeeds' {
        Mock -ModuleName HelpdeskToolkit Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200 } }
        $result = InModuleScope HelpdeskToolkit { Test-HttpsEndpoint -Uri 'https://test.example' }
        $result.Success | Should -BeTrue
        $result.Detail | Should -Be 'HTTP 200'
    }

    It 'still reports success when the server answers with an error status' {
        Mock -ModuleName HelpdeskToolkit Invoke-WebRequest {
            $exception = New-Object -TypeName System.Exception -ArgumentList 'Forbidden'
            $exception | Add-Member -NotePropertyName Response -NotePropertyValue ([PSCustomObject]@{ StatusCode = 403 })
            throw $exception
        }
        $result = InModuleScope HelpdeskToolkit { Test-HttpsEndpoint -Uri 'https://test.example' }
        $result.Success | Should -BeTrue
        $result.Detail | Should -Be 'HTTP 403'
    }

    It 'reports failure with the error text when there is no answer at all' {
        Mock -ModuleName HelpdeskToolkit Invoke-WebRequest { throw 'The remote name could not be resolved' }
        $result = InModuleScope HelpdeskToolkit { Test-HttpsEndpoint -Uri 'https://test.example' }
        $result.Success | Should -BeFalse
        $result.Detail | Should -Be 'The remote name could not be resolved'
    }

    It 'sends a HEAD request, so no page content is downloaded' {
        Mock -ModuleName HelpdeskToolkit Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200 } }
        InModuleScope HelpdeskToolkit { Test-HttpsEndpoint -Uri 'https://test.example' } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'Head' }
    }
}

Describe 'Test-PingHost' {
    # The .NET Ping class cannot be mocked, so this uses the loopback address,
    # which answers on every computer without leaving the machine.
    It 'reports success and a response time for the loopback address' {
        $result = InModuleScope HelpdeskToolkit { Test-PingHost -Target '127.0.0.1' -Count 1 }
        $result.Success | Should -BeTrue
        $result.Text | Should -Not -BeNullOrEmpty
    }

    It 'reports failure instead of throwing for a name that cannot exist' {
        $result = InModuleScope HelpdeskToolkit { Test-PingHost -Target 'host.invalid' -Count 1 -TimeoutMs 500 }
        $result.Success | Should -BeFalse
        $result.AverageMs | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-HostAddress' {
    It 'returns at least one address for localhost' {
        @(InModuleScope HelpdeskToolkit { Resolve-HostAddress -Name 'localhost' }).Count | Should -BeGreaterThan 0
    }

    It 'returns nothing instead of throwing for a name that cannot exist' {
        @(InModuleScope HelpdeskToolkit { Resolve-HostAddress -Name 'host.invalid' }).Count | Should -Be 0
    }
}

Describe 'Get-RegistryValue' {
    It 'returns the value when it exists' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ EnableLUA = 1 } }
        InModuleScope HelpdeskToolkit { Get-RegistryValue -Path 'HKLM:\Test' -Name 'EnableLUA' } | Should -Be 1
    }

    It 'returns a value of 0 as 0, not as "missing"' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ EnableLUA = 0 } }
        $value = InModuleScope HelpdeskToolkit { Get-RegistryValue -Path 'HKLM:\Test' -Name 'EnableLUA' }
        $value | Should -Be 0
        $null -eq $value | Should -BeFalse
    }

    It 'returns nothing when the value does not exist' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { [PSCustomObject]@{ Other = 1 } }
        InModuleScope HelpdeskToolkit { Get-RegistryValue -Path 'HKLM:\Test' -Name 'EnableLUA' } | Should -BeNullOrEmpty
    }

    It 'returns nothing when the key cannot be read' {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty { throw 'Key not found' }
        InModuleScope HelpdeskToolkit { Get-RegistryValue -Path 'HKLM:\Test' -Name 'EnableLUA' } | Should -BeNullOrEmpty
    }
}

Describe 'Get-InstalledProgram' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty {
            [PSCustomObject]@{ DisplayName = ' Contoso Office '; DisplayVersion = '16.0'; InstallDate = '20260110' }
            # Registered a second time under another key: must be returned once.
            [PSCustomObject]@{ DisplayName = ' Contoso Office '; DisplayVersion = '16.0'; InstallDate = '20260110' }
            [PSCustomObject]@{ DisplayName = 'Archive Tool' }
            [PSCustomObject]@{ DisplayName = 'Windows Component'; SystemComponent = 1 }
            [PSCustomObject]@{ DisplayVersion = '1.0' }
            [PSCustomObject]@{ DisplayName = 'Broken Date'; InstallDate = '00000000' }
        }
        $programs = @(InModuleScope HelpdeskToolkit { Get-InstalledProgram })
    }

    It 'returns each program once' {
        @($programs | Where-Object Name -eq 'Contoso Office').Count | Should -Be 1
    }

    It 'skips entries without a name and system components' {
        $programs.Name | Should -Be @('Contoso Office', 'Archive Tool', 'Broken Date')
    }

    It 'reads the version and converts the install date' {
        $office = $programs | Where-Object Name -eq 'Contoso Office'
        $office.Version | Should -Be '16.0'
        $office.InstallDate | Should -Be ([datetime]'2026-01-10')
    }

    It 'leaves the version and the date empty when the installer did not store them' {
        $tool = $programs | Where-Object Name -eq 'Archive Tool'
        $tool.Version | Should -Be ''
        $tool.InstallDate | Should -BeNullOrEmpty
    }

    It 'ignores an install date that is not a real date' {
        ($programs | Where-Object Name -eq 'Broken Date').InstallDate | Should -BeNullOrEmpty
    }
}

Describe 'Get-FileProductName' {
    It 'returns the product name stored in a program file' {
        $path = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        InModuleScope HelpdeskToolkit -Parameters @{ Path = $path } { Get-FileProductName -Path $Path } | Should -Match 'Windows'
    }

    It 'falls back to the file name when the file cannot be read' {
        InModuleScope HelpdeskToolkit { Get-FileProductName -Path 'C:\NoSuchFolder\browser.exe' } | Should -Be 'browser'
    }
}

Describe 'Test-IsAdministratorMember' {
    It 'returns a boolean' {
        InModuleScope HelpdeskToolkit { Test-IsAdministratorMember } | Should -BeOfType [bool]
    }

    It 'is true whenever the session is elevated' {
        $elevated = InModuleScope HelpdeskToolkit { Test-IsAdministrator }
        $member = InModuleScope HelpdeskToolkit { Test-IsAdministratorMember }
        if ($elevated) {
            $member | Should -BeTrue
        }
        else {
            # Not elevated: the user may or may not be an administrator; both are valid.
            $member | Should -BeIn @($true, $false)
        }
    }
}

Describe 'Test-HttpsEndpoint server time' {
    It 'returns the time from the Date header in UTC' {
        Mock -ModuleName HelpdeskToolkit Invoke-WebRequest {
            [PSCustomObject]@{ StatusCode = 200; Headers = @{ Date = 'Thu, 15 Jan 2026 10:30:00 GMT' } }
        }
        $result = InModuleScope HelpdeskToolkit { Test-HttpsEndpoint -Uri 'https://test.example' }
        $result.ServerTime | Should -Be ([datetime]::new(2026, 1, 15, 10, 30, 0, [System.DateTimeKind]::Utc))
        $result.ServerTime.Kind | Should -Be 'Utc'
    }

    It 'accepts the header as a list of strings, as PowerShell 7 returns it' {
        Mock -ModuleName HelpdeskToolkit Invoke-WebRequest {
            [PSCustomObject]@{ StatusCode = 200; Headers = @{ Date = [string[]]@('Thu, 15 Jan 2026 10:30:00 GMT') } }
        }
        (InModuleScope HelpdeskToolkit { Test-HttpsEndpoint -Uri 'https://test.example' }).ServerTime.Hour | Should -Be 10
    }

    It 'returns no server time when the header is missing or unreadable' {
        Mock -ModuleName HelpdeskToolkit Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Headers = @{ Date = 'not a date' } } }
        $result = InModuleScope HelpdeskToolkit { Test-HttpsEndpoint -Uri 'https://test.example' }
        $result.Success | Should -BeTrue
        $result.ServerTime | Should -BeNullOrEmpty
    }
}

Describe 'Get-FolderSize' {
    BeforeAll {
        # A small folder tree with known sizes: 1000 + 2000 + 500 bytes in 3 files.
        $folder = Join-Path -Path $TestDrive -ChildPath 'sizes'
        New-Item -Path (Join-Path -Path $folder -ChildPath 'sub\deeper') -ItemType Directory -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path -Path $folder -ChildPath 'a.bin'), (New-Object -TypeName byte[] -ArgumentList 1000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $folder -ChildPath 'sub\b.bin'), (New-Object -TypeName byte[] -ArgumentList 2000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $folder -ChildPath 'sub\deeper\c.bin'), (New-Object -TypeName byte[] -ArgumentList 500))
    }

    It 'adds up the files of the folder and all subfolders' {
        $size = InModuleScope HelpdeskToolkit -Parameters @{ Path = $folder } { Get-FolderSize -Path $Path }
        $size.Bytes | Should -Be 3500
        $size.FileCount | Should -Be 3
        $size.Complete | Should -BeTrue
    }

    It 'returns zero for a folder that does not exist' {
        $size = InModuleScope HelpdeskToolkit { Get-FolderSize -Path 'C:\NoSuchFolder\Nowhere' }
        $size.Bytes | Should -Be 0
        $size.Complete | Should -BeTrue
    }

    It 'stops at the time limit and says the result is incomplete' {
        $size = InModuleScope HelpdeskToolkit -Parameters @{ Path = $folder } { Get-FolderSize -Path $Path -TimeoutMs 0 }
        $size.Complete | Should -BeFalse
    }
}

Describe 'Get-RecycleBinSize' {
    It 'adds up the Recycle Bin folders of all fixed drives' {
        Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 100; FileCount = 1; Complete = $true } }
        $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady }).Count

        $bin = InModuleScope HelpdeskToolkit { Get-RecycleBinSize }
        $bin.Bytes | Should -Be (100 * $drives)
        $bin.Complete | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Get-FolderSize -Times $drives -Exactly -ParameterFilter { $Path -like '*$Recycle.Bin\S-1-*' }
    }

    It 'is incomplete when one drive could not be measured in time' {
        Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 100; FileCount = 1; Complete = $false } }
        (InModuleScope HelpdeskToolkit { Get-RecycleBinSize }).Complete | Should -BeFalse
    }
}

Describe 'Get-HostsFileEntry' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
    }

    It 'returns only active entries, with single spaces' {
        Mock -ModuleName HelpdeskToolkit Get-Content {
            '# Copyright (c) Microsoft Corp.'
            ''
            '   # 127.0.0.1 localhost'
            "10.0.0.5`t`tintranet.test.example"
            '  127.0.0.1    ads.test.example  '
        }
        InModuleScope HelpdeskToolkit { Get-HostsFileEntry } | Should -Be @('10.0.0.5 intranet.test.example', '127.0.0.1 ads.test.example')
    }

    It 'returns nothing for the file as Windows ships it (comments only)' {
        Mock -ModuleName HelpdeskToolkit Get-Content { '# comment'; '#'; '' }
        @(InModuleScope HelpdeskToolkit { Get-HostsFileEntry }).Count | Should -Be 0
    }

    It 'returns nothing when the file does not exist' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        @(InModuleScope HelpdeskToolkit { Get-HostsFileEntry }).Count | Should -Be 0
    }
}

Describe 'Get-MappedDrive' {
    It 'returns every mapped drive with its network path' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
        Mock -ModuleName HelpdeskToolkit Get-ChildItem {
            foreach ($drive in @{ Letter = 'z'; Target = '\\fileserver\home' }, @{ Letter = 's'; Target = '\\fileserver\shared' }) {
                $key = [PSCustomObject]@{ PSChildName = $drive.Letter; Target = $drive.Target }
                $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { $this.Target }
                $key
            }
        }
        InModuleScope HelpdeskToolkit { Get-MappedDrive } | Should -Be @('Z: -> \\fileserver\home', 'S: -> \\fileserver\shared')
    }

    It 'returns nothing when no drive is mapped' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        @(InModuleScope HelpdeskToolkit { Get-MappedDrive }).Count | Should -Be 0
    }
}

Describe 'Get-VideoMemory' {
    BeforeAll {
        # A registry key of a display adapter: GetValue returns the named value or nothing.
        function New-TestAdapterKey {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([hashtable]$Values)

            $key = [PSCustomObject]@{ Values = $Values }
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($Name) $this.Values[$Name] }
            $key
        }
    }

    It 'returns the name and the 64-bit memory size the driver stored' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem {
            New-TestAdapterKey -Values @{ DriverDesc = 'Contoso Graphics 770'; 'HardwareInformation.qwMemorySize' = 12GB }
        }
        $adapter = InModuleScope HelpdeskToolkit { Get-VideoMemory }

        $adapter.Name | Should -Be 'Contoso Graphics 770'
        $adapter.Bytes | Should -Be 12GB
        $adapter.Bytes | Should -BeOfType [long]
    }

    It 'leaves out adapters whose driver does not store the size, and subkeys that are not adapters' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem {
            New-TestAdapterKey -Values @{ DriverDesc = 'Basic Display Adapter' }
            New-TestAdapterKey -Values @{ }
            New-TestAdapterKey -Values @{ DriverDesc = 'Contoso Graphics 770'; 'HardwareInformation.qwMemorySize' = 8GB }
        }
        @(InModuleScope HelpdeskToolkit { Get-VideoMemory }).Name | Should -Be 'Contoso Graphics 770'
    }

    It 'returns nothing when the registry key cannot be read' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem { }
        @(InModuleScope HelpdeskToolkit { Get-VideoMemory }).Count | Should -Be 0
    }
}
