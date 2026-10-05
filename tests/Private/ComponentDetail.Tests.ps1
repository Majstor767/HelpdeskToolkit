# Tests for the detail pages of the Live monitor (processor, memory, graphics card): the
# functions that read everything about a component, and the page that shows it. Also
# covered here: the order of the results by severity and the click on a program in
# "What takes up the space".

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    # The lines of one section, as "name=value".
    function Get-TestLine {
        param([object[]]$Section, [string]$Title)
        @($Section | Where-Object { $_.Title -eq $Title } | Select-Object -First 1).Rows | ForEach-Object { '{0}={1}' -f $_.Name, $_.Text }
    }
}

Describe 'Format-ByteSize' {
    It 'formats <Bytes> bytes as <Expected>' -ForEach @(
        @{ Bytes = 0; Expected = '0 KB' }
        @{ Bytes = 512KB; Expected = '512 KB' }
        @{ Bytes = 20MB; Expected = '20 MB' }
        @{ Bytes = 1023MB; Expected = '1023 MB' }
        @{ Bytes = 1GB; Expected = '1 GB' }
        @{ Bytes = 1.3GB; Expected = '1.3 GB' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters @{ Bytes = $Bytes } { Format-ByteSize -Bytes $Bytes } | Should -Be $Expected
    }
}

Describe 'Format-DetailRow and Format-DetailSection' {
    It 'builds a line of a name and its value' {
        $row = InModuleScope HelpdeskToolkit { Format-DetailRow 'Cores' 8 }
        $row.Name | Should -Be 'Cores'
        $row.Text | Should -Be '8'
    }

    It 'adds the unit to the value' {
        (InModuleScope HelpdeskToolkit { Format-DetailRow 'Base speed' 2400 -Unit 'MHz' }).Text | Should -Be '2400 MHz'
    }

    It 'yields no line for a value that is missing, empty or blank' {
        InModuleScope HelpdeskToolkit { Format-DetailRow 'A' $null } | Should -BeNullOrEmpty
        InModuleScope HelpdeskToolkit { Format-DetailRow 'B' '' -Unit 'MHz' } | Should -BeNullOrEmpty
        InModuleScope HelpdeskToolkit { Format-DetailRow 'C' '   ' } | Should -BeNullOrEmpty
    }

    It 'keeps a value of zero, which is a value' {
        (InModuleScope HelpdeskToolkit { Format-DetailRow 'Queue' 0 }).Text | Should -Be '0'
    }

    It 'builds a section of a title and the lines that exist' {
        $section = InModuleScope HelpdeskToolkit {
            Format-DetailSection -Title 'Processor' -Row @((Format-DetailRow 'Cores' 8), $null, (Format-DetailRow 'Socket' ''))
        }
        $section.Title | Should -Be 'Processor'
        @($section.Rows).Count | Should -Be 1
        $section.Raw | Should -BeFalse
        $section.KeepNames | Should -BeFalse
    }

    It 'yields no section without lines, so nothing empty is shown' {
        InModuleScope HelpdeskToolkit { Format-DetailSection -Title 'Page file' -Row @() } | Should -BeNullOrEmpty
        InModuleScope HelpdeskToolkit { Format-DetailSection -Title 'Page file' -Row $null } | Should -BeNullOrEmpty
    }

    It 'marks a section as raw, or as one whose names are not labels' {
        (InModuleScope HelpdeskToolkit { Format-DetailSection -Raw -Title 'Win32_Processor' -Row (Format-DetailRow 'A' 1) }).Raw | Should -BeTrue
        (InModuleScope HelpdeskToolkit { Format-DetailSection -KeepNames -Title 'Displays' -Row (Format-DetailRow 'A' 1) }).KeepNames | Should -BeTrue
    }
}

Describe 'ConvertTo-DetailRow' {
    BeforeAll {
        $object = [PSCustomObject]@{
            Name           = 'Contoso Core 8'
            Architecture   = 9
            Empty          = ''
            Missing        = $null
            Blank          = '   '
            Characteristics = @(2, 4, 8)
            InstallDate    = [datetime]'2026-01-15 10:30:05'
            Long           = 'x' * 500
            PSComputerName = 'TEST-PC-01'
            CimClass       = 'root/cimv2:Win32_Processor'
            Enabled        = $false
        }
        $rows = @(InModuleScope HelpdeskToolkit -Parameters @{ Object = $object } { $Object | ConvertTo-DetailRow })
    }

    It 'lists every property that has a value, sorted by its name' {
        $rows.Name | Should -Be @('Architecture', 'Characteristics', 'Enabled', 'InstallDate', 'Long', 'Name')
    }

    It 'keeps a value of zero or "False", which are values' {
        ($rows | Where-Object Name -eq 'Enabled').Text | Should -Be 'False'
    }

    It 'writes a list as one line and a date as year-month-day' {
        ($rows | Where-Object Name -eq 'Characteristics').Text | Should -Be '2, 4, 8'
        ($rows | Where-Object Name -eq 'InstallDate').Text | Should -Be '2026-01-15 10:30:05'
    }

    It 'cuts off a very long value' {
        $long = ($rows | Where-Object Name -eq 'Long').Text
        $long.Length | Should -Be 404
        $long | Should -Match ' \.\.\.$'
    }

    It 'leaves out what describes the WMI object itself' {
        $rows.Name | Should -Not -Contain 'PSComputerName'
        $rows.Name | Should -Not -Contain 'CimClass'
    }

    It 'returns nothing for nothing' {
        @(InModuleScope HelpdeskToolkit { $null | ConvertTo-DetailRow }).Count | Should -Be 0
    }
}

Describe 'Get-ProcessorDetail' {
    BeforeAll {
        $script:cimData = @{
            Win32_Processor                                         = [PSCustomObject]@{
                Name = 'Contoso Core 8 2.40GHz  '; Manufacturer = 'Contoso'; Description = 'x64 Family 6 Model 10 Stepping 2'; Architecture = 9
                SocketDesignation = 'U3E1'; NumberOfCores = 8; NumberOfEnabledCore = 8; NumberOfLogicalProcessors = 16
                MaxClockSpeed = 2400; ExtClock = 100; L2CacheSize = 4096; L3CacheSize = 16384
                VirtualizationFirmwareEnabled = $true; VMMonitorModeExtensions = $true; SecondLevelAddressTranslationExtensions = $false
                # 0x8C: the highest bit says the rest (12) is the voltage in tenths of a volt.
                AddressWidth = 64; DataWidth = 64; CurrentVoltage = 0x8C; ProcessorId = 'BFEBFBFF000A0652'; Status = 'OK'
            }
            Win32_CacheMemory                                       = @(
                [PSCustomObject]@{ Purpose = 'L1 Cache'; InstalledSize = 512; DeviceID = 'Cache Memory 0' }
                [PSCustomObject]@{ Purpose = 'L3 Cache'; InstalledSize = 16384; DeviceID = 'Cache Memory 1' }
                [PSCustomObject]@{ Purpose = 'Unused'; InstalledSize = 0; DeviceID = 'Cache Memory 2' }
            )
            Win32_PerfFormattedData_PerfOS_Processor                = @(
                [PSCustomObject]@{ Name = '0'; PercentUserTime = 99; PercentPrivilegedTime = 99; PercentInterruptTime = 9; PercentDPCTime = 9; PercentIdleTime = 0; InterruptsPersec = 1 }
                [PSCustomObject]@{ Name = '_Total'; PercentUserTime = 21; PercentPrivilegedTime = 6; PercentInterruptTime = 1; PercentDPCTime = 0; PercentIdleTime = 72; InterruptsPersec = 5100 }
            )
            Win32_PerfFormattedData_PerfOS_System                   = [PSCustomObject]@{ ContextSwitchesPersec = 7200; SystemCallsPersec = 37000; ProcessorQueueLength = 0; Processes = 214; Threads = 3187 }
            Win32_ComputerSystem                                    = [PSCustomObject]@{ NumberOfProcessors = 1; NumberOfLogicalProcessors = 16; HypervisorPresent = $false }
            Win32_PerfFormattedData_Counters_ProcessorInformation   = [PSCustomObject]@{ Name = '_Total'; PercentofMaximumFrequency = 100; ParkingStatus = 0 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { $script:cimData[$ClassName] }
        Mock -ModuleName HelpdeskToolkit Get-PowerPlanName { 'Balanced' }

        $sections = @(InModuleScope HelpdeskToolkit { Get-ProcessorDetail })
    }

    It 'returns the sections for people first, then everything Windows reports' {
        ($sections | Where-Object { -not $_.Raw }).Title | Should -Be @('Processor', 'Cache', 'Activity right now', 'Computer')
        ($sections | Where-Object Raw).Title | Should -Contain 'Win32_Processor'
        # No raw section comes before a section for people.
        $firstRaw = [array]::IndexOf(@($sections.Raw), $true)
        @($sections | Select-Object -Skip $firstRaw | Where-Object { -not $_.Raw }).Count | Should -Be 0
    }

    It 'describes the processor: name, cores, speeds, caches and features' {
        $lines = Get-TestLine -Section $sections -Title 'Processor'
        $lines | Should -Contain 'Name=Contoso Core 8 2.40GHz'
        $lines | Should -Contain 'Architecture=x64 (64 bit)'
        $lines | Should -Contain 'Cores=8'
        $lines | Should -Contain 'Logical processors=16'
        $lines | Should -Contain 'Base speed=2400 MHz'
        $lines | Should -Contain 'L2 cache=4 MB'
        $lines | Should -Contain 'L3 cache=16 MB'
        $lines | Should -Contain 'Virtualization turned on in the firmware=Yes'
        $lines | Should -Contain 'Second level address translation=No'
        $lines | Should -Contain 'Voltage=1.2 V'
        $lines | Should -Contain 'Status=OK'
    }

    It 'lists the caches that exist, under the names Windows gives them' {
        $cache = $sections | Where-Object Title -eq 'Cache'
        Get-TestLine -Section $sections -Title 'Cache' | Should -Be @('L1 Cache=512 KB', 'L3 Cache=16 MB')
        $cache.KeepNames | Should -BeTrue
    }

    It 'says where the processor time goes, from the total of all processors' {
        $lines = Get-TestLine -Section $sections -Title 'Activity right now'
        $lines | Should -Contain 'Time spent in programs=21 %'
        $lines | Should -Contain 'Time spent in Windows itself=6 %'
        $lines | Should -Contain 'Idle=72 %'
        $lines | Should -Contain 'Switches between programs per second=7200'
        $lines | Should -Contain 'Threads waiting for a free processor=0'
    }

    It 'describes the computer around the processor, with the power plan' {
        $lines = Get-TestLine -Section $sections -Title 'Computer'
        $lines | Should -Contain 'Processor sockets in use=1'
        $lines | Should -Contain 'Runs under a hypervisor=No'
        $lines | Should -Contain 'Power plan=Balanced'
    }

    It 'lists every property of the processor under the name Windows gives it' {
        $raw = $sections | Where-Object Title -eq 'Win32_Processor'
        $raw.Raw | Should -BeTrue
        $raw.Rows.Name | Should -Contain 'MaxClockSpeed'
        $raw.Rows.Name | Should -Contain 'ProcessorId'
        @($raw.Rows).Count | Should -Be 20
    }

    It 'returns one raw section per cache and for each of the counters' {
        ($sections | Where-Object Raw).Title | Should -Contain 'Win32_CacheMemory (Cache Memory 0)'
        ($sections | Where-Object Raw).Title | Should -Contain 'Win32_PerfFormattedData_PerfOS_Processor (_Total)'
        ($sections | Where-Object Raw).Title | Should -Contain 'Win32_PerfFormattedData_Counters_ProcessorInformation (_Total)'
        ($sections | Where-Object Raw).Title | Should -Contain 'Win32_PerfFormattedData_PerfOS_System'
    }

    It 'leaves out a source that cannot be read and still returns the rest' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'Access denied' } -ParameterFilter { $ClassName -in 'Win32_CacheMemory', 'Win32_PerfFormattedData_PerfOS_System' }
        Mock -ModuleName HelpdeskToolkit Get-PowerPlanName { throw 'Registry not readable' }
        $partial = @(InModuleScope HelpdeskToolkit { Get-ProcessorDetail })

        ($partial | Where-Object { -not $_.Raw }).Title | Should -Be @('Processor', 'Activity right now', 'Computer')
        Get-TestLine -Section $partial -Title 'Activity right now' | Should -Not -Contain 'Processes=214'
        Get-TestLine -Section $partial -Title 'Computer' | Should -Not -Match '^Power plan='
    }

    It 'names the socket in the title when there are several processors' {
        $second = $script:cimData.Win32_Processor.PSObject.Copy()
        $second.SocketDesignation = 'U3E2'
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { $script:cimData.Win32_Processor; $second } -ParameterFilter { $ClassName -eq 'Win32_Processor' }

        (InModuleScope HelpdeskToolkit { Get-ProcessorDetail } | Where-Object { -not $_.Raw }).Title | Should -Contain 'Processor (U3E2)'
    }

    It 'returns nothing when Windows reports nothing at all' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'WMI is not available' }
        Mock -ModuleName HelpdeskToolkit Get-PowerPlanName { }
        @(InModuleScope HelpdeskToolkit { Get-ProcessorDetail }).Count | Should -Be 0
    }
}

