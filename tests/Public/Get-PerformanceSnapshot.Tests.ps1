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
}

Describe 'Get-PerformanceSnapshot' {
    BeforeAll {
        $adapterA = 'luid_0x00000000_0x0000AAAA_phys_0'
        $adapterB = 'luid_0x00000000_0x0000BBBB_phys_0'

        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }

        # Deliberately out of order: "0,10" must come after "0,2".
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_Counters_ProcessorInformation' } {
            [PSCustomObject]@{ Name = '0,10'; PercentProcessorUtility = 5; ProcessorFrequency = 3300 }
            [PSCustomObject]@{ Name = '_Total'; PercentProcessorUtility = 41; ProcessorFrequency = 3400 }
            [PSCustomObject]@{ Name = '0,_Total'; PercentProcessorUtility = 41; ProcessorFrequency = 3400 }
            [PSCustomObject]@{ Name = '0,2'; PercentProcessorUtility = 118; ProcessorFrequency = 3600 }
            [PSCustomObject]@{ Name = '0,0'; PercentProcessorUtility = 37.6; ProcessorFrequency = 3500 }
            [PSCustomObject]@{ Name = '0,1'; PercentProcessorUtility = 0; ProcessorFrequency = 3500 }
        }
        # Sizes in kilobytes, as Windows reports them.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [PSCustomObject]@{
                TotalVisibleMemorySize = 16GB / 1KB; FreePhysicalMemory = 4GB / 1KB
                TotalVirtualMemorySize = 20GB / 1KB; FreeVirtualMemory = 5GB / 1KB
            }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' } {
            [PSCustomObject]@{ Name = '_Total'; PercentIdleTime = 90; DiskReadBytesPersec = 9; DiskWriteBytesPersec = 9 }
            [PSCustomObject]@{ Name = '1'; PercentIdleTime = 100; DiskReadBytesPersec = 0; DiskWriteBytesPersec = 0 }
            [PSCustomObject]@{ Name = '0 C: D:'; PercentIdleTime = 75; DiskReadBytesPersec = 1048576; DiskWriteBytesPersec = 2048 }
        }
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
            [PSCustomObject]@{ Name = $adapterA; DedicatedUsage = 3GB }
            [PSCustomObject]@{ Name = $adapterB; DedicatedUsage = 0 }
        }
        Mock -ModuleName HelpdeskToolkit Get-VideoMemory { [PSCustomObject]@{ Name = 'Contoso Graphics 770'; Bytes = 8GB } }

        # PercentProcessorTime adds up all logical processors (here: 4).
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_PerfProc_Process' } {
            [PSCustomObject]@{ Name = '_Total'; PercentProcessorTime = 400; WorkingSetPrivate = 0 }
            [PSCustomObject]@{ Name = 'Idle'; PercentProcessorTime = 300; WorkingSetPrivate = 0 }
            [PSCustomObject]@{ Name = 'browser'; PercentProcessorTime = 20; WorkingSetPrivate = 500MB }
            [PSCustomObject]@{ Name = 'browser#1'; PercentProcessorTime = 60; WorkingSetPrivate = 300MB }
            [PSCustomObject]@{ Name = 'editor'; PercentProcessorTime = 8; WorkingSetPrivate = 200MB }
            [PSCustomObject]@{ Name = 'quiet-big'; PercentProcessorTime = 0; WorkingSetPrivate = 2GB }
            [PSCustomObject]@{ Name = 'quiet-small'; PercentProcessorTime = 0; WorkingSetPrivate = 1MB }
        }

        # The graphics adapters are only looked up once per session.
        InModuleScope HelpdeskToolkit { $script:VideoMemoryCache = $null }
        $snapshot = Get-PerformanceSnapshot
    }

    It 'returns one object of the snapshot type with the time of the measurement' {
        @($snapshot).Count | Should -Be 1
        $snapshot.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.PerformanceSnapshot'
        $snapshot.TakenAt | Should -BeOfType [datetime]
    }

    Context 'processor' {
        It 'reports the total load and clock speed' {
            $snapshot.Cpu.Percent | Should -Be 41
            $snapshot.Cpu.FrequencyMHz | Should -Be 3400
        }

        It 'numbers the logical processors in their real order and leaves out the totals' {
            $snapshot.Cpu.Processors.Name | Should -Be @('CPU 0', 'CPU 1', 'CPU 2', 'CPU 3')
            $snapshot.Cpu.Processors.FrequencyMHz | Should -Be @(3500, 3500, 3600, 3300)
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
    }

    Context 'network' {
        It 'lists only adapters that are connected' {
            $snapshot.Network.Name | Should -Be 'Contoso Ethernet'
            $snapshot.Network.ReceivedBytesPerSecond | Should -Be 125000
            $snapshot.Network.SentBytesPerSecond | Should -Be 2500
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
        }

        It 'numbers the adapters when it cannot tell which one is which' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory' } {
                [PSCustomObject]@{ Name = $adapterA; DedicatedUsage = 1GB }
                [PSCustomObject]@{ Name = $adapterB; DedicatedUsage = 3GB }
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

        It 'returns only as many programs as asked for' {
            (Get-PerformanceSnapshot -TopProcessCount 2).Processes.Name | Should -Be @('browser', 'editor')
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
        }

        It 'returns an object even when nothing can be read' {
            # A mock with a filter is tried before the ones defined earlier, so this one replaces them all.
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $true } { throw 'WMI is not available' }
            $nothing = Get-PerformanceSnapshot

            $nothing.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.PerformanceSnapshot'
            $nothing.Cpu | Should -BeNullOrEmpty
            $nothing.Memory | Should -BeNullOrEmpty
            @($nothing.Processes).Count | Should -Be 0
        }
    }
}
