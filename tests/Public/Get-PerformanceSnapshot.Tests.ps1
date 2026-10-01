BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule

    # One row of the per-program graphics counter. The name carries the process id, the
    # adapter ("luid") and the engine type.
    function New-TestGpuEngine {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([int]$ProcessId, [string]$Adapter, [string]$Engine, [int]$Percent)

        [PSCustomObject]@{
            Name                  = 'pid_{0}_{1}_eng_0_engtype_{2}' -f $ProcessId, $Adapter, $Engine
            UtilizationPercentage = $Percent
        }
    }

    # One row of the processor counter, with a base speed of 2000 MHz.
    function New-TestProcessor {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Name, [double]$Utility, [int]$Performance, [int]$Parked = 0)

        [PSCustomObject]@{
            Name = $Name; PercentProcessorUtility = $Utility; ProcessorFrequency = 2000
            PercentProcessorPerformance = $Performance; ParkingStatus = $Parked
        }
    }

    # One row of the process counter.
    function New-TestProcess {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Name, [int]$ProcessorTime, [long]$Memory = 0, [long]$Read = 0, [long]$Write = 0, [int]$Threads = 1, [int]$Handles = 1)

        [PSCustomObject]@{
            Name = $Name; PercentProcessorTime = $ProcessorTime; WorkingSetPrivate = $Memory
            IOReadBytesPersec = $Read; IOWriteBytesPersec = $Write; ThreadCount = $Threads; HandleCount = $Handles
        }
    }
}