Describe 'Get-MemoryDetail' {
    BeforeAll {
        $newModule = {
            param($Slot, $Serial)
            [PSCustomObject]@{
                Capacity = 8GB; SMBIOSMemoryType = 26; DeviceLocator = " $Slot "; FormFactor = 12; Speed = 2666; ConfiguredClockSpeed = 3200
                ConfiguredVoltage = 1200; Manufacturer = 'Contoso'; PartNumber = 'CT8G4SFS'; SerialNumber = $Serial; BankLabel = 'BANK 0'
                DataWidth = 64; TotalWidth = 64
            }
        }
        $script:cimData = @{
            Win32_PhysicalMemory                  = @((& $newModule 'DIMM A1' 'A001'), (& $newModule 'DIMM B1' 'B001'))
            # 64 GB in kilobytes
            Win32_PhysicalMemoryArray             = [PSCustomObject]@{ MemoryDevices = 4; MaxCapacityEx = 67108864; MaxCapacity = 67108864; MemoryErrorCorrection = 3 }
            # 16 GB minus 0.2 GB that the hardware keeps for itself, in kilobytes
            Win32_OperatingSystem                 = [PSCustomObject]@{ TotalVisibleMemorySize = (16GB - 0.2GB) / 1KB }
            Win32_PerfFormattedData_PerfOS_Memory = [PSCustomObject]@{
                AvailableBytes = 4.3GB; StandbyCacheNormalPriorityBytes = 2GB; StandbyCacheReserveBytes = 512MB; StandbyCacheCoreBytes = 512MB
                ModifiedPageListBytes = 200MB; FreeAndZeroPageListBytes = 1.25GB; CommittedBytes = 14GB; CommitLimit = 20GB
                PoolPagedBytes = 700MB; PoolNonpagedBytes = 400MB; PageFaultsPersec = 1800; PagesInputPersec = 12; PagesOutputPersec = 0
            }
            Win32_PageFileUsage                   = [PSCustomObject]@{ Name = 'C:\pagefile.sys'; AllocatedBaseSize = 4096; CurrentUsage = 100; PeakUsage = 900 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { $script:cimData[$ClassName] }

        $sections = @(InModuleScope HelpdeskToolkit { Get-MemoryDetail })
    }

    It 'returns an overview, one section per module, the usage and the page file' {
        ($sections | Where-Object { -not $_.Raw }).Title | Should -Be @('Memory', 'Module: DIMM A1', 'Module: DIMM B1', 'Usage right now', 'Page file: C:\pagefile.sys')
    }

    It 'says how much is installed, how much Windows can use and what the motherboard supports' {
        $lines = Get-TestLine -Section $sections -Title 'Memory'
        $lines | Should -Contain 'Installed=16 GB'
        $lines | Should -Contain 'Usable by Windows=15.8 GB'
        $lines | Should -Contain 'Reserved for hardware=205 MB'
        $lines | Should -Contain 'Type=DDR4'
        $lines | Should -Contain 'Slots=2 of 4 used'
        $lines | Should -Contain 'Largest amount the motherboard supports=64 GB'
        $lines | Should -Contain 'Error correction=None'
    }

    It 'describes every module with what is needed to order a matching one' {
        $lines = Get-TestLine -Section $sections -Title 'Module: DIMM B1'
        $lines | Should -Contain 'Size=8 GB'
        $lines | Should -Contain 'Type=DDR4'
        $lines | Should -Contain 'Form=SODIMM (laptop)'
        $lines | Should -Contain 'Speed of the module=2666 MHz'
        $lines | Should -Contain 'Speed it runs at=3200 MHz'
        $lines | Should -Contain 'Voltage=1.2 V'
        $lines | Should -Contain 'Part number=CT8G4SFS'
        $lines | Should -Contain 'Serial number=B001'
    }

    It 'breaks down what the memory is used for right now' {
        $lines = Get-TestLine -Section $sections -Title 'Usage right now'
        $lines | Should -Contain 'In use=11.5 GB'
        $lines | Should -Contain 'Available=4.3 GB'
        $lines | Should -Contain 'Standby (kept for reuse, given back at once)=3 GB'
        $lines | Should -Contain 'Modified (waits to be written to the disk)=200 MB'
        $lines | Should -Contain 'Committed=14 GB'
        $lines | Should -Contain 'Page faults per second=1800'
        $lines | Should -Contain 'Pages written to the disk per second=0'
    }

    It 'describes the page file' {
        Get-TestLine -Section $sections -Title 'Page file: C:\pagefile.sys' | Should -Be @('Size=4 GB', 'In use=100 MB', 'Highest use since Windows started=900 MB')
    }

    It 'lists everything Windows reports about the modules, the slots, the counters and the page file' {
        $raw = @($sections | Where-Object Raw).Title
        $raw | Should -Be @('Win32_PhysicalMemory (DIMM A1)', 'Win32_PhysicalMemory (DIMM B1)', 'Win32_PhysicalMemoryArray', 'Win32_PerfFormattedData_PerfOS_Memory', 'Win32_PageFileUsage')
    }

    It 'falls back to the older field for the largest supported amount' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { [PSCustomObject]@{ MemoryDevices = 2; MaxCapacityEx = $null; MaxCapacity = 33554432; MemoryErrorCorrection = 6 } } -ParameterFilter { $ClassName -eq 'Win32_PhysicalMemoryArray' }
        $lines = Get-TestLine -Section @(InModuleScope HelpdeskToolkit { Get-MemoryDetail }) -Title 'Memory'

        $lines | Should -Contain 'Largest amount the motherboard supports=32 GB'
        $lines | Should -Contain 'Error correction=Multi-bit ECC'
        $lines | Should -Contain 'Slots=2 of 2 used'
    }

    It 'still reports the usage on a computer that does not describe its modules (a virtual machine)' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { } -ParameterFilter { $ClassName -in 'Win32_PhysicalMemory', 'Win32_PhysicalMemoryArray', 'Win32_PageFileUsage' }
        $virtual = @(InModuleScope HelpdeskToolkit { Get-MemoryDetail })

        ($virtual | Where-Object { -not $_.Raw }).Title | Should -Be @('Memory', 'Usage right now')
        Get-TestLine -Section $virtual -Title 'Memory' | Should -Be 'Usable by Windows=15.8 GB'
    }
}

