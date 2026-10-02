BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    # One RAM module as Win32_PhysicalMemory reports it.
    function New-TestMemoryModule {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param(
            [string]$Slot,
            [long]$Capacity = 8GB,
            [int]$Speed = 2666,
            $ConfiguredSpeed = 3200,
            [string]$Manufacturer = 'Contoso',
            [string]$PartNumber = 'CT8G4-3200   '
        )

        [PSCustomObject]@{
            DeviceLocator = $Slot; Capacity = $Capacity; Speed = $Speed; ConfiguredClockSpeed = $ConfiguredSpeed
            SMBIOSMemoryType = 26; Manufacturer = $Manufacturer; PartNumber = $PartNumber
        }
    }
}

Describe 'Get-ComputerSpecification' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }

        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
            [PSCustomObject]@{
                Name = ' Contoso Core 8 '; NumberOfCores = 8; NumberOfLogicalProcessors = 16; MaxClockSpeed = 2400
                L2CacheSize = 4096; L3CacheSize = 16896; AddressWidth = 64; VirtualizationFirmwareEnabled = $true
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
            [PSCustomObject]@{ HypervisorPresent = $false; Manufacturer = 'Contoso' }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' } {
            New-TestMemoryModule -Slot 'DIMM A1'
            New-TestMemoryModule -Slot 'DIMM B1'
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemoryArray' } {
            [PSCustomObject]@{ MemoryDevices = 4 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_VideoController' } {
            [PSCustomObject]@{
                Name = 'Contoso Graphics 770'; DriverVersion = '31.0.101'; DriverDate = [datetime]'2025-11-03'
                CurrentHorizontalResolution = 1920; CurrentVerticalResolution = 1080; CurrentRefreshRate = 60
            }
        }
        # The real amount of graphics memory comes from the registry of the test computer otherwise.
        Mock -ModuleName HelpdeskToolkit Get-VideoMemory { }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' } {
            [PSCustomObject]@{ DeviceId = '1'; FriendlyName = 'Contoso HD 2000 '; MediaType = 3; BusType = 11; Size = 2000GB; FirmwareVersion = 'A1 ' }
            [PSCustomObject]@{ DeviceId = '0'; FriendlyName = 'Contoso SSD 512'; MediaType = 4; BusType = 17; Size = 512GB; FirmwareVersion = 'FW2.1' }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_CDROMDrive' } { }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_SoundDevice' } {
            [PSCustomObject]@{ Name = 'Contoso HD Audio'; PNPDeviceID = 'HDAUDIO\FUNC_01&VEN_0000\1' }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Keyboard' } {
            [PSCustomObject]@{ Description = 'Contoso Keyboard K1' }
            [PSCustomObject]@{ Description = 'HID Keyboard Device' }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PointingDevice' } {
            [PSCustomObject]@{ Name = 'Contoso Mouse M1' }
            [PSCustomObject]@{ Name = 'USB Input Device' }
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
            @{ Check = 'Processor details'; Value = 'L2 cache 4 MB, L3 cache 16.5 MB, 64-bit, virtualization enabled in firmware' }
            @{ Check = 'Memory'; Value = '16 GB (2 x 8 GB DDR4, 3200 MHz), 2 of 4 slots used' }
            @{ Check = 'Graphics'; Value = 'Contoso Graphics 770 (driver 31.0.101 from 2025-11-03), 1920 x 1080 @ 60 Hz' }
            @{ Check = 'Audio devices'; Value = 'Contoso HD Audio' }
            @{ Check = 'Input devices'; Value = 'Contoso Keyboard K1, Contoso Mouse M1' }
            @{ Check = 'Display'; Value = 'Contoso 27Q (CTS, 2024)' }
            @{ Check = 'Motherboard'; Value = 'Contoso MB-100' }
            @{ Check = 'Serial number'; Value = 'CNT4012XYZ' }
        ) {
            ($results | Where-Object Check -eq $Check).Value | Should -Be $Value
        }

        It 'reports the BIOS version and release date' {
            ($results | Where-Object Check -eq 'BIOS').Value | Should -Match '^Contoso 1\.14\.2 \(2025-03-18\)'
        }

        It 'lists every memory module with its slot, speed, manufacturer and part number' {
            ($results | Where-Object Check -eq 'Memory module').Value | Should -Be @(
                'DIMM A1: 8 GB DDR4, 3200 MHz, Contoso CT8G4-3200'
                'DIMM B1: 8 GB DDR4, 3200 MHz, Contoso CT8G4-3200'
            )
        }

        It 'lists every physical drive in the order of its number, with type and firmware' {
            ($results | Where-Object Check -eq 'Storage').Value | Should -Be @(
                'Contoso SSD 512, 512 GB SSD (NVMe), firmware FW2.1'
                'Contoso HD 2000, 2000 GB HDD (SATA), firmware A1'
            )
        }

        It 'shows no optical drive row when the computer has none' {
            $results | Where-Object Check -eq 'Optical drive' | Should -BeNullOrEmpty
        }

        It 'has a description for every row' {
            $results | Where-Object { -not $_.Description } | Should -BeNullOrEmpty
        }
    }

    Context 'processor details' {
        It 'says that virtualization is in use when a hypervisor hides the firmware setting' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
                [PSCustomObject]@{
                    Name = 'Contoso Core 8'; NumberOfCores = 8; NumberOfLogicalProcessors = 16; MaxClockSpeed = 2400
                    L2CacheSize = 512; L3CacheSize = 0; AddressWidth = 64; VirtualizationFirmwareEnabled = $false
                }
            }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
                [PSCustomObject]@{ HypervisorPresent = $true }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Processor details').Value |
                Should -Be 'L2 cache 512 KB, 64-bit, virtualization in use by a hypervisor'
        }

        It 'says that virtualization is disabled when neither the firmware nor a hypervisor reports it' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
                [PSCustomObject]@{
                    Name = 'Contoso Core 8'; NumberOfCores = 8; NumberOfLogicalProcessors = 16; MaxClockSpeed = 2400
                    L2CacheSize = 4096; L3CacheSize = 16384; AddressWidth = 64; VirtualizationFirmwareEnabled = $false
                }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Processor details').Value | Should -Match 'virtualization disabled in firmware$'
        }

        It 'is left out when the processor itself cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } { throw 'Query failed' }
            $results = Get-ComputerSpecification
            ($results | Where-Object Check -eq 'Processor').Status | Should -Be 'Warning'
            $results | Where-Object Check -eq 'Processor details' | Should -BeNullOrEmpty
        }
    }

    Context 'graphics memory' {
        It 'shows the amount the driver reports, which can be more than the 4 GB limit of WMI' {
            Mock -ModuleName HelpdeskToolkit Get-VideoMemory {
                [PSCustomObject]@{ Name = 'Contoso Graphics 770'; Bytes = 12GB }
                [PSCustomObject]@{ Name = 'Some Other Adapter'; Bytes = 2GB }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Graphics').Value |
                Should -Be 'Contoso Graphics 770, 12 GB memory (driver 31.0.101 from 2025-11-03), 1920 x 1080 @ 60 Hz'
        }
    }

    Context 'optical drives' {
        It 'reports a drive with its drive letter' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_CDROMDrive' } {
                [PSCustomObject]@{ Name = 'Contoso DVD-RW'; Drive = 'E:' }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Optical drive').Value | Should -Be 'Contoso DVD-RW (E:)'
        }
    }

    Context 'audio devices' {
        It 'counts devices created by software separately and lists them as details' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_SoundDevice' } {
                [PSCustomObject]@{ Name = 'Contoso USB Headset'; PNPDeviceID = 'USB\VID_0000&PID_0001\1' }
                [PSCustomObject]@{ Name = 'Contoso HD Audio'; PNPDeviceID = 'HDAUDIO\FUNC_01&VEN_0000\1' }
                [PSCustomObject]@{ Name = 'Voice Changer'; PNPDeviceID = 'ROOT\MEDIA\0000' }
            }
            $audio = Get-ComputerSpecification | Where-Object Check -eq 'Audio devices'
            $audio.Value | Should -Be 'Contoso HD Audio, Contoso USB Headset and 1 virtual'
            $audio.Details | Should -Be @('Voice Changer (virtual)')
        }

        It 'says so when no audio device exists' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_SoundDevice' } { }
            (Get-ComputerSpecification | Where-Object Check -eq 'Audio devices').Value | Should -Be 'None found'
        }
    }

    Context 'input devices' {
        It 'reports standard devices when Windows only knows generic names' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Keyboard' } {
                [PSCustomObject]@{ Description = 'HID Keyboard Device' }
            }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PointingDevice' } {
                [PSCustomObject]@{ Name = 'HID-compliant mouse' }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'Input devices').Value | Should -Be 'Standard keyboard and mouse'
        }

        It 'says so when there is no keyboard and no pointing device' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Keyboard' } { }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PointingDevice' } { }
            (Get-ComputerSpecification | Where-Object Check -eq 'Input devices').Value | Should -Be 'None found'
        }
    }

    Context 'with memory modules of different sizes' {
        It 'lists each module and uses the default speed when no configured speed is reported' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' } {
                New-TestMemoryModule -Slot 'DIMM A1' -Capacity 8GB -Speed 2666 -ConfiguredSpeed $null
                New-TestMemoryModule -Slot '' -Capacity 4GB -Speed 2400 -ConfiguredSpeed $null -Manufacturer '' -PartNumber ''
            }
            $results = Get-ComputerSpecification
            ($results | Where-Object Check -eq 'Memory').Value | Should -Be '12 GB (8 GB + 4 GB DDR4, 2666 MHz), 2 of 4 slots used'
            # A module that reports neither slot nor maker is still listed with what is known.
            ($results | Where-Object Check -eq 'Memory module').Value | Should -Be @(
                'DIMM A1: 8 GB DDR4, 2666 MHz, Contoso CT8G4-3200'
                '4 GB DDR4, 2400 MHz'
            )
        }
    }

    Context 'on a virtual machine without module information' {
        It 'says that no module information is available' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemory' } { }
            $results = Get-ComputerSpecification
            ($results | Where-Object Check -eq 'Memory').Value | Should -Be 'No module information available'
            $results | Where-Object Check -eq 'Memory module' | Should -BeNullOrEmpty
        }
    }

    Context 'with a graphics adapter that has no display connected' {
        It 'reports the adapter without a resolution' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_VideoController' } {
                [PSCustomObject]@{
                    Name = 'Contoso GPU'; DriverVersion = '1.0'; DriverDate = $null
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
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BaseBoard' } { throw 'Query failed' }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' } { throw 'Query failed' }
            $results = Get-ComputerSpecification
            ($results | Where-Object Check -eq 'Motherboard').Status | Should -Be 'Warning'
            ($results | Where-Object Check -eq 'Storage').Status | Should -Be 'Warning'
            ($results | Where-Object Check -eq 'Storage').Recommendation | Should -Match 'Query failed'
            ($results | Where-Object Check -eq 'Processor').Status | Should -Be 'Info'
            ($results | Where-Object Check -eq 'Input devices').Status | Should -Be 'Info'
        }
    }

    Context 'when the Storage module of Windows is loaded in the process' {
        It 'still reads the type and the connection of a drive' {
            # The module shows the type of a drive as the text "SSD" instead of the number
            # 4; converting that text to a number made the check fail.
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' } {
                $drive = New-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ClientOnly -Property @{
                    DeviceId = '0'; FriendlyName = 'Contoso SSD 512'; MediaType = [uint16]4; BusType = [uint16]17
                    Size = [uint64]512GB; FirmwareVersion = 'FW2.1'
                }
                $drive | Add-Member -NotePropertyName MediaType -NotePropertyValue 'SSD' -Force
                $drive | Add-Member -NotePropertyName BusType -NotePropertyValue 'NVMe' -Force
                $drive
            }

            $storage = @(Get-ComputerSpecification | Where-Object Check -eq 'Storage')
            $storage.Count | Should -Be 1
            $storage[0].Status | Should -Be 'Info'
            $storage[0].Value | Should -Be 'Contoso SSD 512, 512 GB SSD (NVMe), firmware FW2.1'
        }
    }

    Context 'age of the BIOS, warranty and support' {
        It 'gives no advice about a BIOS of the last years' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } {
                [PSCustomObject]@{ Manufacturer = 'Contoso'; SMBIOSBIOSVersion = '1.14.2'; ReleaseDate = (Get-Date).AddYears(-1); SerialNumber = 'CNT4012XYZ' }
            }
            (Get-ComputerSpecification | Where-Object Check -eq 'BIOS').Recommendation | Should -BeNullOrEmpty
        }

        It 'advises to look for a newer version when the BIOS is older than the limit' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_BIOS' } {
                [PSCustomObject]@{ Manufacturer = 'Contoso'; SMBIOSBIOSVersion = '1.02'; ReleaseDate = (Get-Date).AddYears(-6); SerialNumber = 'CNT4012XYZ' }
            }
            $result = Get-ComputerSpecification | Where-Object Check -eq 'BIOS'
            $result.Status | Should -Be 'Info'
            $result.Recommendation | Should -Match 'more than 4 years old'
        }

        It 'names the support page for a maker it knows' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
                [PSCustomObject]@{ HypervisorPresent = $false; Manufacturer = ' Dell Inc. ' }
            }
            $result = Get-ComputerSpecification | Where-Object Check -eq 'Warranty and support'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Dell Inc.: looked up with the serial number on the support page of the manufacturer'
            $result.Recommendation | Should -Match 'how long the warranty runs'
            # The window finds the page of the maker from this value.
            (InModuleScope HelpdeskToolkit -Parameters @{ Value = $result.Value } { Get-CheckAction -Check 'Warranty and support' -Value $Value }).Target | Should -Match 'dell\.com'
        }

        It 'says so for a maker without a known support page, and offers no button' {
            $result = Get-ComputerSpecification | Where-Object Check -eq 'Warranty and support'
            $result.Value | Should -Match '^No support page known'
            $result.Recommendation | Should -BeNullOrEmpty
        }
    }
}
