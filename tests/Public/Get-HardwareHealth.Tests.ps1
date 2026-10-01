BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-HardwareHealth' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }

        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
            [PSCustomObject]@{ Name = ' Contoso Core 8 '; LoadPercentage = 20 }
        }
        # 16 GB installed, 8 GB free -> 50 % used
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [PSCustomObject]@{ TotalVisibleMemorySize = 16GB / 1KB; FreePhysicalMemory = 8GB / 1KB }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            [PSCustomObject]@{ DeviceID = 'C:'; Size = 200GB; FreeSpace = 100GB }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } { }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPEntity' } { }
        # Page file: 4096 MB allocated, 512 MB in use
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' } {
            [PSCustomObject]@{ AllocatedBaseSize = 4096; CurrentUsage = 512 }
        }
        # Folder sizes are replaced, so the tests never read the real disk.
        Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 1GB; FileCount = 40; Complete = $true } }
        Mock -ModuleName HelpdeskToolkit Get-RecycleBinSize { [PSCustomObject]@{ Bytes = 2GB; Complete = $true } }
        # The tests run as a standard user unless a test says otherwise.
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        # The Downloads folder is treated as present, whatever the test machine looks like.
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' } {
            [PSCustomObject]@{ FriendlyName = 'Contoso NVMe 256GB'; MediaType = 4; BusType = 17; Size = 256GB; HealthStatus = 0 }
        }
        Mock -ModuleName HelpdeskToolkit Get-Process {
            [PSCustomObject]@{ ProcessName = 'browser'; WorkingSet64 = 1GB }
            [PSCustomObject]@{ ProcessName = 'browser'; WorkingSet64 = 1GB }
            [PSCustomObject]@{ ProcessName = 'mail'; WorkingSet64 = 512MB }
        }
    }

    Context 'on a healthy desktop computer' {
        BeforeAll {
            $results = Get-HardwareHealth
        }

        It 'reports <Check> as <Status> with value "<Value>"' -ForEach @(
            @{ Check = 'CPU load'; Status = 'OK'; Value = '20 % (Contoso Core 8)' }
            @{ Check = 'Memory usage'; Status = 'OK'; Value = '50 % (8 GB of 16 GB used)' }
            @{ Check = 'Disk (C:)'; Status = 'OK'; Value = '50 % free (100 GB of 200 GB)' }
            @{ Check = 'Drive: Contoso NVMe 256GB'; Status = 'OK'; Value = 'SSD, NVMe, 256 GB, health: Healthy' }
            @{ Check = 'Temporary files'; Status = 'OK'; Value = '1 GB' }
            @{ Check = 'Downloads folder'; Status = 'Info'; Value = '1 GB in 40 files' }
            @{ Check = 'Recycle Bin'; Status = 'OK'; Value = '2 GB' }
            @{ Check = 'Page file'; Status = 'OK'; Value = '12 % (512 MB of 4096 MB used)' }
            @{ Check = 'Devices with problems'; Status = 'OK'; Value = 'None' }
            @{ Check = 'Battery'; Status = 'Info'; Value = 'No battery (desktop computer)' }
        ) {
            $result = $results | Where-Object Check -eq $Check
            $result.Status | Should -Be $Status
            $result.Value | Should -Be $Value
        }

        It 'adds the allowed range and typical value to the measurements' {
            ($results | Where-Object Check -eq 'CPU load').Allowed | Should -Be '0 - 85 % (critical above 95 %)'
            ($results | Where-Object Check -eq 'CPU load').Typical | Should -Be 'typical cpu'
            ($results | Where-Object Check -eq 'Disk (C:)').Allowed | Should -Be '15 - 100 % free (critical below 5 % free)'
        }

        It 'groups processes by name and sorts them by memory' {
            ($results | Where-Object Check -eq 'Top memory consumers').Value | Should -Be 'browser (2 GB), mail (0.5 GB)'
        }
    }

    Context 'CPU load' {
        It 'is <Status> at <Load> %' -ForEach @(
            @{ Load = 90; Status = 'Warning' }
            @{ Load = 99; Status = 'Critical' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
                [PSCustomObject]@{ Name = 'CPU'; LoadPercentage = $Load }
            }
            $cpu = Get-HardwareHealth | Where-Object Check -eq 'CPU load'
            $cpu.Status | Should -Be $Status
            $cpu.Recommendation | Should -Match 'Task Manager'
        }

        It 'averages the load of several processors' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
                [PSCustomObject]@{ Name = 'CPU'; LoadPercentage = 10 }
                [PSCustomObject]@{ Name = 'CPU'; LoadPercentage = 30 }
            }
            (Get-HardwareHealth | Where-Object Check -eq 'CPU load').Value | Should -Match '^20 %'
        }

        It 'is reported as unavailable when Windows gives no load value' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
                [PSCustomObject]@{ Name = 'CPU'; LoadPercentage = $null }
            }
            (Get-HardwareHealth | Where-Object Check -eq 'CPU load').Value | Should -Be 'Unavailable'
        }
    }

    Context 'memory usage' {
        It 'is <Status> when <FreeGb> GB of 16 GB is free' -ForEach @(
            @{ FreeGb = 2; Status = 'Warning' }      # 87.5 % used
            @{ FreeGb = 0.5; Status = 'Critical' }   # 97 % used
        ) {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
                [PSCustomObject]@{ TotalVisibleMemorySize = 16GB / 1KB; FreePhysicalMemory = $FreeGb * 1GB / 1KB }
            }
            (Get-HardwareHealth | Where-Object Check -eq 'Memory usage').Status | Should -Be $Status
        }
    }

    Context 'disk space' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
                [PSCustomObject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 3GB }
                [PSCustomObject]@{ DeviceID = 'D:'; Size = 100GB; FreeSpace = 10GB }
                [PSCustomObject]@{ DeviceID = 'E:'; Size = 100GB; FreeSpace = 60GB }
                [PSCustomObject]@{ DeviceID = 'F:'; Size = $null; FreeSpace = $null }
            }
            $results = Get-HardwareHealth
        }

        It 'returns one result per disk' {
            @($results | Where-Object Check -like 'Disk (*').Count | Should -Be 4
        }

        It 'is Critical below 5 % free' {
            $disk = $results | Where-Object Check -eq 'Disk (C:)'
            $disk.Status | Should -Be 'Critical'
            $disk.Value | Should -Be '3 % free (3 GB of 100 GB)'
            $disk.Recommendation | Should -Match 'almost full'
        }

        It 'is a Warning below 15 % free' {
            ($results | Where-Object Check -eq 'Disk (D:)').Status | Should -Be 'Warning'
        }

        It 'is OK with plenty of free space' {
            ($results | Where-Object Check -eq 'Disk (E:)').Status | Should -Be 'OK'
        }

        It 'does not divide by zero for a disk without a size' {
            ($results | Where-Object Check -eq 'Disk (F:)').Value | Should -Be 'Size unknown'
        }
    }

    Context 'drive health' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'MSFT_PhysicalDisk' } {
                [PSCustomObject]@{ FriendlyName = 'Old HDD'; MediaType = 3; BusType = 11; Size = 500GB; HealthStatus = 1 }
                [PSCustomObject]@{ FriendlyName = 'Dying SSD'; MediaType = 4; BusType = 11; Size = 250GB; HealthStatus = 2 }
                [PSCustomObject]@{ FriendlyName = 'USB stick'; MediaType = 0; BusType = 7; Size = 16GB; HealthStatus = 5 }
            }
            $results = Get-HardwareHealth
        }

        It 'reports a drive with a health warning as Warning and recommends a backup' {
            $drive = $results | Where-Object Check -eq 'Drive: Old HDD'
            $drive.Status | Should -Be 'Warning'
            $drive.Value | Should -Be 'HDD, SATA, 500 GB, health: Warning'
            $drive.Recommendation | Should -Match 'Back up'
        }

        It 'reports an unhealthy drive as Critical' {
            ($results | Where-Object Check -eq 'Drive: Dying SSD').Status | Should -Be 'Critical'
        }

        It 'reports an unknown health state as Info' {
            $drive = $results | Where-Object Check -eq 'Drive: USB stick'
            $drive.Status | Should -Be 'Info'
            $drive.Value | Should -Be 'USB, 16 GB, health: Unknown'
        }
    }

    Context 'space that can be freed' {
        It 'is a Warning when the temporary files are larger than the limit' {
            Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 8GB; FileCount = 9000; Complete = $true } }
            $temp = Get-HardwareHealth | Where-Object Check -eq 'Temporary files'
            $temp.Status | Should -Be 'Warning'
            $temp.Value | Should -Be '8 GB'
            $temp.Allowed | Should -Be '0 - 5 GB'
            $temp.Recommendation | Should -Match 'Temporary files'
        }

        It 'says "or more" when counting was stopped by the time limit' {
            Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 3GB; FileCount = 50000; Complete = $false } }
            $results = Get-HardwareHealth
            ($results | Where-Object Check -eq 'Temporary files').Value | Should -Be '3 GB or more'
            ($results | Where-Object Check -eq 'Downloads folder').Value | Should -Be '3 GB or more in 50000 files'
        }

        It 'is a Warning when the Recycle Bin is larger than the limit' {
            Mock -ModuleName HelpdeskToolkit Get-RecycleBinSize { [PSCustomObject]@{ Bytes = 25GB; Complete = $true } }
            $bin = Get-HardwareHealth | Where-Object Check -eq 'Recycle Bin'
            $bin.Status | Should -Be 'Warning'
            $bin.Recommendation | Should -Match 'Empty Recycle Bin'
        }

        It 'reports the sizes as unavailable instead of failing when they cannot be measured' {
            Mock -ModuleName HelpdeskToolkit Get-FolderSize { throw 'Disk error' }
            $results = Get-HardwareHealth
            ($results | Where-Object Check -eq 'Space that can be freed').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'CPU load').Status | Should -Be 'OK'
        }
    }

    Context 'page file' {
        It 'is a Warning when most of the page file is in use' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' } {
                [PSCustomObject]@{ AllocatedBaseSize = 2048; CurrentUsage = 1900 }
                [PSCustomObject]@{ AllocatedBaseSize = 2048; CurrentUsage = 1800 }
            }
            $pageFile = Get-HardwareHealth | Where-Object Check -eq 'Page file'
            $pageFile.Status | Should -Be 'Warning'
            $pageFile.Value | Should -Be '90 % (3700 MB of 4096 MB used)'
            $pageFile.Recommendation | Should -Match 'more RAM'
        }

        It 'says so when Windows runs without a page file' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' } { }
            (Get-HardwareHealth | Where-Object Check -eq 'Page file').Value | Should -Be 'No page file'
        }
    }

    Context 'without administrator rights' {
        It 'marks <_> as "Requires admin" instead of trying to read it' -ForEach @('Drive details', 'File system', 'System temporary files') {
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability { }
            $result = Get-HardwareHealth | Where-Object Check -eq $_
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Requires admin'
            Should -Invoke -ModuleName HelpdeskToolkit Get-DriveReliability -Times 0 -Exactly
        }
    }

    Context 'with administrator rights' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability {
                [PSCustomObject]@{ Name = 'Contoso NVMe'; Temperature = 41; Wear = 3; PowerOnHours = 5200; ReadErrors = 0; WriteErrors = 0 }
            }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Volume' } {
                [PSCustomObject]@{ DriveLetter = 'D:'; DirtyBitSet = $false }
                [PSCustomObject]@{ DriveLetter = 'C:'; DirtyBitSet = $false }
                [PSCustomObject]@{ DriveLetter = $null; DirtyBitSet = $false }
            }
            $degrees = '{0}C' -f [char]176
        }

        It 'reports what a healthy drive measures about itself' {
            $detail = Get-HardwareHealth | Where-Object Check -eq 'Drive details: Contoso NVMe'
            $detail.Status | Should -Be 'OK'
            $detail.Value | Should -Be "41 $degrees, 3 % of its lifetime used, 5200 hours powered on, 0 uncorrected errors"
            $detail.Typical | Should -Be "30 - 50 $degrees"
        }

        It 'is <Status> at a drive temperature of <Temperature> degrees' -ForEach @(
            @{ Temperature = 65; Status = 'Warning' }
            @{ Temperature = 75; Status = 'Critical' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability {
                [PSCustomObject]@{ Name = 'Hot'; Temperature = $Temperature; Wear = 1; PowerOnHours = 10; ReadErrors = 0; WriteErrors = 0 }
            }
            $detail = Get-HardwareHealth | Where-Object Check -eq 'Drive details: Hot'
            $detail.Status | Should -Be $Status
            $detail.Recommendation | Should -Match 'too hot'
        }

        It 'is a Warning when most of the lifetime of an SSD is used up' {
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability {
                [PSCustomObject]@{ Name = 'Worn'; Temperature = 40; Wear = 88; PowerOnHours = 30000; ReadErrors = 0; WriteErrors = 0 }
            }
            $detail = Get-HardwareHealth | Where-Object Check -eq 'Drive details: Worn'
            $detail.Status | Should -Be 'Warning'
            $detail.Recommendation | Should -Match 'replace'
        }

        It 'is a Warning when the drive has errors it could not correct' {
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability {
                [PSCustomObject]@{ Name = 'Failing'; Temperature = 40; Wear = 5; PowerOnHours = 100; ReadErrors = 3; WriteErrors = 1 }
            }
            $detail = Get-HardwareHealth | Where-Object Check -eq 'Drive details: Failing'
            $detail.Status | Should -Be 'Warning'
            $detail.Value | Should -Match '4 uncorrected errors'
        }

        It 'only shows what the drive reports (a hard disk has no wear value)' {
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability {
                [PSCustomObject]@{ Name = 'HDD'; Temperature = 0; Wear = $null; PowerOnHours = 12000; ReadErrors = $null; WriteErrors = $null }
            }
            $detail = Get-HardwareHealth | Where-Object Check -eq 'Drive details: HDD'
            $detail.Status | Should -Be 'OK'
            $detail.Value | Should -Be '12000 hours powered on'
        }

        It 'reports the drives as unavailable when the details cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability { throw 'Not supported by the storage driver' }
            (Get-HardwareHealth | Where-Object Check -eq 'Drive details').Value | Should -Be 'Unavailable'
        }

        It 'reports a clean file system on all drives with a letter' {
            $fileSystem = Get-HardwareHealth | Where-Object Check -eq 'File system'
            $fileSystem.Status | Should -Be 'OK'
            $fileSystem.Value | Should -Be 'No errors flagged (C:, D:)'
        }

        It 'is a Warning when Windows flagged a drive for a disk check' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Volume' } {
                [PSCustomObject]@{ DriveLetter = 'C:'; DirtyBitSet = $true }
                [PSCustomObject]@{ DriveLetter = 'D:'; DirtyBitSet = $false }
            }
            $fileSystem = Get-HardwareHealth | Where-Object Check -eq 'File system'
            $fileSystem.Status | Should -Be 'Warning'
            $fileSystem.Value | Should -Be 'Possible errors on C:'
            $fileSystem.Recommendation | Should -Match 'chkdsk'
        }

        It 'reports the size of the temporary files of Windows' {
            $systemTemp = Get-HardwareHealth | Where-Object Check -eq 'System temporary files'
            $systemTemp.Status | Should -Be 'OK'
            $systemTemp.Value | Should -Be '1 GB'
        }
    }

    Context 'devices without a working driver' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPEntity' } {
                [PSCustomObject]@{ Name = 'Contoso USB Dock'; ConfigManagerErrorCode = 28 }
                [PSCustomObject]@{ Name = $null; ConfigManagerErrorCode = 43 }
                3..7 | ForEach-Object { [PSCustomObject]@{ Name = "Device $_"; ConfigManagerErrorCode = 10 } }
            }
            $devices = Get-HardwareHealth | Where-Object Check -eq 'Devices with problems'
        }

        It 'is a Warning that names the devices and their error codes' {
            $devices.Status | Should -Be 'Warning'
            $devices.Value | Should -Match '^7 devices: Contoso USB Dock \(code 28\), Unknown device \(code 43\)'
            $devices.Recommendation | Should -Match 'Device Manager'
        }

        It 'shows the first five devices and keeps the rest as details' {
            $devices.Value | Should -Match 'and 2 more$'
            $devices.Details | Should -Be @('Device 6 (code 10)', 'Device 7 (code 10)')
        }

        It 'does not ask for devices that were disabled on purpose (code 22)' {
            Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -Scope Context -ParameterFilter {
                $ClassName -eq 'Win32_PnPEntity' -and $Filter -match 'ConfigManagerErrorCode <> 22'
            }
        }
    }

    Context 'on a laptop' {
        It 'is OK while plugged in, even with a low charge' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } {
                [PSCustomObject]@{ EstimatedChargeRemaining = 8; BatteryStatus = 2 }
            }
            $battery = Get-HardwareHealth | Where-Object Check -eq 'Battery'
            $battery.Status | Should -Be 'OK'
            $battery.Value | Should -Be '8 % (plugged in)'
        }

        It 'is <Status> at <Charge> % on battery' -ForEach @(
            @{ Charge = 60; Status = 'OK' }
            @{ Charge = 15; Status = 'Warning' }
            @{ Charge = 5; Status = 'Critical' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } {
                [PSCustomObject]@{ EstimatedChargeRemaining = $Charge; BatteryStatus = 1 }
            }
            $battery = Get-HardwareHealth | Where-Object Check -eq 'Battery'
            $battery.Status | Should -Be $Status
            $battery.Value | Should -Be "$Charge % (on battery)"
        }
    }

    Context 'when one data source fails' {
        It 'reports that check as unavailable and still returns the others' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } { throw 'Query failed' }
            $results = Get-HardwareHealth
            ($results | Where-Object Check -eq 'Disk space').Status | Should -Be 'Warning'
            ($results | Where-Object Check -eq 'CPU load').Status | Should -Be 'OK'
        }
    }
}