Describe 'Get-GraphicsDetail' {
    BeforeAll {
        $newAdapter = {
            param($Name, $Ram, $Width)
            [PSCustomObject]@{
                Name = $Name; AdapterRAM = $Ram; CurrentHorizontalResolution = $Width; CurrentVerticalResolution = if ($Width) { 1440 } else { $null }
                MinRefreshRate = if ($Width) { 50 } else { $null }; MaxRefreshRate = if ($Width) { 144 } else { $null }; CurrentRefreshRate = if ($Width) { 144 } else { $null }
                DriverDate = [datetime]'2026-08-20'; DriverVersion = '32.0.15.6094'; InfFilename = 'oem12.inf'
                InstalledDisplayDrivers = 'C:\WINDOWS\System32\DriverStore\ctdx.dll,C:\WINDOWS\System32\DriverStore\ctdx.dll, C:\WINDOWS\System32\DriverStore\ctgl.dll'
                AdapterCompatibility = 'Contoso'; VideoProcessor = $Name; AdapterDACType = 'Integrated RAMDAC'; CurrentBitsPerPixel = if ($Width) { 32 } else { $null }
                VideoModeDescription = if ($Width) { '2560 x 1440 x 4294967296 colors' } else { $null }; Status = 'OK'; PNPDeviceID = 'PCI\VEN_1234&DEV_0001'
            }
        }
        $engine = { param($Name, $Percent) [PSCustomObject]@{ Name = $Name; UtilizationPercentage = $Percent } }
        $memory = { param($Name, $Bytes) [PSCustomObject]@{ Name = $Name; DedicatedUsage = $Bytes; SharedUsage = 0 } }
        $text = { param([string]$Value) , ([int[]]$Value.ToCharArray() + 0, 0, 0) }

        $script:cimData = @{
            Win32_VideoController                                             = @((& $newAdapter 'Contoso Graphics 770' 4GB 2560), (& $newAdapter 'Contoso Basic Display' 1GB $null))
            Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine          = @(
                & $engine 'pid_100_luid_0x0_0x1_phys_0_eng_0_engtype_3D' 40
                & $engine 'pid_100_luid_0x0_0x1_phys_0_eng_1_engtype_VideoDecode' 10
                & $engine 'pid_200_luid_0x0_0x1_phys_0_eng_0_engtype_3D' 5
                & $engine 'pid_201_luid_0x0_0x1_phys_0_eng_0_engtype_3D' 7
                & $engine 'pid_300_luid_0x0_0x1_phys_0_eng_0_engtype_3D' 0
                & $engine 'luid_0x0_0x1_phys_0_eng_0_engtype_3D' 99
            )
            Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory   = @(
                & $memory 'pid_100_luid_0x0_0x1_phys_0' 2GB
                & $memory 'pid_200_luid_0x0_0x1_phys_0' 512MB
                & $memory 'pid_201_luid_0x0_0x1_phys_0' 100MB
                & $memory 'pid_300_luid_0x0_0x1_phys_0' 500KB
                & $memory 'pid_400_luid_0x0_0x1_phys_0' 10MB
            )
            Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory   = [PSCustomObject]@{ Name = 'luid_0x0_0x1_phys_0'; DedicatedUsage = 2GB; SharedUsage = 100MB }
            WmiMonitorID                                                      = @(
                [PSCustomObject]@{ InstanceName = 'DISPLAY\CTS0001\1_0'; UserFriendlyName = (& $text 'Contoso 24'); ManufacturerName = (& $text 'CTS'); YearOfManufacture = 2024 }
                [PSCustomObject]@{ InstanceName = 'DISPLAY\GEN0001\2_0'; UserFriendlyName = $null; ManufacturerName = $null; YearOfManufacture = $null }
            )
            WmiMonitorBasicDisplayParams                                      = [PSCustomObject]@{ InstanceName = 'DISPLAY\CTS0001\1_0'; MaxHorizontalImageSize = 53; MaxVerticalImageSize = 30 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { $script:cimData[$ClassName] }
        Mock -ModuleName HelpdeskToolkit Get-VideoMemory { [PSCustomObject]@{ Name = 'Contoso Graphics 770'; Bytes = 8GB } }
        Mock -ModuleName HelpdeskToolkit Invoke-NvidiaSmi { 'Contoso RTX, 555.10, 95.02.3c, 00000000:01:00.0, 61, [N/A], 120.50, 200.00, 45, 12, 2048, 8192' } -ParameterFilter { $Query -like 'name,*' }
        Mock -ModuleName HelpdeskToolkit Invoke-NvidiaSmi { '1500, 7000, 2800, 9500, P0, 3, [Not Supported]' } -ParameterFilter { $Query -like 'clocks*' }
        Mock -ModuleName HelpdeskToolkit Get-Process {
            switch ($Id) {
                100 { [PSCustomObject]@{ ProcessName = 'game' } }
                { $_ -in 200, 201 } { [PSCustomObject]@{ ProcessName = 'browser' } }
                300 { [PSCustomObject]@{ ProcessName = 'idle-app' } }
            }
        }

        $sections = @(InModuleScope HelpdeskToolkit { Get-GraphicsDetail })
    }

    It 'returns a section per adapter, the NVIDIA values, the programs and the displays' {
        ($sections | Where-Object { -not $_.Raw }).Title | Should -Be @(
            'Adapter: Contoso Graphics 770', 'Adapter: Contoso Basic Display', 'NVIDIA: Contoso RTX', 'Programs using the graphics card right now', 'Displays'
        )
    }

    It 'describes an adapter: maker, memory, driver and the picture it sends' {
        $lines = Get-TestLine -Section $sections -Title 'Adapter: Contoso Graphics 770'
        $lines | Should -Contain 'Maker=Contoso'
        $lines | Should -Contain 'Driver version=32.0.15.6094'
        $lines | Should -Contain 'Driver date=2026-08-20'
        $lines | Should -Contain 'Driver files=ctdx.dll, ctgl.dll'
        $lines | Should -Contain 'Resolution=2560 x 1440'
        $lines | Should -Contain 'Refresh rate=144 Hz'
        $lines | Should -Contain 'Refresh rates it supports=50 - 144 Hz'
        $lines | Should -Contain 'Color depth=32 bit'
    }

    It 'takes the memory of an adapter from its driver, which knows more than 4 GB' {
        Get-TestLine -Section $sections -Title 'Adapter: Contoso Graphics 770' | Should -Contain 'Memory of its own=8 GB'
    }

    It 'falls back to what Windows reports, and leaves out what an adapter without a display does not have' {
        $lines = Get-TestLine -Section $sections -Title 'Adapter: Contoso Basic Display'
        $lines | Should -Contain 'Memory of its own=1 GB'
        $lines | Should -Not -Match '^Resolution='
        $lines | Should -Not -Match '^Refresh rate'
    }

    It 'lists what an NVIDIA card reports, without the values it does not have' {
        $lines = Get-TestLine -Section $sections -Title 'NVIDIA: Contoso RTX'
        ($lines -join "`n") | Should -Match '(?m)^Temperature=61 .C$'
        $lines | Should -Not -Match '^Fan='
        $lines | Should -Contain 'Power draw=120.50 W'
        $lines | Should -Contain 'Load of the graphics processor=45 %'
        $lines | Should -Contain 'Memory in use=2048 MB'
        $lines | Should -Contain 'Clock of the graphics processor=1500 MHz'
        $lines | Should -Contain 'Performance state (P0 is the fastest)=P0'
        $lines | Should -Contain 'Load of the video encoder=3 %'
        $lines | Should -Not -Match '^Load of the video decoder='
        $lines | Should -Contain 'Firmware version=95.02.3c'
    }

    It 'still lists the basic NVIDIA values when an older driver does not know the newer ones' {
        Mock -ModuleName HelpdeskToolkit Invoke-NvidiaSmi { } -ParameterFilter { $Query -like 'clocks*' }
        $lines = Get-TestLine -Section @(InModuleScope HelpdeskToolkit { Get-GraphicsDetail }) -Title 'NVIDIA: Contoso RTX'

        $lines | Should -Contain 'Power limit=200.00 W'
        $lines | Should -Not -Match '^Clock of'
    }

    It 'has no NVIDIA section on a computer without such a card' {
        Mock -ModuleName HelpdeskToolkit Invoke-NvidiaSmi { } -ParameterFilter { $true }
        (InModuleScope HelpdeskToolkit { Get-GraphicsDetail }).Title | Should -Not -Match '^NVIDIA'
    }

    It 'lists the programs that use the graphics card, busiest first, with their graphics memory' {
        $programs = $sections | Where-Object Title -eq 'Programs using the graphics card right now'
        $programs.KeepNames | Should -BeTrue
        Get-TestLine -Section $sections -Title 'Programs using the graphics card right now' | Should -Be @(
            # The load of a process is that of its busiest engine.
            'game=40 %  |  2 GB graphics memory'
            # Two processes of the same program are added up.
            'browser=12 %  |  612 MB graphics memory'
            # A process that has ended in the meantime is named by its number.
            'Process 400=0 %  |  10 MB graphics memory'
        )
    }

    It 'describes the displays with their size' {
        Get-TestLine -Section $sections -Title 'Displays' | Should -Be @(
            'Contoso 24=24 inch (53 x 30 cm), maker code CTS, made in 2024'
            'Built-in or generic display=connected'
        )
    }

    It 'lists everything Windows reports about every adapter' {
        $raw = @($sections | Where-Object Raw).Title
        $raw | Should -Contain 'Win32_VideoController (Contoso Graphics 770)'
        $raw | Should -Contain 'Win32_VideoController (Contoso Basic Display)'
        $raw | Should -Contain 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory (luid_0x0_0x1_phys_0)'
    }

    It 'leaves out the parts that cannot be read and still returns the adapters' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'Not supported' } -ParameterFilter { $ClassName -ne 'Win32_VideoController' }
        Mock -ModuleName HelpdeskToolkit Get-VideoMemory { throw 'Registry not readable' }
        Mock -ModuleName HelpdeskToolkit Invoke-NvidiaSmi { throw 'The tool did not start' } -ParameterFilter { $true }
        $partial = @(InModuleScope HelpdeskToolkit { Get-GraphicsDetail })

        ($partial | Where-Object { -not $_.Raw }).Title | Should -Be @('Adapter: Contoso Graphics 770', 'Adapter: Contoso Basic Display')
        Get-TestLine -Section $partial -Title 'Adapter: Contoso Graphics 770' | Should -Contain 'Memory of its own=4 GB'
    }
}

