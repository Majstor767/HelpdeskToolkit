BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-HardwareHealth' {
    BeforeAll {
        # Windows is on C: in these tests, whatever the drive of the test computer is.
        $realSystemDrive = $env:SystemDrive
        $env:SystemDrive = 'C:'

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
        # No hibernation file, no drivers worth mentioning and no battery details,
        # unless a test says otherwise.
        Mock -ModuleName HelpdeskToolkit Get-ChildItem { }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } { }
        Mock -ModuleName HelpdeskToolkit Get-BatteryCapacity { }
        # No memory test on record; the event log of the test computer is never read.
        Mock -ModuleName HelpdeskToolkit Get-MemoryDiagnosticResult { }
        Mock -ModuleName HelpdeskToolkit Get-LargestFolder { throw 'Must only be called for a disk that is running full' }

        # A driver as Win32_PnPSignedDriver reports it.
        function New-TestDriver {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([string]$Name, [string]$Provider = 'Contoso', [string]$Class = 'DISPLAY', $Date = (Get-Date).AddYears(-1), $Signed = $true)

            [PSCustomObject]@{ DeviceName = $Name; DriverProviderName = $Provider; DeviceClass = $Class; DriverDate = $Date; IsSigned = $Signed }
        }
    }

    Context 'on a healthy desktop computer' {
        BeforeAll {
            $results = Get-HardwareHealth
        }

        It 'reports <Check> as <Status> with value "<Value>"' -ForEach @(
            @{ Check = 'CPU load'; Status = 'OK'; Value = '20 % (Contoso Core 8)' }
            @{ Check = 'Memory usage'; Status = 'OK'; Value = '50 % (8 GB of 16 GB used)' }
            @{ Check = 'Disk (C:)'; Status = 'OK'; Value = '50 % free (100 GB of 200 GB), Windows drive' }
            @{ Check = 'Drive: Contoso NVMe 256GB'; Status = 'OK'; Value = 'SSD, NVMe, 256 GB, health: Healthy' }
            @{ Check = 'Temporary files'; Status = 'OK'; Value = '1 GB' }
            @{ Check = 'Downloads folder'; Status = 'Info'; Value = '1 GB in 40 files' }
            @{ Check = 'Recycle Bin'; Status = 'OK'; Value = '2 GB' }
            @{ Check = 'Page file'; Status = 'OK'; Value = '12 % (512 MB of 4096 MB used)' }
            @{ Check = 'Devices with problems'; Status = 'OK'; Value = 'None' }
            @{ Check = 'Battery'; Status = 'Info'; Value = 'No battery (desktop computer)' }
            @{ Check = 'Hibernation file'; Status = 'Info'; Value = 'Not present (hibernation is off)' }
            @{ Check = 'Unsigned drivers'; Status = 'OK'; Value = 'None' }
            @{ Check = 'Old drivers'; Status = 'Info'; Value = 'None older than 5 years' }
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

        It 'does not measure the folders of a disk that has enough free space' {
            $results | Where-Object Check -like 'Largest folders*' | Should -BeNullOrEmpty
            $results | Where-Object Check -eq 'Battery health' | Should -BeNullOrEmpty
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
            $disk.Value | Should -Be '3 % free (3 GB of 100 GB), Windows drive'
            $disk.Recommendation | Should -Match 'almost full'
        }

        It 'is a Warning below 15 % free' {
            ($results | Where-Object Check -eq 'Disk (D:)').Status | Should -Be 'Warning'
        }

        It 'marks only the drive Windows is installed on' {
            ($results | Where-Object Check -like 'Disk (*' | Where-Object { $_.Value -like '*, Windows drive' }).Check | Should -Be 'Disk (C:)'
            ($results | Where-Object Check -eq 'Disk (D:)').Value | Should -Be '10 % free (10 GB of 100 GB)'
        }

        It 'explains the Windows drive and a data drive differently' {
            ($results | Where-Object Check -eq 'Disk (C:)').Description | Should -Match '^The drive letter \(partition\) Windows is installed on'
            ($results | Where-Object Check -eq 'Disk (D:)').Description | Should -Match 'Windows is installed on another drive'
            ($results | Where-Object Check -eq 'Disk (E:)').Description | Should -Match 'Windows is installed on another drive'
        }

        It 'talks about Windows updates only in the advice for the Windows drive' {
            ($results | Where-Object Check -eq 'Disk (C:)').Recommendation | Should -Match 'Windows updates'
            $data = ($results | Where-Object Check -eq 'Disk (D:)').Recommendation
            $data | Should -Match 'Move files to another drive'
            $data | Should -Not -Match 'Windows|Disk Cleanup'
        }

        It 'gives a full data drive advice about its largest folders that does not mention Windows' {
            Mock -ModuleName HelpdeskToolkit Get-LargestFolder { [PSCustomObject]@{ Name = 'Games'; Bytes = 80GB; Complete = $true } }
            $folders = Get-HardwareHealth | Where-Object Check -like 'Largest folders*'

            ($folders | Where-Object Check -eq 'Largest folders (C:)').Recommendation | Should -Match 'inside Windows, Program Files or ProgramData'
            $data = ($folders | Where-Object Check -eq 'Largest folders (D:)').Recommendation
            $data | Should -Match 'removed by uninstalling it'
            $data | Should -Not -Match 'Windows'
        }

        It 'follows Windows to whatever drive it is installed on' {
            $env:SystemDrive = 'D:'
            try {
                $moved = Get-HardwareHealth
                ($moved | Where-Object Check -eq 'Disk (D:)').Value | Should -Be '10 % free (10 GB of 100 GB), Windows drive'
                ($moved | Where-Object Check -eq 'Disk (D:)').Recommendation | Should -Match 'Disk Cleanup'
                ($moved | Where-Object Check -eq 'Disk (C:)').Value | Should -Be '3 % free (3 GB of 100 GB)'
                ($moved | Where-Object Check -eq 'Disk (C:)').Recommendation | Should -Match 'Windows is not installed here'
            }
            finally {
                $env:SystemDrive = 'C:'
            }
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

    Context 'what takes up the space on a disk that is running full' {
        BeforeAll {
            # 4 GB of 200 GB free = 2 %, which is Critical
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
                [PSCustomObject]@{ DeviceID = 'C:'; Size = 200GB; FreeSpace = 4GB }
                [PSCustomObject]@{ DeviceID = 'D:'; Size = 200GB; FreeSpace = 150GB }
            }
            Mock -ModuleName HelpdeskToolkit Get-LargestFolder {
                [PSCustomObject]@{ Name = 'Users\tester\AppData'; Bytes = 60GB; Complete = $false }
                [PSCustomObject]@{ Name = 'Program Files'; Bytes = 20GB; Complete = $true }
                3..8 | ForEach-Object { [PSCustomObject]@{ Name = "Folder$_"; Bytes = (10 - $_) * 1GB; Complete = $true } }
            }
            $results = Get-HardwareHealth
            $largest = $results | Where-Object Check -like 'Largest folders*'
        }

        It 'lists the largest folders of that disk only' {
            @($largest).Count | Should -Be 1
            $largest.Check | Should -Be 'Largest folders (C:)'
            $largest.Status | Should -Be 'Info'
        }

        It 'shows the first six and marks a folder that could not be measured completely' {
            $largest.Value | Should -Be 'Users\tester\AppData 60 GB or more, Program Files 20 GB, Folder3 7 GB, Folder4 6 GB, Folder5 5 GB, Folder6 4 GB and 2 more'
            $largest.Details | Should -Be @('Folder7 3 GB', 'Folder8 2 GB')
        }

        It 'says where to start cleaning up' {
            $largest.Recommendation | Should -Match 'Downloads'
        }

        It 'measures the root of the disk within the configured time' {
            Should -Invoke -ModuleName HelpdeskToolkit Get-LargestFolder -Times 1 -Exactly -Scope Context -ParameterFilter {
                $Path -eq 'C:\' -and $BudgetMs -eq 3000
            }
        }

        It 'says so when nothing could be measured' {
            Mock -ModuleName HelpdeskToolkit Get-LargestFolder { }
            (Get-HardwareHealth | Where-Object Check -eq 'Largest folders (C:)').Value | Should -Be 'Nothing could be measured'
        }

        It 'reports a failure for that disk and still returns the other checks' {
            Mock -ModuleName HelpdeskToolkit Get-LargestFolder { throw 'Disk not ready' }
            $failed = Get-HardwareHealth
            ($failed | Where-Object Check -eq 'Largest folders (C:)').Value | Should -Be 'Unavailable'
            ($failed | Where-Object Check -eq 'Page file').Status | Should -Be 'OK'
        }
    }

    Context 'hibernation file' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-ChildItem { [PSCustomObject]@{ Name = 'hiberfil.sys'; Length = 12GB } }
        }

        It 'reports its size without advice while the system disk has room' {
            $file = Get-HardwareHealth | Where-Object Check -eq 'Hibernation file'
            $file.Status | Should -Be 'Info'
            $file.Value | Should -Be '12 GB'
            $file.Recommendation | Should -Be ''
        }

        It 'explains how to remove it when the system disk is running full' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
                [PSCustomObject]@{ DeviceID = $env:SystemDrive; Size = 200GB; FreeSpace = 4GB }
            }
            Mock -ModuleName HelpdeskToolkit Get-LargestFolder { }
            (Get-HardwareHealth | Where-Object Check -eq 'Hibernation file').Recommendation | Should -Match 'powercfg /hibernate off'
        }

        It 'looks for the file in the root of the system disk, hidden files included' {
            Get-HardwareHealth | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-ChildItem -ParameterFilter {
                $LiteralPath -eq "$($env:SystemDrive)\" -and $Filter -eq 'hiberfil.sys' -and $Force
            }
        }
    }

    Context 'drivers' {
        It 'is a Warning that names the drivers without a valid signature' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } {
                New-TestDriver -Name 'Contoso Capture Card' -Signed $false
                New-TestDriver -Name 'Contoso Graphics 770'
                # Windows does not say whether this one is signed; that is not a finding.
                New-TestDriver -Name 'Generic Device' -Signed $null
            }
            $unsigned = Get-HardwareHealth | Where-Object Check -eq 'Unsigned drivers'

            $unsigned.Status | Should -Be 'Warning'
            $unsigned.Value | Should -Be '1 driver: Contoso Capture Card'
            $unsigned.Recommendation | Should -Match 'digital signature'
        }

        It 'lists third-party drivers of important devices that are older than the limit, oldest first' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } {
                New-TestDriver -Name 'Contoso Graphics 770' -Date ([datetime]'2019-03-02')
                New-TestDriver -Name 'Contoso Wi-Fi' -Class 'NET' -Date ([datetime]'2017-06-15')
                # Not listed: new enough, made by Microsoft, a kind of device that does not
                # matter here, and the symbolic date some chipset drivers carry.
                New-TestDriver -Name 'Contoso Camera' -Date (Get-Date).AddYears(-2)
                New-TestDriver -Name 'Basic Display' -Provider 'Microsoft' -Date ([datetime]'2006-06-21')
                New-TestDriver -Name 'Contoso Chipset' -Class 'SYSTEM' -Date ([datetime]'2015-01-01')
                New-TestDriver -Name 'Contoso Bridge' -Date ([datetime]'1968-07-18')
            }
            $old = Get-HardwareHealth | Where-Object Check -eq 'Old drivers'

            $old.Status | Should -Be 'Info'
            $old.Value | Should -Be '2 drivers: Contoso Wi-Fi (2017-06-15), Contoso Graphics 770 (2019-03-02)'
            $old.Recommendation | Should -Match 'older than 5 years'
        }

        It 'lists a device with several entries of the same driver once' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } {
                New-TestDriver -Name 'Contoso Audio' -Date ([datetime]'2018-01-01')
                New-TestDriver -Name 'Contoso Audio' -Date ([datetime]'2018-01-01')
            }
            (Get-HardwareHealth | Where-Object Check -eq 'Old drivers').Value | Should -Be '1 driver: Contoso Audio (2018-01-01)'
        }

        It 'reports the drivers as unavailable when they cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PnPSignedDriver' } { throw 'Query failed' }
            $results = Get-HardwareHealth
            ($results | Where-Object Check -eq 'Drivers').Value | Should -Be 'Unavailable'
            $results | Where-Object Check -eq 'Unsigned drivers' | Should -BeNullOrEmpty
        }
    }

    Context 'battery health' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } {
                [PSCustomObject]@{ EstimatedChargeRemaining = 80; BatteryStatus = 2 }
            }
        }

        It 'is <Status> when the battery holds <Full> of 60000 mWh' -ForEach @(
            @{ Full = 48000; Status = 'OK'; Percent = 80 }
            @{ Full = 30000; Status = 'Warning'; Percent = 50 }
            @{ Full = 18000; Status = 'Critical'; Percent = 30 }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-BatteryCapacity { [PSCustomObject]@{ DesignedCapacity = 60000; FullChargedCapacity = $Full; CycleCount = $null } }
            $health = Get-HardwareHealth | Where-Object Check -eq 'Battery health'

            $health.Status | Should -Be $Status
            $health.Value | Should -Be "$Percent % of the original capacity ($Full of 60000 mWh)"
            $health.Allowed | Should -Be '60 - 100 % (critical below 40 %)'
            $health.Typical | Should -Be 'typical battery health'
        }

        It 'recommends a new battery when the capacity is low' {
            Mock -ModuleName HelpdeskToolkit Get-BatteryCapacity { [PSCustomObject]@{ DesignedCapacity = 60000; FullChargedCapacity = 30000; CycleCount = $null } }
            (Get-HardwareHealth | Where-Object Check -eq 'Battery health').Recommendation | Should -Match 'replace the battery'
        }

        It 'adds the number of charge cycles when the battery counts them' {
            Mock -ModuleName HelpdeskToolkit Get-BatteryCapacity { [PSCustomObject]@{ DesignedCapacity = 60000; FullChargedCapacity = 54000; CycleCount = 312 } }
            (Get-HardwareHealth | Where-Object Check -eq 'Battery health').Value | Should -Be '90 % of the original capacity (54000 of 60000 mWh), 312 charge cycles'
        }

        It 'never shows more than 100 %, which a new battery can report' {
            Mock -ModuleName HelpdeskToolkit Get-BatteryCapacity { [PSCustomObject]@{ DesignedCapacity = 60000; FullChargedCapacity = 61500; CycleCount = $null } }
            (Get-HardwareHealth | Where-Object Check -eq 'Battery health').Value | Should -Match '^100 %'
        }

        It 'is left out when the battery reports no capacity' {
            Get-HardwareHealth | Where-Object Check -eq 'Battery health' | Should -BeNullOrEmpty
        }
    }

    Context 'memory test' {
        It 'says so when the memory was never tested' {
            $result = Get-HardwareHealth | Where-Object Check -eq 'Memory test'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'No test on record'
        }

        It 'reports a test without errors as OK, with its date' {
            Mock -ModuleName HelpdeskToolkit Get-MemoryDiagnosticResult { [PSCustomObject]@{ TestedAt = [datetime]'2026-01-11 07:30'; HasErrors = $false } }
            $result = Get-HardwareHealth | Where-Object Check -eq 'Memory test'
            $result.Status | Should -Be 'OK'
            $result.Value | Should -Be 'No errors (tested 2026-01-11)'
        }

        It 'reports faulty memory as Critical' {
            Mock -ModuleName HelpdeskToolkit Get-MemoryDiagnosticResult { [PSCustomObject]@{ TestedAt = [datetime]'2026-01-11 07:30'; HasErrors = $true } }
            $result = Get-HardwareHealth | Where-Object Check -eq 'Memory test'
            $result.Status | Should -Be 'Critical'
            $result.Value | Should -Be 'Errors found (tested 2026-01-11)'
            $result.Recommendation | Should -Match 'replace it'
        }

        It 'reports the test as unavailable when the event log cannot be read, and goes on' {
            Mock -ModuleName HelpdeskToolkit Get-MemoryDiagnosticResult { throw 'The event log service is not running' }
            $results = Get-HardwareHealth
            ($results | Where-Object Check -eq 'Memory test').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Battery').Value | Should -Be 'No battery (desktop computer)'
        }
    }

    AfterAll {
        $env:SystemDrive = $realSystemDrive
    }
}
