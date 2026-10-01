BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-ComputerSpecification' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }

        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
            [PSCustomObject]@{ Name = ' Contoso Core 8 '; NumberOfCores = 8; NumberOfLogicalProcessors = 16; MaxClockSpeed = 2400 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' } {
            [PSCustomObject]@{ Capacity = 8GB; Speed = 2666; ConfiguredClockSpeed = 3200; SMBIOSMemoryType = 26 }
            [PSCustomObject]@{ Capacity = 8GB; Speed = 2666; ConfiguredClockSpeed = 3200; SMBIOSMemoryType = 26 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemoryArray' } {
            [PSCustomObject]@{ MemoryDevices = 4 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_VideoController' } {
            [PSCustomObject]@{
                Name = 'Contoso Graphics 770'; DriverVersion = '31.0.101'
                CurrentHorizontalResolution = 1920; CurrentVerticalResolution = 1080; CurrentRefreshRate = 60
            }
        }
        # Monitors describe themselves with character codes, padded with zeros.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'WmiMonitorID' } {
            [PSCustomObject]@{
                UserFriendlyName  = [uint16[]](@([char[]]'Contoso 27Q' | ForEach-Object { [int]$_ }) + 0, 0)
                ManufacturerName  = [uint16[]](@([char[]]'CTS' | ForEach-Object { [int]$_ }) + 0)
                YearOfManufacture = 2024
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BaseBoard' } {
            [PSCustomObject]@{ Manufacturer = 'Contoso'; Product = 'MB-100' }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } {
            [PSCustomObject]@{ Manufacturer = 'Contoso'; SMBIOSBIOSVersion = '1.14.2'; ReleaseDate = [datetime]'2025-03-18'; SerialNumber = ' CNT4012XYZ ' }
        }
    }

    Context 'on a typical computer' {
        BeforeAll {
            $results = Get-ComputerSpecification
        }

        It 'returns informational results in the Specifications category' {
            $results.Category | Sort-Object -Unique | Should -Be 'Specifications'
            $results.Status | Sort-Object -Unique | Should -Be 'Info'
        }

        It 'reports <Check> as "<Value>"' -ForEach @(
            @{ Check = 'Processor'; Value = 'Contoso Core 8, 8 cores / 16 threads, 2.4 GHz' }
            @{ Check = 'Memory'; Value = '16 GB (2 x 8 GB DDR4, 3200 MHz), 2 of 4 slots used' }
            @{ Check = 'Graphics'; Value = 'Contoso Graphics 770 (driver 31.0.101), 1920 x 1080 @ 60 Hz' }
            @{ Check = 'Display'; Value = 'Contoso 27Q (CTS, 2024)' }
            @{ Check = 'Motherboard'; Value = 'Contoso MB-100' }
            @{ Check = 'Serial number'; Value = 'CNT4012XYZ' }
        ) {
            ($results | Where-Object Check -eq $Check).Value | Should -Be $Value
        }

        It 'reports the BIOS version and release date' {
            ($results | Where-Object Check -eq 'BIOS').Value | Should -Match '^Contoso 1\.14\.2 \(2025-03-18\)'
        }
    }

    Context 'with memory modules of different sizes' {
        It 'lists each module and uses the default speed when no configured speed is reported' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' } {
                [PSCustomObject]@{ Capacity = 8GB; Speed = 2666; ConfiguredClockSpeed = $null; SMBIOSMemoryType = 26 }
                [PSCustomObject]@{ Capacity = 4GB; Speed = 2400; ConfiguredClockSpeed = $null; SMBIOSMemoryType = 26 }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Memory').Value |
                Should -Be '12 GB (8 GB + 4 GB DDR4, 2666 MHz), 2 of 4 slots used'
        }
    }

    Context 'on a virtual machine without module information' {
        It 'says that no module information is available' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' } { }
            (Get-ComputerSpecification | Where-Object Check -eq 'Memory').Value | Should -Be 'No module information available'
        }
    }

    Context 'with a graphics adapter that has no display connected' {
        It 'reports the adapter without a resolution' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_VideoController' } {
                [PSCustomObject]@{
                    Name = 'Contoso GPU'; DriverVersion = '1.0'
                    CurrentHorizontalResolution = $null; CurrentVerticalResolution = $null; CurrentRefreshRate = $null
                }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Graphics').Value | Should -Be 'Contoso GPU (driver 1.0)'
        }
    }

    Context 'displays' {
        It 'returns one result per connected display' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'WmiMonitorID' } {
                foreach ($name in 'Display A', 'Display B') {
                    [PSCustomObject]@{
                        UserFriendlyName  = [uint16[]](@([char[]]$name | ForEach-Object { [int]$_ }))
                        ManufacturerName  = [uint16[]](@([char[]]'CTS' | ForEach-Object { [int]$_ }))
                        YearOfManufacture = 2023
                    }
                }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Display').Value | Should -Be @('Display A (CTS, 2023)', 'Display B (CTS, 2023)')
        }

        It 'names a display that does not report a name' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'WmiMonitorID' } {
                [PSCustomObject]@{ UserFriendlyName = $null; ManufacturerName = $null; YearOfManufacture = $null }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Display').Value | Should -Be 'Built-in or generic display'
        }

        It 'leaves the displays out, without an error, where Windows has no monitor information' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'WmiMonitorID' } { throw 'Not supported' }
            $results = Get-ComputerSpecification
            $results | Where-Object Check -eq 'Display' | Should -BeNullOrEmpty
            $results | Where-Object Value -eq 'Unavailable' | Should -BeNullOrEmpty
        }
    }

    Context 'with a placeholder serial number' {
        It 'reports "<Serial>" as not set by the manufacturer' -ForEach @(
            @{ Serial = 'To Be Filled By O.E.M.' }
            @{ Serial = 'Default string' }
            @{ Serial = '' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } {
                [PSCustomObject]@{ Manufacturer = 'Contoso'; SMBIOSBIOSVersion = '1.0'; ReleaseDate = $null; SerialNumber = $Serial }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Serial number').Value | Should -Be 'Not set by the manufacturer'
        }
    }

    Context 'when one component cannot be read' {
        It 'reports that component as unavailable and still returns the others' {
            # Monitors describe themselves with character codes, padded with zeros.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'WmiMonitorID' } {
            [PSCustomObject]@{
                UserFriendlyName  = [uint16[]](@([char[]]'Contoso 27Q' | ForEach-Object { [int]$_ }) + 0, 0)
                ManufacturerName  = [uint16[]](@([char[]]'CTS' | ForEach-Object { [int]$_ }) + 0)
                YearOfManufacture = 2024
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BaseBoard' } { throw 'Query failed' }
            $results = Get-ComputerSpecification
            ($results | Where-Object Check -eq 'Motherboard').Status | Should -Be 'Warning'
            ($results | Where-Object Check -eq 'Processor').Status | Should -Be 'Info'
        }
    }
}