Describe 'Get-ComponentDetail' {
    BeforeAll {
        $section = { param($Title) [PSCustomObject]@{ Title = $Title; Raw = $false; KeepNames = $false; Rows = @([PSCustomObject]@{ Name = 'A'; Text = '1' }) } }
        Mock -ModuleName HelpdeskToolkit Get-ProcessorDetail { & $section 'Processor'; & $section 'Cache' }
        Mock -ModuleName HelpdeskToolkit Get-MemoryDetail { & $section 'Memory' }
        Mock -ModuleName HelpdeskToolkit Get-GraphicsDetail { }
    }

    It 'returns the sections of the <Name> with the time they were read' -ForEach @(
        @{ Name = 'Cpu'; Titles = @('Processor', 'Cache') }
        @{ Name = 'Memory'; Titles = @('Memory') }
    ) {
        $detail = InModuleScope HelpdeskToolkit -Parameters @{ Name = $Name } { Get-ComponentDetail -Name $Name }
        $detail.Name | Should -Be $Name
        $detail.Sections.Title | Should -Be $Titles
        $detail.ReadAt | Should -BeOfType [datetime]
    }

    It 'returns an empty list when nothing can be read about a component' {
        $detail = InModuleScope HelpdeskToolkit { Get-ComponentDetail -Name 'Gpu' }
        @($detail.Sections).Count | Should -Be 0
    }

    It 'knows the processor, the memory and the graphics card, and nothing else' {
        { InModuleScope HelpdeskToolkit { Get-ComponentDetail -Name 'Disk' } } | Should -Throw
    }
}

Describe 'The labels of the detail pages' {
    BeforeAll {
        # Every label the three functions use: the name of a line, and the title of a
        # section that is written as plain text.
        $labels = foreach ($name in 'Get-ProcessorDetail', 'Get-MemoryDetail', 'Get-GraphicsDetail') {
            $file = Join-Path -Path $PSScriptRoot -ChildPath "..\..\HelpdeskToolkit\Private\$name.ps1"
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $file).Path, [ref]$null, [ref]$null)
            $calls = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)

            foreach ($call in $calls) {
                $elements = @($call.CommandElements)
                switch ($call.GetCommandName()) {
                    'Format-DetailRow' {
                        if ($elements[1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $elements[1].Value
                        }
                    }
                    'Format-DetailSection' {
                        $isRaw = @($elements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Raw' }).Count -gt 0
                        for ($index = 0; $index -lt $elements.Count - 1; $index++) {
                            $isTitle = $elements[$index] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$index].ParameterName -eq 'Title'
                            if ($isTitle -and -not $isRaw -and $elements[$index + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                                $elements[$index + 1].Value
                            }
                        }
                    }
                }
            }
        }
        $labels = @($labels | Sort-Object -Unique)
    }

    It 'finds the labels in the code' {
        $labels.Count | Should -BeGreaterThan 80
        $labels | Should -Contain 'Cores'
        $labels | Should -Contain 'Usage right now'
        $labels | Should -Not -Contain 'Win32_Processor'
    }

    It 'has a Croatian translation for every one of them' {
        try {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
            # The terms of Windows for these parts of the memory have no Croatian name in use.
            $same = 'Paged pool', 'Non-paged pool'
            $missing = @($labels | Where-Object { $same -notcontains $_ -and (InModuleScope HelpdeskToolkit -Parameters @{ Text = $_ } { Get-LocalizedText $Text }) -ceq $_ })
            $missing | Should -BeNullOrEmpty -Because 'every label of a detail page needs a Croatian translation in Lang\hr.psd1'
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
        }
    }
}

