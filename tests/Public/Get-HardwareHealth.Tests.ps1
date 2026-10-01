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