Describe 'Get-PerformanceSnapshot' {
    BeforeAll {
        $adapterA = 'luid_0x00000000_0x0000AAAA_phys_0'
        $adapterB = 'luid_0x00000000_0x0000BBBB_phys_0'

        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }

        # Deliberately out of order: "0,10" must come after "0,2".
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_Counters_ProcessorInformation' } {
            # The base speed is 2000 MHz; "performance" says how fast a processor really runs.
            New-TestProcessor -Name '0,10' -Utility 5 -Performance 100
            New-TestProcessor -Name '_Total' -Utility 41 -Performance 170
            New-TestProcessor -Name '0,_Total' -Utility 41 -Performance 170
            New-TestProcessor -Name '0,2' -Utility 118 -Performance 180
            New-TestProcessor -Name '0,0' -Utility 37.6 -Performance 175
            New-TestProcessor -Name '0,1' -Utility 0 -Performance 0 -Parked 1
        }
        # Sizes in kilobytes, as Windows reports them.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [PSCustomObject]@{
                TotalVisibleMemorySize = 16GB / 1KB; FreePhysicalMemory = 4GB / 1KB
                TotalVirtualMemorySize = 20GB / 1KB; FreeVirtualMemory = 5GB / 1KB
                NumberOfProcesses = 212; LastBootUpTime = (Get-Date).AddHours(-26)
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfRawData_PerfOS_Memory' } {
            [PSCustomObject]@{
                StandbyCacheNormalPriorityBytes = 3GB; StandbyCacheReserveBytes = 512MB; StandbyCacheCoreBytes = 256MB; ModifiedPageListBytes = 256MB
                PoolPagedBytes = 1GB; PoolNonpagedBytes = 768MB
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_PerfOS_PagingFile' } {
            [PSCustomObject]@{ Name = 'C:\pagefile.sys'; PercentUsage = 9 }
            [PSCustomObject]@{ Name = '_Total'; PercentUsage = 12 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' } {
            [PSCustomObject]@{ Name = '_Total'; PercentIdleTime = 90; DiskReadBytesPersec = 9; DiskWriteBytesPersec = 9; CurrentDiskQueueLength = 3 }
            [PSCustomObject]@{ Name = '1'; PercentIdleTime = 100; DiskReadBytesPersec = 0; DiskWriteBytesPersec = 0; CurrentDiskQueueLength = 0 }
            [PSCustomObject]@{ Name = '0 C: D:'; PercentIdleTime = 75; DiskReadBytesPersec = 1048576; DiskWriteBytesPersec = 2048; CurrentDiskQueueLength = 3 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            [PSCustomObject]@{ DeviceID = 'D:'; VolumeName = 'Data'; Size = 400GB; FreeSpace = 300GB }
            [PSCustomObject]@{ DeviceID = 'C:'; VolumeName = ''; Size = 200GB; FreeSpace = 10GB }
            # A card reader without a card reports no size.
            [PSCustomObject]@{ DeviceID = 'F:'; VolumeName = ''; Size = $null; FreeSpace = $null }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_Counters_ThermalZoneInformation' } { }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } { }
        Mock -ModuleName HelpdeskToolkit Get-NvidiaGpuStatus { }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        Mock -ModuleName HelpdeskToolkit Get-DriveReliability { throw 'Must not be called without administrator rights' }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_Tcpip_NetworkInterface' } {
            [PSCustomObject]@{ Name = 'Contoso Ethernet'; CurrentBandwidth = 1000000000; BytesReceivedPersec = 125000; BytesSentPersec = 2500 }
            [PSCustomObject]@{ Name = 'Disconnected Adapter'; CurrentBandwidth = 0; BytesReceivedPersec = 0; BytesSentPersec = 0 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' } {
            # Adapter A: two programs use the 3D engine (30 + 12), one decodes video (20).
            New-TestGpuEngine -ProcessId 100 -Adapter $adapterA -Engine '3D' -Percent 30
            New-TestGpuEngine -ProcessId 200 -Adapter $adapterA -Engine '3D' -Percent 12
            New-TestGpuEngine -ProcessId 200 -Adapter $adapterA -Engine 'VideoDecode' -Percent 20
            # Adapter B is a software adapter that does nothing.
            New-TestGpuEngine -ProcessId 100 -Adapter $adapterB -Engine '3D' -Percent 0
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory' } {
            [PSCustomObject]@{ Name = $adapterA; DedicatedUsage = 3GB; SharedUsage = 256MB }
            [PSCustomObject]@{ Name = $adapterB; DedicatedUsage = 0; SharedUsage = 0 }
        }
        Mock -ModuleName HelpdeskToolkit Get-VideoMemory { [PSCustomObject]@{ Name = 'Contoso Graphics 770'; Bytes = 8GB } }

        # PercentProcessorTime adds up all logical processors (here: 4).
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_PerfProc_Process' } {
            New-TestProcess -Name '_Total' -ProcessorTime 400 -Threads 3456 -Handles 98765
            New-TestProcess -Name 'Idle' -ProcessorTime 300
            New-TestProcess -Name 'browser' -ProcessorTime 20 -Memory 500MB -Read 1000 -Write 500
            New-TestProcess -Name 'browser#1' -ProcessorTime 60 -Memory 300MB -Read 500
            New-TestProcess -Name 'editor' -ProcessorTime 8 -Memory 200MB
            New-TestProcess -Name 'quiet-big' -ProcessorTime 0 -Memory 2GB -Write 5MB
            New-TestProcess -Name 'quiet-small' -ProcessorTime 0 -Memory 1MB
        }

        # The graphics adapters are only looked up once per session, the drives every 30 seconds.
        InModuleScope HelpdeskToolkit { $script:VideoMemoryCache = $null; $script:DriveHealthCache = $null }
        $snapshot = Get-PerformanceSnapshot
    }

    It 'returns one object of the snapshot type with the time of the measurement' {
        @($snapshot).Count | Should -Be 1
        $snapshot.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.PerformanceSnapshot'
        $snapshot.TakenAt | Should -BeOfType [datetime]
    }

    Context 'processor' {
        It 'reports the total load, the base speed and the speed the processor really runs at' {
            $snapshot.Cpu.Percent | Should -Be 41
            $snapshot.Cpu.BaseFrequencyMHz | Should -Be 2000
            # 170 % of the base speed
            $snapshot.Cpu.FrequencyMHz | Should -Be 3400
        }

        It 'numbers the logical processors in their real order and leaves out the totals' {
            $snapshot.Cpu.Processors.Name | Should -Be @('CPU 0', 'CPU 1', 'CPU 2', 'CPU 3')
        }

        It 'calculates the speed of every processor, and falls back to the base speed when Windows reports none' {
            $snapshot.Cpu.Processors.FrequencyMHz | Should -Be @(3500, 2000, 3600, 2000)
        }

        It 'reports which processors Windows has parked' {
            $snapshot.Cpu.Processors.Parked | Should -Be @($false, $true, $false, $false)
        }

        It 'rounds the load and never shows more than 100 %' {
            $snapshot.Cpu.Processors.Percent | Should -Be @(38, 0, 100, 5)
        }
    }

    Context 'memory' {
        It 'converts the sizes to bytes and calculates the share in use' {
            $snapshot.Memory.TotalBytes | Should -Be 16GB
            $snapshot.Memory.UsedBytes | Should -Be 12GB
            $snapshot.Memory.Percent | Should -Be 75
        }

        It 'reports the committed memory against its limit' {
            $snapshot.Memory.CommittedBytes | Should -Be 15GB
            $snapshot.Memory.CommitLimitBytes | Should -Be 20GB
        }

        It 'reports the available memory, and the cached memory as standby plus modified pages' {
            $snapshot.Memory.AvailableBytes | Should -Be 4GB
            $snapshot.Memory.CachedBytes | Should -Be 4GB
        }

        It 'reports the kernel pools and the usage of the page file' {
            $snapshot.Memory.PagedPoolBytes | Should -Be 1GB
            $snapshot.Memory.NonPagedPoolBytes | Should -Be 768MB
            $snapshot.Memory.PageFilePercent | Should -Be 12
        }

        It 'still reports the basic values when the breakdown cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfRawData_PerfOS_Memory' } { throw 'Counter missing' }
            $memory = (Get-PerformanceSnapshot).Memory

            $memory.Percent | Should -Be 75
            $memory.CachedBytes | Should -BeNullOrEmpty
            $memory.PageFilePercent | Should -BeNullOrEmpty
        }
    }

    Context 'system' {
        It 'reports the number of processes, threads and handles' {
            $snapshot.System.Processes | Should -Be 212
            $snapshot.System.Threads | Should -Be 3456
            $snapshot.System.Handles | Should -Be 98765
        }

        It 'reports the time since Windows started' {
            # 26 hours, give or take the seconds the test needs
            $snapshot.System.UptimeSeconds | Should -BeGreaterOrEqual 93600
            $snapshot.System.UptimeSeconds | Should -BeLessThan 93700
        }
    }

    Context 'disks' {
        It 'lists every physical disk with its drive letters and leaves out the total' {
            $snapshot.Disks.Name | Should -Be @('Disk 0 (C: D:)', 'Disk 1')
        }

        It 'reports how busy a disk is as 100 minus its idle time' {
            $snapshot.Disks.Percent | Should -Be @(25, 0)
            $snapshot.Disks[0].ReadBytesPerSecond | Should -Be 1048576
            $snapshot.Disks[0].WriteBytesPerSecond | Should -Be 2048
        }

        It 'reports how many requests are waiting for a disk' {
            $snapshot.Disks.QueueLength | Should -Be @(3, 0)
        }
    }

    Context 'volumes' {
        It 'lists the drive letters in order and leaves out a drive without a size' {
            $snapshot.Volumes.Name | Should -Be @('C:', 'D:')
            $snapshot.Volumes.Label | Should -Be @('', 'Data')
        }

        It 'reports the share of the space that is used' {
            $snapshot.Volumes.Percent | Should -Be @(95, 25)
            $snapshot.Volumes[0].FreeBytes | Should -Be 10GB
            $snapshot.Volumes[0].TotalBytes | Should -Be 200GB
        }
    }

    Context 'drive health' {
        BeforeEach {
            InModuleScope HelpdeskToolkit { $script:DriveHealthCache = $null }
        }

        It 'says that administrator rights are needed, without asking the drives' {
            $snapshot.DriveHealth.State | Should -Be 'RequiresAdmin'
            @($snapshot.DriveHealth.Drives).Count | Should -Be 0
        }

        It 'reports temperature, wear and hours of use of every drive for an administrator' {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability {
                [PSCustomObject]@{ Name = 'Contoso SSD 512'; Temperature = 41; Wear = 3; PowerOnHours = 5231; ReadErrors = 0; WriteErrors = 0 }
                [PSCustomObject]@{ Name = 'Contoso HD 2000'; Temperature = 36; Wear = $null; PowerOnHours = $null; ReadErrors = 0; WriteErrors = 0 }
            }
            $health = (Get-PerformanceSnapshot).DriveHealth

            $health.State | Should -Be 'OK'
            $health.Drives.Name | Should -Be @('Contoso SSD 512', 'Contoso HD 2000')
            $health.Drives[0].TemperatureC | Should -Be 41
            $health.Drives[0].WearPercent | Should -Be 3
            $health.Drives[0].PowerOnHours | Should -Be 5231
            $health.Drives[1].WearPercent | Should -BeNullOrEmpty
        }

        It 'asks the drives only once in a while, because the values change slowly' {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability { [PSCustomObject]@{ Name = 'Contoso SSD 512'; Temperature = 41; Wear = 3; PowerOnHours = 1 } }
            Get-PerformanceSnapshot | Out-Null
            $second = Get-PerformanceSnapshot

            Should -Invoke -ModuleName HelpdeskToolkit Get-DriveReliability -Times 1 -Exactly
            $second.DriveHealth.Drives.Name | Should -Be 'Contoso SSD 512'
        }

        It 'asks the drives again when the last answer is older than 30 seconds' {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability { [PSCustomObject]@{ Name = 'Contoso SSD 512'; Temperature = 41; Wear = 3; PowerOnHours = 1 } }
            Get-PerformanceSnapshot | Out-Null
            InModuleScope HelpdeskToolkit { $script:DriveHealthCache.At = (Get-Date).AddSeconds(-31) }
            Get-PerformanceSnapshot | Out-Null

            Should -Invoke -ModuleName HelpdeskToolkit Get-DriveReliability -Times 2 -Exactly
        }

        It 'says why the drives could not be read instead of failing' {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability { throw 'The storage service does not answer' }
            $health = (Get-PerformanceSnapshot).DriveHealth

            $health.State | Should -Be 'Unavailable'
            $health.Message | Should -Be 'The storage service does not answer'
        }
    }

    Context 'sensors' {
        It 'passes on the sensors of NVIDIA graphics cards' {
            Mock -ModuleName HelpdeskToolkit Get-NvidiaGpuStatus {
                [PSCustomObject]@{ Name = 'Contoso GeForce'; TemperatureC = 61; FanPercent = 35; PowerWatts = 90; PowerLimitWatts = 200 }
            }
            $sensors = (Get-PerformanceSnapshot).GpuSensors

            $sensors.Name | Should -Be 'Contoso GeForce'
            $sensors.TemperatureC | Should -Be 61
        }

        It 'returns no graphics sensors, without an error, when the tool fails' {
            Mock -ModuleName HelpdeskToolkit Get-NvidiaGpuStatus { throw 'The tool crashed' }
            @((Get-PerformanceSnapshot).GpuSensors).Count | Should -Be 0
        }

        It 'converts the thermal zones from tenths of a kelvin to degrees Celsius' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_Counters_ThermalZoneInformation' } {
                [PSCustomObject]@{ Name = '\_TZ.TZ01'; HighPrecisionTemperature = 3282; Temperature = 328 }
                # A zone without the precise value reports whole kelvin.
                [PSCustomObject]@{ Name = '\_TZ.TZ00'; HighPrecisionTemperature = 0; Temperature = 318 }
                # A zone that reports nothing useful is left out.
                [PSCustomObject]@{ Name = '\_TZ.TZ02'; HighPrecisionTemperature = 0; Temperature = 0 }
            }
            $zones = (Get-PerformanceSnapshot).Thermal

            $zones.Name | Should -Be @('TZ00', 'TZ01')
            $zones.TemperatureC | Should -Be @(45, 55)
        }

        It 'returns no battery on a desktop computer' {
            $snapshot.Battery | Should -BeNullOrEmpty
        }

        It 'reports charge and remaining time of a battery that is in use' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } {
                [PSCustomObject]@{ EstimatedChargeRemaining = 64; BatteryStatus = 1; EstimatedRunTime = 130 }
            }
            $battery = (Get-PerformanceSnapshot).Battery

            $battery.Percent | Should -Be 64
            $battery.PluggedIn | Should -BeFalse
            $battery.MinutesRemaining | Should -Be 130
        }

        It 'reports no remaining time while the computer is plugged in' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Battery' } {
                # Windows reports a very large number of minutes while charging.
                [PSCustomObject]@{ EstimatedChargeRemaining = 90; BatteryStatus = 2; EstimatedRunTime = 71582788 }
            }
            $battery = (Get-PerformanceSnapshot).Battery

            $battery.PluggedIn | Should -BeTrue
            $battery.MinutesRemaining | Should -BeNullOrEmpty
        }
    }

    Context 'network' {
        It 'lists only adapters that are connected' {
            $snapshot.Network.Name | Should -Be 'Contoso Ethernet'
            $snapshot.Network.ReceivedBytesPerSecond | Should -Be 125000
            $snapshot.Network.SentBytesPerSecond | Should -Be 2500
        }

        It 'reports the speed of the link' {
            $snapshot.Network.LinkBitsPerSecond | Should -Be 1000000000
        }
    }

    Context 'graphics' {
        It 'leaves out a software adapter that uses no memory and does no work' {
            @($snapshot.Gpu).Count | Should -Be 1
        }

        It 'takes the load of the busiest engine, added up over all programs' {
            # 3D: 30 + 12 = 42; video decode: 20. Like Task Manager, the higher one counts.
            $snapshot.Gpu[0].Percent | Should -Be 42
        }

        It 'names the only real adapter and reports its memory' {
            $snapshot.Gpu[0].Name | Should -Be 'Contoso Graphics 770'
            $snapshot.Gpu[0].DedicatedUsedBytes | Should -Be 3GB
            $snapshot.Gpu[0].DedicatedTotalBytes | Should -Be 8GB
            $snapshot.Gpu[0].SharedUsedBytes | Should -Be 256MB
        }

        It 'reports the load of each engine under a readable name' {
            $snapshot.Gpu[0].Engines.Name | Should -Be @('3D', 'Video decode')
            $snapshot.Gpu[0].Engines.Percent | Should -Be @(42, 20)
        }

        It 'numbers the adapters when it cannot tell which one is which' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory' } {
                [PSCustomObject]@{ Name = $adapterA; DedicatedUsage = 1GB; SharedUsage = 0 }
                [PSCustomObject]@{ Name = $adapterB; DedicatedUsage = 3GB; SharedUsage = 0 }
            }
            $gpu = (Get-PerformanceSnapshot).Gpu

            $gpu.Name | Should -Be @('GPU 1', 'GPU 2')
            # Sorted by memory in use, and without a total size that would only be a guess.
            $gpu.DedicatedUsedBytes | Should -Be @(3GB, 1GB)
            $gpu.DedicatedTotalBytes | Should -Be @(0, 0)
        }

        It 'reads the installed adapters from the registry only once' {
            InModuleScope HelpdeskToolkit { $script:VideoMemoryCache = $null }
            Get-PerformanceSnapshot | Out-Null
            Get-PerformanceSnapshot | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-VideoMemory -Times 1 -Exactly
        }
    }

    Context 'busiest programs' {
        It 'adds up the processes of one program and divides by the number of logical processors' {
            $browser = $snapshot.Processes | Where-Object Name -eq 'browser'
            # (20 + 60) / 4 logical processors
            $browser.Percent | Should -Be 20
            $browser.MemoryBytes | Should -Be 800MB
        }

        It 'sorts by processor time, then by memory, and leaves out Idle and the total' {
            $snapshot.Processes.Name | Should -Be @('browser', 'editor', 'quiet-big', 'quiet-small')
        }

        It 'lists the programs that use the most memory' {
            $snapshot.MemoryProcesses.Name | Should -Be @('quiet-big', 'browser', 'editor', 'quiet-small')
        }

        It 'lists the programs that read and write the most data, and only those that do' {
            $snapshot.IoProcesses.Name | Should -Be @('quiet-big', 'browser')
            # browser: (1000 + 500) + 500 bytes per second over its two processes
            $snapshot.IoProcesses[1].IoBytesPerSecond | Should -Be 2000
        }

        It 'returns only as many programs as asked for' {
            $top = Get-PerformanceSnapshot -TopProcessCount 2
            $top.Processes.Name | Should -Be @('browser', 'editor')
            $top.MemoryProcesses.Name | Should -Be @('quiet-big', 'browser')
        }

        It 'rejects a count outside 1 - 20' {
            { Get-PerformanceSnapshot -TopProcessCount 0 } | Should -Throw
        }
    }

    Context 'when a part cannot be read' {
        It 'returns that part empty and still fills in the others' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_Counters_ProcessorInformation' } { throw 'Counter missing' }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' } { throw 'Counter missing' }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' } { throw 'Counter missing' }
            $partial = Get-PerformanceSnapshot

            $partial.Cpu | Should -BeNullOrEmpty
            @($partial.Gpu).Count | Should -Be 0
            @($partial.Disks).Count | Should -Be 0
            $partial.Memory.Percent | Should -Be 75
            $partial.Network.Name | Should -Be 'Contoso Ethernet'
            @($partial.Processes).Count | Should -Be 4
            $partial.Volumes.Name | Should -Be @('C:', 'D:')
        }

        It 'returns an object even when nothing can be read' {
            # A mock with a filter is tried before the ones defined earlier, so this one replaces them all.
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $true } { throw 'WMI is not available' }
            $nothing = Get-PerformanceSnapshot

            $nothing.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.PerformanceSnapshot'
            $nothing.Cpu | Should -BeNullOrEmpty
            $nothing.Memory | Should -BeNullOrEmpty
            $nothing.System | Should -BeNullOrEmpty
            $nothing.Battery | Should -BeNullOrEmpty
            @($nothing.Processes).Count | Should -Be 0
            @($nothing.Volumes).Count | Should -Be 0
            @($nothing.Thermal).Count | Should -Be 0
        }
    }
}