Describe 'The detail page of a component' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail { }
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }

        # A measurement as Get-PerformanceSnapshot returns it; single parts are replaced through -Change.
        function New-TestSnapshot {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([hashtable]$Change = @{})

            $parts = [ordered]@{
                TakenAt         = [datetime]'2026-01-15 10:30:05'
                Cpu             = [PSCustomObject]@{
                    Percent = 37; FrequencyMHz = 3460; BaseFrequencyMHz = 2400
                    Processors = @(
                        [PSCustomObject]@{ Name = 'CPU 0'; Percent = 12; FrequencyMHz = 3460; Parked = $false }
                        [PSCustomObject]@{ Name = 'CPU 1'; Percent = 0; FrequencyMHz = 2400; Parked = $true }
                    )
                }
                System          = [PSCustomObject]@{ Processes = 212; Threads = 3456; Handles = 98765; UptimeSeconds = 93784 }
                Memory          = [PSCustomObject]@{
                    TotalBytes = 16GB; UsedBytes = 8GB; AvailableBytes = 8GB; Percent = 50; CommittedBytes = 10GB; CommitLimitBytes = 20GB
                    CachedBytes = 5GB; PagedPoolBytes = 1GB; NonPagedPoolBytes = 512MB; PageFilePercent = 7
                }
                Gpu             = @([PSCustomObject]@{
                        Name = 'Contoso Graphics 770'; Percent = 25
                        Engines = @([PSCustomObject]@{ Name = '3D'; Percent = 25 }, [PSCustomObject]@{ Name = 'Video decode'; Percent = 4 })
                        DedicatedUsedBytes = 2GB; DedicatedTotalBytes = 8GB; SharedUsedBytes = 300MB
                    })
                GpuSensors      = @([PSCustomObject]@{ Name = 'Contoso Graphics 770'; TemperatureC = 61; FanPercent = 35; PowerWatts = 90; PowerLimitWatts = 200 })
                Disks           = @()
                Volumes         = @()
                DriveHealth     = $null
                Network         = @()
                Thermal         = @()
                Battery         = $null
                Processes       = @([PSCustomObject]@{ Name = 'contoso-app'; Percent = 18; MemoryBytes = 1GB; IoBytesPerSecond = 0 })
                MemoryProcesses = @([PSCustomObject]@{ Name = 'browser'; Percent = 2; MemoryBytes = 3GB; IoBytesPerSecond = 0 })
                IoProcesses     = @()
            }
            foreach ($key in $Change.Keys) {
                $parts[$key] = $Change[$key]
            }
            [PSCustomObject]$parts
        }

        # A window that has shown the given measurements (the last one is the newest).
        function New-TestMonitor {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds a window object in memory.')]
            param([object[]]$Snapshot = @(New-TestSnapshot))

            $window = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
            $window.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
            foreach ($entry in $Snapshot) {
                InModuleScope HelpdeskToolkit -Parameters @{ Gui = $window; Snapshot = $entry } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }
            }
            $window
        }

        function Open-TestComponent {
            param($Gui, [string]$Name)
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui; Name = $Name } { Open-WindowComponent -Gui $Gui -Name $Name }
        }

        # The lines of one live section, as "name=value".
        function Get-TestLiveLine {
            param($Gui, [string]$Title)
            @(@($Gui.Controls.ComponentLiveSections.ItemsSource) | Where-Object { $_.Title -eq $Title } | Select-Object -First 1).Rows | ForEach-Object { '{0}={1}' -f $_.Name, $_.Text }
        }

        # What Get-ComponentDetail returns, with one section of each kind.
        function New-TestDetail {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([string]$Name = 'Cpu')

            $row = { param($Label, $Text) [PSCustomObject]@{ Name = $Label; Text = $Text } }
            [PSCustomObject]@{
                Name     = $Name
                ReadAt   = [datetime]'2026-01-15 10:31:00'
                Sections = @(
                    [PSCustomObject]@{ Title = 'Module: DIMM A1'; Raw = $false; KeepNames = $false; Rows = @((& $row 'Cores' '8'), (& $row 'Runs under a hypervisor' 'Yes')) }
                    [PSCustomObject]@{ Title = 'Programs using the graphics card right now'; Raw = $false; KeepNames = $true; Rows = @((& $row 'System' '3 %  |  20 MB graphics memory')) }
                    [PSCustomObject]@{ Title = 'Win32_Processor'; Raw = $true; KeepNames = $false; Rows = @((& $row 'Status' 'OK'), (& $row 'Name' 'Contoso Core 8')) }
                )
            }
        }
    }

    Context 'the layout' {
        BeforeAll {
            $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        }

        It 'exposes the control <_>' -ForEach @(
            'MonitorCpuTile', 'MonitorMemoryTile', 'MonitorGpuTile'
            'ComponentPanel', 'ComponentBackButton', 'ComponentRefreshButton', 'ComponentState'
            'ComponentValue', 'ComponentDot', 'ComponentSummary', 'ComponentGraph', 'ComponentLine', 'ComponentArea'
            'ComponentAdviceCard', 'ComponentAdviceTitle', 'ComponentAdviceItems', 'ComponentAdviceAction'
            'ComponentLiveSections', 'ComponentSections'
        ) {
            $gui.Controls[$_] | Should -Not -BeNullOrEmpty
        }

        It 'shows by the mouse pointer and a tip that the three tiles can be clicked' {
            foreach ($name in 'MonitorCpuTile', 'MonitorMemoryTile', 'MonitorGpuTile') {
                [string]$gui.Controls[$name].Cursor | Should -Be 'Hand'
                $gui.Controls[$name].ToolTip | Should -Match '^Click to see everything about the '
            }
        }

        It 'starts with the detail page hidden' {
            $gui.Controls.ComponentPanel.Visibility | Should -Be 'Collapsed'
            $gui.MonitorComponent | Should -Be ''
        }
    }

    Context 'opening and closing' {
        BeforeEach {
            $gui = New-TestMonitor
        }

        It 'shows the page of the <Name> in place of the monitor, titled "<Title>"' -ForEach @(
            @{ Name = 'Cpu'; Title = 'Processor' }
            @{ Name = 'Memory'; Title = 'Memory' }
            @{ Name = 'Gpu'; Title = 'Graphics card' }
        ) {
            Open-TestComponent -Gui $gui -Name $Name

            $gui.MonitorComponent | Should -Be $Name
            $gui.Controls.ComponentPanel.Visibility | Should -Be 'Visible'
            $gui.Controls.MonitorPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.PageTitle.Text | Should -Be $Title
        }

        It 'draws the graph and the large number in the color of the component' {
            Open-TestComponent -Gui $gui -Name 'Memory'
            $color = [string]$gui.Window.FindResource('MemoryBrush').Color
            [string]$gui.Controls.ComponentLine.Stroke.Color | Should -Be $color
            [string]$gui.Controls.ComponentArea.Fill.Color | Should -Be $color
            [string]$gui.Controls.ComponentValue.Foreground.Color | Should -Be $color
        }

        It 'starts reading the details the first time, and says so' {
            Open-TestComponent -Gui $gui -Name 'Cpu'

            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 1 -Exactly -ParameterFilter { $Name -eq 'Cpu' }
            $gui.Controls.ComponentState.Text | Should -Be 'Reading the details ...'
            @($gui.Controls.ComponentSections.ItemsSource).Count | Should -Be 0
        }

        It 'shows what was read before at once when the page is opened again' {
            $gui.ComponentDetail['Cpu'] = @{ State = 'Done'; Detail = (New-TestDetail); Error = ''; Worker = $null; Handle = $null; FinishedAt = Get-Date }
            Open-TestComponent -Gui $gui -Name 'Cpu'

            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 0 -Exactly
            @($gui.Controls.ComponentSections.ItemsSource).Count | Should -Be 3
        }

        It 'tries again when the last reading failed' {
            $gui.ComponentDetail['Cpu'] = @{ State = 'Failed'; Detail = $null; Error = 'WMI is not available'; Worker = $null; Handle = $null; FinishedAt = Get-Date }
            Open-TestComponent -Gui $gui -Name 'Cpu'
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 1 -Exactly
        }

        It 'goes back to the monitor' {
            Open-TestComponent -Gui $gui -Name 'Gpu'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Close-WindowComponent -Gui $Gui }

            $gui.MonitorComponent | Should -Be ''
            $gui.Controls.ComponentPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.MonitorPanel.Visibility | Should -Be 'Visible'
            $gui.Controls.PageTitle.Text | Should -Be 'Live monitor'
        }

        It 'goes back with Esc' {
            Open-TestComponent -Gui $gui -Name 'Cpu'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Escape' } | Should -BeTrue
            $gui.MonitorComponent | Should -Be ''
            # With nothing left to close, Esc is not a shortcut.
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Escape' } | Should -BeFalse
        }

        It 'is left when another page is opened, and the Live monitor then opens with the monitor itself' {
            Open-TestComponent -Gui $gui -Name 'Cpu'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
            $gui.Controls.ComponentPanel.Visibility | Should -Be 'Collapsed'
            $gui.MonitorComponent | Should -Be ''

            Open-TestComponent -Gui $gui -Name 'Cpu'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Live monitor' }
            $gui.Controls.ComponentPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.MonitorPanel.Visibility | Should -Be 'Visible'
        }
    }

    Context 'the live values' {
        It 'says so when nothing has been measured yet' {
            $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
            Open-TestComponent -Gui $gui -Name 'Cpu'

            $gui.Controls.ComponentValue.Text | Should -Be '-'
            $gui.Controls.ComponentSummary.Text | Should -Be 'No measurement yet.'
            @($gui.Controls.ComponentLiveSections.ItemsSource).Count | Should -Be 0
            $gui.Controls.ComponentAdviceCard.Visibility | Should -Be 'Collapsed'
        }

        It 'shows the processor: load, speeds, counts, every logical processor and the busiest programs' {
            $gui = New-TestMonitor
            Open-TestComponent -Gui $gui -Name 'Cpu'

            $gui.Controls.ComponentValue.Text | Should -Be '37 %'
            @($gui.Controls.ComponentLiveSections.ItemsSource).Title | Should -Be @('Right now', 'Load of every logical processor', 'Busiest programs')
            Get-TestLiveLine -Gui $gui -Title 'Right now' | Should -Be @(
                'Load=37 %', 'Speed=3.5 GHz', 'Base speed=2.4 GHz', 'Logical processors=2', 'Processes=212', 'Threads=3,456', 'Handles=98,765', 'Running for=1 d 2 h'
            )
            Get-TestLiveLine -Gui $gui -Title 'Load of every logical processor' | Should -Be @(
                'CPU 0=12 %  |  3.5 GHz', 'CPU 1=0 %  |  2.4 GHz, parked by Windows to save power'
            )
            Get-TestLiveLine -Gui $gui -Title 'Busiest programs' | Should -Be 'contoso-app=18 %  |  1 GB'
        }

        It 'draws a meter for a line that is a percentage, and none for the others' {
            $gui = New-TestMonitor
            Open-TestComponent -Gui $gui -Name 'Cpu'
            $rows = (@($gui.Controls.ComponentLiveSections.ItemsSource) | Where-Object Title -eq 'Right now').Rows

            ($rows | Where-Object Name -eq 'Load').Meter | Should -Be 'Show'
            ($rows | Where-Object Name -eq 'Load').Percent | Should -Be 37
            ($rows | Where-Object Name -eq 'Load').Percent | Should -BeOfType [double]
            ($rows | Where-Object Name -eq 'Speed').Meter | Should -Be ''
        }

        It 'shows the memory: what it is used for and the programs that use the most' {
            $gui = New-TestMonitor
            Open-TestComponent -Gui $gui -Name 'Memory'

            $gui.Controls.ComponentValue.Text | Should -Be '50 %'
            Get-TestLiveLine -Gui $gui -Title 'Right now' | Should -Be @(
                'In use=8 GB of 16 GB', 'Available=8 GB', 'Cached=5 GB', 'Committed (RAM plus page file)=10 GB of 20 GB'
                'Paged pool=1 GB', 'Non-paged pool=512 MB', 'Page file=7 % used'
            )
            Get-TestLiveLine -Gui $gui -Title 'Programs that use the most memory' | Should -Be 'browser=3 GB'
        }

        It 'shows the graphics card: load per engine, memory and sensors' {
            $gui = New-TestMonitor
            Open-TestComponent -Gui $gui -Name 'Gpu'

            $gui.Controls.ComponentValue.Text | Should -Be '25 %'
            Get-TestLiveLine -Gui $gui -Title 'Right now: Contoso Graphics 770' | Should -Be @(
                'Load=25 %', '3D=25 %', 'Video decode=4 %', 'Memory of its own in use=2 GB of 8 GB', 'Borrowed RAM in use=300 MB'
            )
            $sensors = Get-TestLiveLine -Gui $gui -Title 'Sensors: Contoso Graphics 770'
            $sensors[0] | Should -Match '^Temperature=61 .C$'
            $sensors[1] | Should -Be 'Fan=35 %'
            $sensors[2] | Should -Be 'Power draw=90 W of 200 W'
        }

        It 'shows a graphics card without sensors and without a known memory size' {
            $bare = New-TestSnapshot -Change @{
                Gpu        = @([PSCustomObject]@{ Name = 'GPU 1'; Percent = 3; Engines = @(); DedicatedUsedBytes = 1GB; DedicatedTotalBytes = 0; SharedUsedBytes = 0 })
                GpuSensors = @()
            }
            $gui = New-TestMonitor -Snapshot $bare
            Open-TestComponent -Gui $gui -Name 'Gpu'

            @($gui.Controls.ComponentLiveSections.ItemsSource).Title | Should -Be 'Right now: GPU 1'
            Get-TestLiveLine -Gui $gui -Title 'Right now: GPU 1' | Should -Be @('Load=3 %', 'Memory of its own in use=1 GB')
        }

        It 'follows the measurements of the monitor while the page is open' {
            $gui = New-TestMonitor
            Open-TestComponent -Gui $gui -Name 'Cpu'
            $next = New-TestSnapshot -Change @{ Cpu = [PSCustomObject]@{ Percent = 80; FrequencyMHz = 4000; BaseFrequencyMHz = 2400; Processors = @() } }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = $next } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }

            $gui.Controls.ComponentValue.Text | Should -Be '80 %'
            $gui.Controls.ComponentLine.Points.Count | Should -Be 2
        }

        It 'explains the status dot, without advice while the value is fine' {
            $gui = New-TestMonitor
            Open-TestComponent -Gui $gui -Name 'Cpu'

            $gui.Controls.ComponentSummary.Text | Should -Be 'Fine: 37 % on average, up to 85 % is fine.'
            [string]$gui.Controls.ComponentDot.Fill.Color | Should -Be ([string]$gui.Window.FindResource('OkBrush').Color)
            $gui.Controls.ComponentAdviceCard.Visibility | Should -Be 'Collapsed'
        }

        It 'shows what to do, in red, while the value is above its limit' {
            $busy = New-TestSnapshot -Change @{ Cpu = [PSCustomObject]@{ Percent = 95; FrequencyMHz = 4000; BaseFrequencyMHz = 2400; Processors = @() } }
            $gui = New-TestMonitor -Snapshot $busy, $busy, $busy
            Open-TestComponent -Gui $gui -Name 'Cpu'

            [string]$gui.Controls.ComponentDot.Fill.Color | Should -Be ([string]$gui.Window.FindResource('CriticalBrush').Color)
            $gui.Controls.ComponentAdviceCard.Visibility | Should -Be 'Visible'
            [string]$gui.Controls.ComponentAdviceCard.Background.Color | Should -Be ([string]$gui.Window.FindResource('CriticalBackBrush').Color)
            $gui.Controls.ComponentAdviceTitle.Text | Should -Be 'Processor: how to bring the load down'
            @($gui.Controls.ComponentAdviceItems.ItemsSource).Text | Should -Contain 'The program that uses the processor most right now is contoso-app (18 %). Close it, or what it has open, if you do not need it.'
            $gui.Controls.ComponentAdviceAction.Content | Should -Be 'Open Task Manager'
        }

        It 'shows what to do, in orange, while the value is close to its limit' {
            $near = New-TestSnapshot -Change @{ Memory = [PSCustomObject]@{
                    TotalBytes = 16GB; UsedBytes = 12.8GB; AvailableBytes = 3.2GB; Percent = 80; CommittedBytes = 14GB; CommitLimitBytes = 20GB
                    CachedBytes = $null; PagedPoolBytes = $null; NonPagedPoolBytes = $null; PageFilePercent = $null
                }
            }
            $gui = New-TestMonitor -Snapshot $near, $near, $near
            Open-TestComponent -Gui $gui -Name 'Memory'

            $gui.Controls.ComponentAdviceCard.Visibility | Should -Be 'Visible'
            [string]$gui.Controls.ComponentAdviceCard.Background.Color | Should -Be ([string]$gui.Window.FindResource('WarningBackBrush').Color)
            $gui.Controls.ComponentAdviceTitle.Text | Should -Be 'Memory: how to free it'
            # A measurement without the breakdown shows the lines it has.
            Get-TestLiveLine -Gui $gui -Title 'Right now' | Should -Be @('In use=12.8 GB of 16 GB', 'Available=3.2 GB', 'Committed (RAM plus page file)=14 GB of 20 GB')
        }

        It 'does nothing while no detail page is open' {
            $gui = New-TestMonitor
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowComponent -Gui $Gui; Show-WindowComponentDetail -Gui $Gui } } | Should -Not -Throw
            $gui.Controls.ComponentValue.Text | Should -Be '-'
        }
    }

    Context 'everything that was read' {
        BeforeEach {
            $gui = New-TestMonitor
            Open-TestComponent -Gui $gui -Name 'Cpu'
            $state = $gui.ComponentDetail['Cpu']
        }

        It 'lists the sections and says when they were read' {
            $state.State = 'Done'
            $state.Detail = New-TestDetail
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowComponentDetail -Gui $Gui }

            $gui.Controls.ComponentState.Text | Should -Be 'Details read at 10:31:00; they are read again every 10 seconds.'
            $sections = @($gui.Controls.ComponentSections.ItemsSource)
            $sections.Title | Should -Be @('Module: DIMM A1', 'Programs using the graphics card right now', 'Everything Windows reports: Win32_Processor')
            $sections[0].Rows.Name | Should -Be @('Cores', 'Runs under a hypervisor')
            $sections[2].Rows.Text | Should -Be @('OK', 'Contoso Core 8')
        }

        It 'reports a reading that failed' {
            $state.State = 'Failed'
            $state.Error = 'WMI is not available'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowComponentDetail -Gui $Gui }

            $gui.Controls.ComponentState.Text | Should -Be 'The details could not be read: WMI is not available'
            @($gui.Controls.ComponentSections.ItemsSource).Count | Should -Be 0
        }

        It 'keeps the sections of the last good reading when a later one fails' {
            $state.State = 'Failed'
            $state.Error = 'WMI is not available'
            $state.Detail = New-TestDetail
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowComponentDetail -Gui $Gui }

            $gui.Controls.ComponentState.Text | Should -Match '^The details could not be read'
            @($gui.Controls.ComponentSections.ItemsSource).Count | Should -Be 3
        }

        It 'translates labels and words, but not names of things and not what Windows reports' {
            $state.State = 'Done'
            $state.Detail = New-TestDetail
            try {
                InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
                InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowComponentDetail -Gui $Gui }
                $sections = @($gui.Controls.ComponentSections.ItemsSource)

                # A label and a word
                $sections[0].Title | Should -Be 'Modul: DIMM A1'
                $sections[0].Rows[0].Name | Should -Be 'Jezgre'
                $sections[0].Rows[1].Text | Should -Be 'Da'
                # "System" is the name of a program here, not the category of the checks.
                $sections[1].Rows[0].Name | Should -Be 'System'
                # The lines of a raw section stay as Windows names them; its title is translated.
                $sections[2].Title | Should -Match ': Win32_Processor$'
                $sections[2].Title | Should -Not -Match '^Everything'
                $sections[2].Rows.Name | Should -Be @('Status', 'Name')
            }
            finally {
                InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
            }
        }
    }
}

Describe 'Invoke-WindowComponentDetail and Receive-WindowComponentDetail' -Skip:(-not $isSta) {
    BeforeAll {
        # Gives a component a finished background runspace that returns what the script produces.
        function Set-TestWorker {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only runs a short script in a background runspace.')]
            param($Gui, [string]$Name, [string]$Script, $Detail = $null)

            $worker = [powershell]::Create()
            [void]$worker.AddScript($Script)
            $state = @{ State = if ($Detail) { 'Done' } else { 'Loading' }; Detail = $Detail; Error = ''; Worker = $worker; Handle = $worker.BeginInvoke(); FinishedAt = $null }
            [void]$state.Handle.AsyncWaitHandle.WaitOne(10000)
            $Gui.ComponentDetail[$Name] = $state
        }

        $goodScript = @'
[PSCustomObject]@{
    Name = 'Cpu'; ReadAt = [datetime]'2026-01-15 10:31:00'
    Sections = @([PSCustomObject]@{ Title = 'Processor'; Raw = $false; KeepNames = $false; Rows = @([PSCustomObject]@{ Name = 'Cores'; Text = '8' }) })
}
'@
    }

    BeforeEach {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
    }

    It 'starts a background runspace for the component and marks it as being read' {
        # A module path that does not exist: the runspace fails at once instead of
        # asking this computer.
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowComponentDetail -Gui $Gui -Name 'Memory' }

            $gui.ComponentDetail['Memory'].State | Should -Be 'Loading'
            $gui.ComponentDetail['Memory'].Worker | Should -BeOfType [powershell]
        }
        finally {
            $gui.ComponentDetail['Memory'].Worker.Stop()
            $gui.ComponentDetail['Memory'].Worker.Dispose()
        }
    }

    It 'does not start a second runspace while one is working' {
        $gui.ComponentDetail['Cpu'] = @{ State = 'Loading'; Detail = $null; Error = ''; Worker = 'already reading'; Handle = $null; FinishedAt = $null }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowComponentDetail -Gui $Gui -Name 'Cpu' }
        $gui.ComponentDetail['Cpu'].Worker | Should -Be 'already reading'
    }

    It 'keeps what was read before on the screen while it reads again' {
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        $gui.ComponentDetail['Cpu'] = @{ State = 'Done'; Detail = 'the last reading'; Error = ''; Worker = $null; Handle = $null; FinishedAt = Get-Date }
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowComponentDetail -Gui $Gui -Name 'Cpu' }
            $gui.ComponentDetail['Cpu'].State | Should -Be 'Done'
            $gui.ComponentDetail['Cpu'].Detail | Should -Be 'the last reading'
        }
        finally {
            $gui.ComponentDetail['Cpu'].Worker.Stop()
            $gui.ComponentDetail['Cpu'].Worker.Dispose()
        }
    }

    It 'stores a finished reading, releases the runspace and shows the sections of the open page' {
        $gui.MonitorComponent = 'Cpu'
        Set-TestWorker -Gui $gui -Name 'Cpu' -Script $goodScript
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }

        $state = $gui.ComponentDetail['Cpu']
        $state.State | Should -Be 'Done'
        $state.Worker | Should -BeNullOrEmpty
        $state.FinishedAt | Should -BeOfType [datetime]
        @($gui.Controls.ComponentSections.ItemsSource).Title | Should -Be 'Processor'
    }

    It 'stores the reading of a component whose page is not open without drawing it' {
        $gui.MonitorComponent = 'Memory'
        $gui.ComponentDetail['Memory'] = @{ State = 'Loading'; Detail = $null; Error = ''; Worker = $null; Handle = $null; FinishedAt = $null }
        Set-TestWorker -Gui $gui -Name 'Cpu' -Script $goodScript
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }

        $gui.ComponentDetail['Cpu'].State | Should -Be 'Done'
        $gui.Controls.ComponentSections.ItemsSource | Should -BeNullOrEmpty
    }

    It 'reports a reading that failed and keeps the one before' {
        $gui.MonitorComponent = 'Cpu'
        Set-TestWorker -Gui $gui -Name 'Cpu' -Script 'Write-Error "The module could not be loaded"' -Detail ([PSCustomObject]@{ Name = 'Cpu'; ReadAt = Get-Date; Sections = @() })
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }

        $state = $gui.ComponentDetail['Cpu']
        $state.State | Should -Be 'Failed'
        $state.Error | Should -Be 'The module could not be loaded'
        $state.Detail | Should -Not -BeNullOrEmpty
        $gui.Controls.ComponentState.Text | Should -Be 'The details could not be read: The module could not be loaded'
    }

    Context 'reading again' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail { }
        }

        BeforeEach {
            $gui.MonitorComponent = 'Cpu'
            $gui.ComponentDetail['Cpu'] = @{ State = 'Done'; Detail = 'the last reading'; Error = ''; Worker = $null; Handle = $null; FinishedAt = (Get-Date).AddSeconds(-11) }
        }

        It 'reads the open component again when its last reading is older than the configured seconds' {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 1 -Exactly -ParameterFilter { $Name -eq 'Cpu' }
        }

        It 'tries again after a reading that failed' {
            $gui.ComponentDetail['Cpu'].State = 'Failed'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 1 -Exactly
        }

        It 'waits while the last reading is recent' {
            $gui.ComponentDetail['Cpu'].FinishedAt = (Get-Date).AddSeconds(-3)
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 0 -Exactly
        }

        It 'does not read again while the user has paused the monitor' {
            $gui.MonitorUserPaused = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 0 -Exactly
        }

        It 'does not read again after the page was closed' {
            $gui.MonitorComponent = ''
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowComponentDetail -Gui $Gui }
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowComponentDetail -Times 0 -Exactly
        }
    }

    It 'is called by the timer of the Live monitor' {
        Mock -ModuleName HelpdeskToolkit Receive-WindowComponentDetail { }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui }
        Should -Invoke -ModuleName HelpdeskToolkit Receive-WindowComponentDetail -Times 1 -Exactly
    }
}

Describe 'Results in the order of their severity' {
    BeforeAll {
        # The order in which the checks ran is deliberately the opposite of the severity.
        $mixed = @(
            New-TestResult -Category 'System' -Check 'First info' -Status Info
            New-TestResult -Category 'System' -Check 'First fine' -Status OK
            New-TestResult -Category 'System' -Check 'A warning' -Status Warning -Recommendation 'Look at it.'
            New-TestResult -Category 'System' -Check 'Second fine' -Status OK
            New-TestResult -Category 'System' -Check 'A critical problem' -Status Critical -Recommendation 'Fix it.'
            New-TestResult -Category 'System' -Check 'Second warning' -Status Warning -Recommendation 'Look at it.'
            New-TestResult -Category 'Network' -Check 'Network info' -Status Info
            New-TestResult -Category 'Network' -Check 'Network problem' -Status Critical -Recommendation 'Fix it.'
        )
    }

    Context 'in the window' -Skip:(-not $isSta) {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
            $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $mixed) } { Show-WindowReport -Gui $Gui -Report $Report }
        }

        BeforeEach {
            $gui.Controls.SearchBox.Text = ''
            $gui.Controls.StatusFilter.SelectedIndex = 0
        }

        It 'lists the page of a category as Critical, Warning, OK, Info' {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }
            @($gui.Controls.ResultItems.ItemsSource).Status | Should -Be @('Critical', 'Warning', 'Warning', 'OK', 'OK', 'Info')
        }

        It 'keeps the order of the checks among results with the same status' {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }
            @($gui.Controls.ResultItems.ItemsSource).SourceCheck | Should -Be @(
                'A critical problem', 'A warning', 'Second warning', 'First fine', 'Second fine', 'First info'
            )
        }

        It 'lists the Overview with all critical problems before the first warning' {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
            @($gui.Controls.ResultItems.ItemsSource).SourceCheck | Should -Be @('A critical problem', 'Network problem', 'A warning', 'Second warning')
        }

        It 'lists search results in the same order' {
            $gui.Controls.SearchBox.Text = 'i'
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }
            $statuses = @($gui.Controls.ResultItems.ItemsSource).Status

            $statuses[0] | Should -Be 'Critical'
            $statuses[-1] | Should -Be 'Info'
            ($statuses -join ' ') | Should -Match '^(Critical ?)+(Warning ?)+(OK ?)+(Info ?)+$'
        }

        It 'lists the problems of a status filter in the same order' {
            $gui.Controls.StatusFilter.SelectedIndex = 1
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }
            @($gui.Controls.ResultItems.ItemsSource).SourceCheck | Should -Be @('A critical problem', 'A warning', 'Second warning')
        }
    }

    Context 'in the HTML report' {
        BeforeAll {
            $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestReport -Result $mixed) } { ConvertTo-HealthReportHtml -Report $Report }
            # The problem list at the top names the problems too, so the last place a
            # check is named is its row in the card of its category.
            $position = { param($Name) $html.LastIndexOf($Name) }
        }

        It 'lists the card of a category as Critical, Warning, OK, Info' {
            $order = 'A critical problem', 'A warning', 'Second warning', 'First fine', 'Second fine', 'First info'
            $places = @($order | ForEach-Object { & $position $_ })

            $places | Should -Not -Contain -1
            ($places | Sort-Object) | Should -Be $places
        }

        It 'keeps the categories themselves in the order in which they ran' {
            (& $position 'Network problem') | Should -BeGreaterThan (& $position 'First info')
        }
    }
}

Describe 'A click on a program in "What takes up the space"' -Skip:(-not $isSta) {
    BeforeAll {
        # The program of these tests is not installed anywhere: there is no uninstaller
        # to start, so the click leads to the page of Windows. Whatever happens, nobody
        # is asked and nothing is started (see Uninstall.Tests.ps1 for the rest).
        Mock -ModuleName HelpdeskToolkit Get-InstalledProgram { }
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $false }
        Mock -ModuleName HelpdeskToolkit Start-Process { }
    }

    BeforeEach {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
    }

    It 'marks the programs of the list as lines that can be clicked, with a tip' {
        $volume = [PSCustomObject]@{ Name = 'C:'; Label = ''; TotalBytes = 200GB; FreeBytes = 6GB; Percent = 97 }
        $gui.DiskUsage['C:'] = @{
            Expanded = $true; State = 'Done'; Error = ''; Worker = $null; Handle = $null
            Detail = [PSCustomObject]@{
                Drive = 'C:'; ProgramCount = 1; ProgramBytes = 3GB; UnknownCount = 0; IsElevated = $true; MeasuredAt = [datetime]'2026-01-15 10:31:00'
                Programs = @([PSCustomObject]@{ Name = 'Contoso Office 16.0'; Version = '16.0'; Bytes = 3GB; Complete = $true })
                Folders = @([PSCustomObject]@{ Name = 'Windows'; Bytes = 28GB; Complete = $true })
            }
        }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Volume = $volume } { Show-WindowVolume -Gui $Gui -Volume $Volume }
        $row = @($gui.Controls.MonitorVolumes.ItemsSource)[0]

        $row.Programs[0].Kind | Should -Be 'Program'
        $row.Programs[0].Tip | Should -Be 'Click to uninstall this program: its own uninstaller starts after you confirm'
        # A folder is not a program and cannot be clicked.
        $row.Folders[0].PSObject.Properties['Kind'] | Should -BeNullOrEmpty
    }

    It 'opens Installed apps of Windows and puts the name of the program on the clipboard' {
        Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office 16.0' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -ParameterFilter { $Check -eq 'Installed programs' }
        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 1 -Exactly -ParameterFilter { $Value -eq 'Contoso Office 16.0' }
        $gui.Controls.StatusText.Text | Should -Be 'Installed apps is open. The name "Contoso Office 16.0" was copied: paste it into the search field there (Ctrl+V), then choose Uninstall.'
    }

    It 'opens the place the program list of Windows is at' {
        (InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Installed programs' -Category 'Software' }).Target | Should -Be 'ms-settings:appsfeatures'
    }

    It 'still opens the page when another program holds the clipboard' {
        Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { throw 'The clipboard is in use' }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office 16.0' } | Should -BeTrue
        $gui.Controls.StatusText.Text | Should -Be 'Installed apps is open. Look for "Contoso Office 16.0" there and choose Uninstall.'
    }

    It 'says so when Windows cannot open the page, and leaves the clipboard alone' {
        Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $false }
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office 16.0' } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 0 -Exactly
        $gui.Controls.StatusText.Text | Should -Be 'Windows could not open that place.'
    }
}
