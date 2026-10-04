# Tests for what makes the application fast: loading the module as one block, running
# the check categories side by side, measuring folders with several threads, reusing
# slow measurements in repeated checks, and showing the last report at the start.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $manifest = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit\HelpdeskToolkit.psd1')).Path

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param()

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }
}

Describe 'Loading the module' {
    BeforeAll {
        # Both ways of loading, each in a process of its own: the names of all functions
        # of the module, and what one of them returns.
        $probe = @'
Import-Module '{0}'
$module = Get-Module HelpdeskToolkit
$names = & $module {{ (Get-Command -Module HelpdeskToolkit -All | Sort-Object Name).Name }}
'{{0}}|{{1}}|{{2}}' -f @($names).Count, (@($names) -join ','), (& $module {{ Format-Gigabyte -Bytes 1610612736 }})
'@ -f $manifest

        $shell = (Get-Process -Id $PID).Path
        $previous = $env:HELPDESKTOOLKIT_LOAD_FILES
        try {
            $env:HELPDESKTOOLKIT_LOAD_FILES = '1'
            $byFile = [string](& $shell -NoProfile -Command $probe | Select-Object -Last 1)
            $env:HELPDESKTOOLKIT_LOAD_FILES = ''
            $asBlock = [string](& $shell -NoProfile -Command $probe | Select-Object -Last 1)
        }
        finally {
            $env:HELPDESKTOOLKIT_LOAD_FILES = $previous
        }
    }

    It 'defines the same functions as one block as it does file by file' {
        $asBlock | Should -Be $byFile
        [int]($asBlock -split '\|')[0] | Should -BeGreaterThan 150
    }

    It 'gives functions that work' {
        ($asBlock -split '\|')[2] | Should -Be '1.5 GB'
    }
}

Describe 'Invoke-ParallelCommand' {
    It 'runs commands of the module, private ones too, and returns their output by name and in order' {
        $jobs = [ordered]@{
            'Third'  = @{ Command = 'Format-Gigabyte'; Parameters = @{ Bytes = 3GB } }
            'First'  = @{ Command = 'Format-Gigabyte'; Parameters = @{ Bytes = 1GB } }
            'Second' = @{ Command = 'Get-ToolVersion' }
        }
        $outcome = InModuleScope HelpdeskToolkit -Parameters @{ Job = $jobs; Manifest = $manifest } {
            Invoke-ParallelCommand -Job $Job -ManifestPath $Manifest -ThrottleLimit 3
        }

        @($outcome.Keys) | Should -Be @('Third', 'First', 'Second')
        $outcome['Third'].Output | Should -Be '3 GB'
        $outcome['First'].Output | Should -Be '1 GB'
        $outcome['Second'].Output | Should -Match '^\d+\.\d+\.\d+$'
        $outcome['First'].Error | Should -BeNullOrEmpty
    }

    It 'returns the error of a command that fails and still runs the others' {
        $jobs = [ordered]@{
            'Broken' = @{ Command = 'Get-FolderSize'; Parameters = @{ NoSuchParameter = 1 } }
            'Fine'   = @{ Command = 'Format-Gigabyte'; Parameters = @{ Bytes = 2GB } }
        }
        $outcome = InModuleScope HelpdeskToolkit -Parameters @{ Job = $jobs; Manifest = $manifest } {
            Invoke-ParallelCommand -Job $Job -ManifestPath $Manifest -ThrottleLimit 2
        }

        $outcome['Broken'].Error | Should -BeOfType [System.Management.Automation.ErrorRecord]
        $outcome['Broken'].Error.Exception.Message | Should -Match 'NoSuchParameter'
        @($outcome['Broken'].Output).Count | Should -Be 0
        $outcome['Fine'].Output | Should -Be '2 GB'
    }

    It 'reports at the start and after every finished command how many are done and which are open' {
        $jobs = [ordered]@{
            'A' = @{ Command = 'Get-ToolVersion' }
            'B' = @{ Command = 'Get-ToolVersion' }
        }
        $calls = InModuleScope HelpdeskToolkit -Parameters @{ Job = $jobs; Manifest = $manifest } {
            $seen = New-Object -TypeName 'System.Collections.Generic.List[string]'
            [void](Invoke-ParallelCommand -Job $Job -ManifestPath $Manifest -ThrottleLimit 1 -OnProgress {
                    param($Done, $Total, $Open)
                    $seen.Add(('{0}/{1}:{2}' -f $Done, $Total, ($Open -join '+')))
                })
            $seen
        }

        $calls[0] | Should -Be '0/2:A+B'
        $calls[-1] | Should -Be '2/2:'
        # Two quick commands can be finished between two looks, so a call for "one of
        # two" is not certain; when there is one, it names the command that is still open.
        $calls | Where-Object { $_ -like '1/2:*' } | ForEach-Object { $_ | Should -Be '1/2:B' }
    }

    It 'really runs the commands side by side' {
        # Three commands that each wait 3 seconds: one after the other they need at least 9.
        # The waits are long, so the time the runspaces need to load the module (more on
        # a busy computer) cannot blur the difference.
        $jobs = [ordered]@{}
        foreach ($name in 'A', 'B', 'C') {
            $jobs[$name] = @{ Command = 'Start-Sleep'; Parameters = @{ Milliseconds = 3000 } }
        }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        InModuleScope HelpdeskToolkit -Parameters @{ Job = $jobs; Manifest = $manifest } {
            [void](Invoke-ParallelCommand -Job $Job -ManifestPath $Manifest -ThrottleLimit 3)
        }
        $sideBySide = $watch.Elapsed.TotalSeconds

        $sideBySide | Should -BeLessThan 7.5 -Because 'three waits of 3 seconds side by side are over long before the 9 seconds they need one after the other'
    }
}

Describe 'Get-CimInstanceBatch' {
    Context 'one class after the other (as in the tests, where the mocks are)' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Test_First' } {
                [PSCustomObject]@{ Name = 'a' }
                [PSCustomObject]@{ Name = 'b' }
            }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Test_Empty' } { }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Test_Broken' } { throw 'Counter missing' }

            $batch = InModuleScope HelpdeskToolkit { Get-CimInstanceBatch -ClassName 'Test_First', 'Test_Broken', 'Test_Empty' }
        }

        It 'returns the instances of every class under its name' {
            @($batch['Test_First'].Rows).Name | Should -Be @('a', 'b')
            $batch['Test_First'].Error | Should -BeNullOrEmpty
            @($batch['Test_Empty'].Rows).Count | Should -Be 0
            $batch['Test_Empty'].Error | Should -BeNullOrEmpty
        }

        It 'returns the error of a class that cannot be read and still reads the others' {
            $batch['Test_Broken'].Error.Exception.Message | Should -Be 'Counter missing'
            @($batch['Test_Broken'].Rows).Count | Should -Be 0
        }
    }

    Context 'all classes at the same time' {
        BeforeAll {
            # Real classes of this computer, read in the runspaces of the module.
            $outcome = InModuleScope HelpdeskToolkit {
                $script:CheckThrottleLimit = $null
                try {
                    $first = Get-CimInstanceBatch -ClassName 'Win32_OperatingSystem', 'Win32_ComputerSystem', 'Win32_NoSuchClass_HelpdeskToolkit'
                    $pool = $script:CimPool
                    $second = Get-CimInstanceBatch -ClassName 'Win32_OperatingSystem', 'Win32_ComputerSystem'
                    @{ First = $first; Second = $second; SamePool = [object]::ReferenceEquals($pool, $script:CimPool); State = [string]$script:CimPool.RunspacePoolStateInfo.State }
                }
                finally {
                    $script:CheckThrottleLimit = 1
                }
            }
        }

        It 'returns what Get-CimInstance returns' {
            @($outcome.First['Win32_OperatingSystem'].Rows).Count | Should -Be 1
            $outcome.First['Win32_OperatingSystem'].Rows[0].Caption | Should -Match 'Windows'
            $outcome.First['Win32_ComputerSystem'].Rows[0].Name | Should -Be $env:COMPUTERNAME
            $outcome.First['Win32_OperatingSystem'].Error | Should -BeNullOrEmpty
        }

        It 'returns the error of a class that does not exist and still reads the others' {
            $outcome.First['Win32_NoSuchClass_HelpdeskToolkit'].Error | Should -BeOfType [System.Management.Automation.ErrorRecord]
            @($outcome.First['Win32_NoSuchClass_HelpdeskToolkit'].Rows).Count | Should -Be 0
        }

        It 'keeps its runspaces for the next measurement' {
            $outcome.SamePool | Should -BeTrue
            $outcome.State | Should -Be 'Opened'
            $outcome.Second['Win32_ComputerSystem'].Rows[0].Name | Should -Be $env:COMPUTERNAME
        }
    }

    Context 'Get-PerformanceSnapshot' {
        BeforeAll {
            # Every class "cannot be read": the measurement still has to come back.
            Mock -ModuleName HelpdeskToolkit Get-CimInstanceBatch {
                $table = @{}
                foreach ($class in $ClassName) {
                    $failure = try { throw "No $class" } catch { $_ }
                    $table[$class] = [PSCustomObject]@{ Rows = @(); Error = $failure }
                }
                $table
            }
            Mock -ModuleName HelpdeskToolkit Get-CimInstance { }

            $snapshot = Get-PerformanceSnapshot
        }

        It 'asks for all slow classes in one go' {
            Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstanceBatch -Times 1 -Exactly -Scope Context -ParameterFilter {
                @($ClassName).Count -eq 10 -and
                $ClassName -contains 'Win32_PerfFormattedData_Counters_ProcessorInformation' -and
                $ClassName -contains 'Win32_PerfFormattedData_PerfProc_Process'
            }
        }

        It 'still returns a measurement when no class could be read' {
            $snapshot | Should -Not -BeNullOrEmpty
            $snapshot.TakenAt | Should -BeOfType [datetime]
        }
    }
}

Describe 'Get-FolderSizeBatch' {
    BeforeAll {
        $base = Join-Path -Path $TestDrive -ChildPath 'Batch'
        foreach ($folder in 'One\Deep\Deeper', 'Two', 'Empty', 'Many') {
            New-Item -Path (Join-Path -Path $base -ChildPath $folder) -ItemType Directory -Force | Out-Null
        }
        [System.IO.File]::WriteAllBytes((Join-Path -Path $base -ChildPath 'One\a.bin'), (New-Object byte[] 1000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $base -ChildPath 'One\Deep\b.bin'), (New-Object byte[] 2000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $base -ChildPath 'One\Deep\Deeper\c.bin'), (New-Object byte[] 4000))
        [System.IO.File]::WriteAllBytes((Join-Path -Path $base -ChildPath 'Two\d.bin'), (New-Object byte[] 500))
        # Enough subfolders that the threads have something to hand over to each other.
        foreach ($number in 1..40) {
            $folder = Join-Path -Path $base -ChildPath ('Many\F{0}\Inner' -f $number)
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path -Path $folder -ChildPath 'x.bin'), (New-Object byte[] 100))
        }

        $paths = 'One', 'Two', 'Empty', 'Many', 'Missing' | ForEach-Object { Join-Path -Path $base -ChildPath $_ }
        $sizes = @(InModuleScope HelpdeskToolkit -Parameters @{ Path = $paths } { Get-FolderSizeBatch -Path $Path -BudgetMs 20000 })
    }

    It 'returns one object per folder, in the order they were given' {
        $sizes.Count | Should -Be 5
        $sizes.Path | Should -Be $paths
    }

    It 'adds up the files of a folder and of all its subfolders' {
        $sizes[0].Bytes | Should -Be 7000
        $sizes[0].FileCount | Should -Be 3
        $sizes[1].Bytes | Should -Be 500
        $sizes[3].Bytes | Should -Be 4000
        $sizes[3].FileCount | Should -Be 40
    }

    It 'gives the same sizes as measuring every folder by itself' {
        foreach ($size in $sizes | Select-Object -First 4) {
            $single = InModuleScope HelpdeskToolkit -Parameters @{ Path = $size.Path } { Get-FolderSize -Path $Path -TimeoutMs 20000 }
            $size.Bytes | Should -Be $single.Bytes
            $size.FileCount | Should -Be $single.FileCount
        }
    }

    It 'calls a folder complete when it was walked through to the end' {
        $sizes.Complete | Sort-Object -Unique | Should -Be $true
    }

    It 'returns an empty folder and one that does not exist with a size of 0' {
        $sizes[2].Bytes | Should -Be 0
        $sizes[4].Bytes | Should -Be 0
    }

    It 'gives the same result with one thread as with many' {
        $one = @(InModuleScope HelpdeskToolkit -Parameters @{ Path = $paths } { Get-FolderSizeBatch -Path $Path -BudgetMs 20000 -ThrottleLimit 1 })
        $many = @(InModuleScope HelpdeskToolkit -Parameters @{ Path = $paths } { Get-FolderSizeBatch -Path $Path -BudgetMs 20000 -ThrottleLimit 8 })
        ($one.Bytes -join ',') | Should -Be ($sizes.Bytes -join ',')
        ($many.Bytes -join ',') | Should -Be ($sizes.Bytes -join ',')
    }

    It 'says so when the time was over before a folder was walked through' {
        $late = @(InModuleScope HelpdeskToolkit -Parameters @{ Path = $paths } { Get-FolderSizeBatch -Path $Path -BudgetMs 0 })
        $late.Count | Should -Be 5
        # Nothing was read: the folders that exist are not complete.
        ($late | Select-Object -First 4).Complete | Sort-Object -Unique | Should -Be $false
        ($late | Measure-Object -Property Bytes -Sum).Sum | Should -Be 0
    }

    It 'returns nothing for no folders' {
        InModuleScope HelpdeskToolkit { Get-FolderSizeBatch -Path @() } | Should -BeNullOrEmpty
    }
}

Describe 'Get-ProcessCache and Set-ProcessCache' {
    It 'returns what was remembered, with the time, while it is young enough' {
        InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'Test:Young' -Value @('a', 'b') }
        $entry = InModuleScope HelpdeskToolkit { Get-ProcessCache -Key 'Test:Young' -MaxAgeMinutes 5 }
        $entry.Value | Should -Be @('a', 'b')
        $entry.At | Should -BeOfType [datetime]
    }

    It 'returns nothing for a value that is too old' {
        InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'Test:Old' -Value 'x' }
        [System.AppDomain]::CurrentDomain.GetData('HelpdeskToolkit:Test:Old').At = (Get-Date).AddMinutes(-40)
        InModuleScope HelpdeskToolkit { Get-ProcessCache -Key 'Test:Old' -MaxAgeMinutes 30 } | Should -BeNullOrEmpty
    }

    It 'returns nothing for a key that was never set' {
        InModuleScope HelpdeskToolkit { Get-ProcessCache -Key 'Test:Never' -MaxAgeMinutes 30 } | Should -BeNullOrEmpty
    }

    It 'is seen by another runspace of the same process, which is where the checks run' {
        InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'Test:Shared' -Value 42 }
        $shell = [powershell]::Create()
        try {
            $seen = $shell.AddScript("[System.AppDomain]::CurrentDomain.GetData('HelpdeskToolkit:Test:Shared').Value").Invoke()
        }
        finally {
            $shell.Dispose()
        }
        $seen | Should -Be 42
    }
}

Describe 'Get-LoadSample' {
    It 'reads processor load, memory and the running processes' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } { [PSCustomObject]@{ Name = 'Contoso Core 8'; LoadPercentage = 12 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } { [PSCustomObject]@{ TotalVisibleMemorySize = 16GB / 1KB; FreePhysicalMemory = 8GB / 1KB } }
        Mock -ModuleName HelpdeskToolkit Get-Process { [PSCustomObject]@{ ProcessName = 'browser'; WorkingSet64 = 1GB } }

        $sample = InModuleScope HelpdeskToolkit { Get-LoadSample }
        $sample.Processors[0].LoadPercentage | Should -Be 12
        $sample.OperatingSystem.FreePhysicalMemory | Should -Be (8GB / 1KB)
        $sample.Processes[0].ProcessName | Should -Be 'browser'
        $sample.TakenAt | Should -BeOfType [datetime]
    }

    It 'leaves a part empty that cannot be read, instead of failing' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'WMI is not working' }
        Mock -ModuleName HelpdeskToolkit Get-Process { [PSCustomObject]@{ ProcessName = 'browser'; WorkingSet64 = 1GB } }

        $sample = InModuleScope HelpdeskToolkit { Get-LoadSample }
        @($sample.Processors).Count | Should -Be 0
        $sample.OperatingSystem | Should -BeNullOrEmpty
        @($sample.Processes).Count | Should -Be 1
    }
}

Describe 'Get-PCHealthReport: the categories side by side' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Write-Progress { }
        Mock -ModuleName HelpdeskToolkit Get-ChangeTimeline { }
        Mock -ModuleName HelpdeskToolkit Get-LoadSample { [PSCustomObject]@{ TakenAt = Get-Date; Processors = @('sample'); OperatingSystem = 'sample'; Processes = @('sample') } }
        # What the runspaces would return: one result per category, and a failed one.
        Mock -ModuleName HelpdeskToolkit Invoke-ParallelCommand {
            $outcome = [ordered]@{}
            foreach ($name in $Job.Keys) {
                $result = [PSCustomObject]@{ PSTypeName = 'HelpdeskToolkit.CheckResult'; Category = $name; Check = 'Test'; Description = ''; Status = 'OK'; Value = ''; Details = @(); Allowed = ''; Typical = ''; Recommendation = '' }
                $outcome[$name] = [PSCustomObject]@{ Output = @($result); Error = $null }
            }
            try { throw 'The printer service does not answer' } catch { $outcome['Printers'] = [PSCustomObject]@{ Output = @(); Error = $_ } }
            if ($OnProgress) {
                & $OnProgress 0 $Job.Count @($Job.Keys)
                & $OnProgress 8 $Job.Count @('Hardware', 'Windows Update')
                & $OnProgress $Job.Count $Job.Count @()
            }
            $outcome
        }
        # Category commands must not run in the session of the test in this mode.
        Mock -ModuleName HelpdeskToolkit Get-SystemHealth { throw 'Must run in a runspace of its own' }

        $report = Get-PCHealthReport -ThrottleLimit 4 -Days 30 -SkipNetwork -AllowCached
    }

    It 'hands every category to a runspace, with as many at a time as asked for' {
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-ParallelCommand -Times 1 -Exactly -Scope Describe -ParameterFilter {
            $ThrottleLimit -eq 4 -and $Job.Count -eq 10 -and $Job['System'].Command -eq 'Get-SystemHealth' -and (Test-Path -LiteralPath $ManifestPath)
        }
        Should -Invoke -ModuleName HelpdeskToolkit Get-SystemHealth -Times 0 -Exactly -Scope Describe
    }

    It 'passes the parameters of the check on to the categories' {
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-ParallelCommand -Scope Describe -ParameterFilter {
            $Job['Event Log'].Parameters.Days -eq 30 -and $Job['Network'].Parameters.SkipConnectivity -and
            $Job['Software'].Parameters.SkipUpdateCheck -and $Job['Hardware'].Parameters.AllowCached
        }
    }

    It 'measures the load before anything runs and gives it to the hardware category' {
        Should -Invoke -ModuleName HelpdeskToolkit Get-LoadSample -Times 1 -Exactly -Scope Describe
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-ParallelCommand -Scope Describe -ParameterFilter {
            $Job['Hardware'].Parameters.LoadSample.OperatingSystem -eq 'sample'
        }
    }

    It 'puts the results together in the order of the categories' {
        $report.Results.Category | Should -Be @('System', 'Specifications', 'Hardware', 'Software', 'Event Log', 'Windows Update', 'Security', 'Network', 'Printers', 'Services')
    }

    It 'reports a category that failed as a Warning and keeps the others' {
        $failed = $report.Results | Where-Object Category -eq 'Printers'
        $failed.Check | Should -Be 'Check execution'
        $failed.Status | Should -Be 'Warning'
        $failed.Recommendation | Should -Match 'printer service does not answer'
        @($report.Results).Count | Should -Be 10
    }

    It 'reports which categories are still running and how many are done' {
        Should -Invoke -ModuleName HelpdeskToolkit Write-Progress -Scope Describe -ParameterFilter {
            $Activity -eq 'PC Health Check' -and $Status -eq 'Hardware, Windows Update' -and $CurrentOperation -eq '8 of 10 done' -and $PercentComplete -eq 80
        }
    }

    It 'runs the categories one after the other in a copy of the module that only exists in memory' {
        Mock -ModuleName HelpdeskToolkit Get-SystemHealth { New-TestResult -Category 'System' }
        foreach ($command in 'Get-ComputerSpecification', 'Get-HardwareHealth', 'Get-SoftwareHealth', 'Get-EventLogHealth', 'Get-WindowsUpdateHealth',
            'Get-SecurityHealth', 'Get-NetworkHealth', 'Get-PrinterHealth', 'Get-ServiceHealth') {
            Mock -ModuleName HelpdeskToolkit $command { New-TestResult }
        }
        $root = InModuleScope HelpdeskToolkit { $script:ModuleRoot }
        try {
            # On another computer the module has no folder (see Get-RemoteHealthReport).
            InModuleScope HelpdeskToolkit { $script:ModuleRoot = '' }
            $remote = Get-PCHealthReport -ThrottleLimit 4
        }
        finally {
            InModuleScope HelpdeskToolkit -Parameters @{ Root = $root } { $script:ModuleRoot = $Root }
        }

        @($remote.Results).Count | Should -Be 10
        Should -Invoke -ModuleName HelpdeskToolkit Get-SystemHealth -Times 1 -Exactly
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-ParallelCommand -Times 0 -Exactly
    }

    It 'rejects a number of runspaces outside 0 - 64' {
        { Get-PCHealthReport -ThrottleLimit 65 } | Should -Throw
    }
}

Describe 'Get-HardwareHealth: measurements that are handed in or remembered' {
    BeforeAll {
        $realSystemDrive = $env:SystemDrive
        $env:SystemDrive = 'C:'

        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } { [PSCustomObject]@{ Name = 'Contoso Core 8'; LoadPercentage = 90 } }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } {
            [PSCustomObject]@{ TotalVisibleMemorySize = 16GB / 1KB; FreePhysicalMemory = 1GB / 1KB }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } { [PSCustomObject]@{ DeviceID = 'C:'; Size = 100GB; FreeSpace = 3GB } }
        foreach ($class in 'Win32_Battery', 'Win32_PnPEntity', 'Win32_PnPSignedDriver', 'MSFT_PhysicalDisk') {
            $filter = [scriptblock]::Create("`$ClassName -eq '$class'")
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter $filter { }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PageFileUsage' } { [PSCustomObject]@{ AllocatedBaseSize = 4096; CurrentUsage = 512 } }
        Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 1GB; FileCount = 40; Complete = $true } }
        Mock -ModuleName HelpdeskToolkit Get-RecycleBinSize { [PSCustomObject]@{ Bytes = 2GB; Complete = $true } }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
        Mock -ModuleName HelpdeskToolkit Get-Process { [PSCustomObject]@{ ProcessName = 'the-check-itself'; WorkingSet64 = 9GB } }
        Mock -ModuleName HelpdeskToolkit Get-ChildItem { }
        Mock -ModuleName HelpdeskToolkit Get-BatteryCapacity { }
        Mock -ModuleName HelpdeskToolkit Get-MemoryDiagnosticResult { }
        Mock -ModuleName HelpdeskToolkit Get-LargestFolder { [PSCustomObject]@{ Name = 'Measured now'; Bytes = 50GB; Complete = $true } }

        $sample = [PSCustomObject]@{
            TakenAt         = Get-Date
            Processors      = @([PSCustomObject]@{ Name = 'Contoso Core 8'; LoadPercentage = 10 })
            OperatingSystem = [PSCustomObject]@{ TotalVisibleMemorySize = 16GB / 1KB; FreePhysicalMemory = 8GB / 1KB }
            Processes       = @([PSCustomObject]@{ ProcessName = 'browser'; WorkingSet64 = 2GB })
        }
    }

    AfterAll {
        $env:SystemDrive = $realSystemDrive
    }

    It 'reports the load that was measured before the check, not the one during it' {
        $results = Get-HardwareHealth -LoadSample $sample
        ($results | Where-Object Check -eq 'CPU load').Value | Should -Be '10 % (Contoso Core 8)'
        ($results | Where-Object Check -eq 'Memory usage').Value | Should -Be '50 % (8 GB of 16 GB used)'
        ($results | Where-Object Check -eq 'Top memory consumers').Value | Should -Be 'browser (2 GB)'
    }

    It 'measures by itself without a sample' {
        $results = Get-HardwareHealth
        ($results | Where-Object Check -eq 'CPU load').Value | Should -Be '90 % (Contoso Core 8)'
        ($results | Where-Object Check -eq 'Top memory consumers').Value | Should -Be 'the-check-itself (9 GB)'
    }

    It 'measures a part itself that the sample could not read' {
        $partial = [PSCustomObject]@{ TakenAt = Get-Date; Processors = @(); OperatingSystem = $null; Processes = @() }
        $results = Get-HardwareHealth -LoadSample $partial
        ($results | Where-Object Check -eq 'CPU load').Value | Should -Be '90 % (Contoso Core 8)'
        ($results | Where-Object Check -eq 'Memory usage').Value | Should -Be '94 % (15 GB of 16 GB used)'
    }

    It 'measures the largest folders anew for a check that was asked for' {
        InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'LargestFolders:C:' -Value @([PSCustomObject]@{ Name = 'Remembered'; Bytes = 40GB; Complete = $true }) }
        (Get-HardwareHealth | Where-Object Check -eq 'Largest folders (C:)').Value | Should -Be 'Measured now 50 GB'
    }

    It 'uses the remembered folders in a repeated check, without walking through the drive' {
        InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'LargestFolders:C:' -Value @([PSCustomObject]@{ Name = 'Remembered'; Bytes = 40GB; Complete = $true }) }
        (Get-HardwareHealth -AllowCached | Where-Object Check -eq 'Largest folders (C:)').Value | Should -Be 'Remembered 40 GB'
        Should -Invoke -ModuleName HelpdeskToolkit Get-LargestFolder -Times 0 -Exactly
    }

    It 'measures again once what was remembered is older than the configuration allows' {
        InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'LargestFolders:C:' -Value @([PSCustomObject]@{ Name = 'Remembered'; Bytes = 40GB; Complete = $true }) }
        [System.AppDomain]::CurrentDomain.GetData('HelpdeskToolkit:LargestFolders:C:').At = (Get-Date).AddMinutes(-31)
        (Get-HardwareHealth -AllowCached | Where-Object Check -eq 'Largest folders (C:)').Value | Should -Be 'Measured now 50 GB'
    }

    It 'remembers what it measured' {
        Get-HardwareHealth | Out-Null
        [System.AppDomain]::CurrentDomain.GetData('HelpdeskToolkit:LargestFolders:C:').Value[0].Name | Should -Be 'Measured now'
    }
}

Describe 'Get-AppSetting: the options of a check' {
    BeforeEach {
        $path = InModuleScope HelpdeskToolkit { Get-AppDataPath -ChildPath 'settings.json' }
        New-Item -Path (Split-Path -Path $path -Parent) -ItemType Directory -Force | Out-Null
    }

    It 'starts with the network tests on and a history period of 7 days' {
        if (Test-Path -LiteralPath $path) { [System.IO.File]::Delete($path) }
        $settings = InModuleScope HelpdeskToolkit { Get-AppSetting }
        $settings.SkipNetwork | Should -BeFalse
        $settings.HistoryDays | Should -Be 7
    }

    It 'remembers what was chosen' {
        $settings = InModuleScope HelpdeskToolkit { Get-AppSetting }
        $settings.SkipNetwork = $true
        $settings.HistoryDays = 30
        InModuleScope HelpdeskToolkit -Parameters @{ Setting = $settings } { [void](Save-AppSetting -Setting $Setting) }

        $loaded = InModuleScope HelpdeskToolkit { Get-AppSetting }
        $loaded.SkipNetwork | Should -BeTrue
        $loaded.HistoryDays | Should -Be 30
    }

    It 'falls back to the defaults for values the window does not offer' {
        Set-Content -LiteralPath $path -Value '{ "SkipNetwork": "maybe", "HistoryDays": 8 }'
        $settings = InModuleScope HelpdeskToolkit { Get-AppSetting }
        $settings.SkipNetwork | Should -BeFalse
        $settings.HistoryDays | Should -Be 7
    }
}

Describe 'Get-LastHealthReport' {
    BeforeAll {
        function Save-TestHistory {
            param([int]$Day, [string]$Computer = 'TEST-PC-01')
            $report = New-TestReport -Result @(New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value "day $Day")
            $report.ComputerName = $Computer
            $report.GeneratedAt = '2026-01-{0:00} 10:30:00' -f $Day
            InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { [void](Save-HealthReportHistory -Report $Report) }
        }

        function Get-TestLastReport {
            param([string]$Computer)
            InModuleScope HelpdeskToolkit -Parameters @{ Computer = $Computer } { Get-LastHealthReport -ComputerName $Computer }
        }
    }

    It 'returns nothing before the first check' {
        Get-TestLastReport -Computer 'NEVER-CHECKED' | Should -BeNullOrEmpty
    }

    It 'returns the newest report of the computer' {
        Save-TestHistory -Day 3
        Save-TestHistory -Day 9
        Save-TestHistory -Day 5
        Save-TestHistory -Day 20 -Computer 'OTHER-PC'

        $last = Get-TestLastReport -Computer 'TEST-PC-01'
        $last.GeneratedAt | Should -Be '2026-01-09 10:30:00'
        $last.Results[0].Value | Should -Be 'day 9'
    }

    It 'returns nothing when the stored report is damaged' {
        $folder = InModuleScope HelpdeskToolkit { Get-AppDataPath -ChildPath 'History' }
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'PCHealth_BROKEN-PC_20260101-103000.json') -Value 'not json {'
        Get-TestLastReport -Computer 'BROKEN-PC' | Should -BeNullOrEmpty
    }
}

Describe 'The last report at the start of the window' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Save-HealthReportHistory { }

        $old = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status Warning -Value '9 d' -Recommendation 'Restart.'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status OK -Value '50 % free'
        )
        $old.GeneratedAt = '2026-01-14 08:00:00'
        $fresh = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 h'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free' -Recommendation 'Free up space.'
        )
        $fresh.PSObject.TypeNames.Insert(0, 'HelpdeskToolkit.HealthReport')

        # Finishes the check that is "running" in the window with the given report.
        function Complete-TestCheck {
            param($Gui, $Report)
            $Gui.Worker = [powershell]::Create()
            [void]$Gui.Worker.AddScript('param($Report) $Report').AddArgument($Report)
            $Gui.Handle = $Gui.Worker.BeginInvoke()
            [void]$Gui.Handle.AsyncWaitHandle.WaitOne(15000)
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui } { Receive-WindowCheck -Gui $Gui }
        }
    }

    It 'shows nothing when this computer was never checked' {
        Mock -ModuleName HelpdeskToolkit Get-LastHealthReport { }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowLastReport -Gui $Gui } | Should -BeFalse
        $gui.Report | Should -BeNullOrEmpty
        $gui.StaleReport | Should -BeFalse
    }

    It 'shows the last report at once and says from when it is' {
        Mock -ModuleName HelpdeskToolkit Get-LastHealthReport { $old }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowLastReport -Gui $Gui } | Should -BeTrue

        $gui.Report.GeneratedAt | Should -Be '2026-01-14 08:00:00'
        $gui.StaleReport | Should -BeTrue
        $gui.Controls.StatusText.Text | Should -Be 'These are the results of the last check (2026-01-14 08:00:00). They are replaced as soon as a new check has finished.'
        $gui.Controls.ComputerText.Text | Should -Match 'checked 2026-01-14 08:00:00'
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Contain 'Hardware'
    }

    It 'does not replace a report that is on the screen already' {
        Mock -ModuleName HelpdeskToolkit Get-LastHealthReport { $old }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $fresh } { Show-WindowReport -Gui $Gui -Report $Report }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowLastReport -Gui $Gui } | Should -BeFalse
        $gui.Report.GeneratedAt | Should -Be $fresh.GeneratedAt
    }

    It 'does not start the automatic check by itself: the old report is no check of this start' {
        Mock -ModuleName HelpdeskToolkit Get-LastHealthReport { $old }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { [void](Show-WindowLastReport -Gui $Gui) }
        $gui.LastCheckAt | Should -BeNullOrEmpty
    }

    It 'replaces it with the new results without leaving the page that is open' {
        Mock -ModuleName HelpdeskToolkit Get-LastHealthReport { $old }
        Mock -ModuleName HelpdeskToolkit Get-PreviousHealthReport { $old }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } {
            [void](Show-WindowLastReport -Gui $Gui)
            Show-WindowPage -Gui $Gui -Name 'Hardware'
        }
        Complete-TestCheck -Gui $gui -Report $fresh

        $gui.Report.GeneratedAt | Should -Be $fresh.GeneratedAt
        $gui.StaleReport | Should -BeFalse
        $gui.Page | Should -Be 'Hardware'
        @($gui.Controls.ProblemItems.ItemsSource | Where-Object Status -eq 'Critical').SourceCheck | Should -Be 'Disk (C:)'
        # It was a check of its own, not one of the repeated ones: it says so and is kept.
        $gui.Controls.StatusText.Text | Should -Match '^Check finished: 2 results\.'
        Should -Invoke -ModuleName HelpdeskToolkit Save-HealthReportHistory -Times 1 -Exactly
    }

    It 'shows what changed since the report that was on the screen' {
        Mock -ModuleName HelpdeskToolkit Get-LastHealthReport { $old }
        Mock -ModuleName HelpdeskToolkit Get-PreviousHealthReport { $old }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { [void](Show-WindowLastReport -Gui $Gui) }
        Complete-TestCheck -Gui $gui -Report $fresh

        $gui.PreviousReport.GeneratedAt | Should -Be '2026-01-14 08:00:00'
        $gui.Controls.ChangesBorder.Visibility | Should -Be 'Visible'
        @($gui.Controls.ChangesItems.ItemsSource).Count | Should -Be 2
    }

    It 'goes to the Overview after a check when no older report was shown, as before' {
        Mock -ModuleName HelpdeskToolkit Get-PreviousHealthReport { }
        $gui = New-TestWindow
        Complete-TestCheck -Gui $gui -Report $fresh
        $gui.Page | Should -Be 'Overview'
        $gui.Controls.StatusText.Text | Should -Match '^Check finished: 2 results\.'
    }
}

Describe 'The progress of a check whose categories run side by side' -Skip:(-not $isSta) {
    BeforeAll {
        function Show-TestProgress {
            param([string]$Status, [string]$Operation, [int]$Percent)
            $gui = New-TestWindow
            $gui.Worker = [powershell]::Create()
            [void]$gui.Worker.AddScript("Write-Progress -Activity 'PC Health Check' -Status '$Status' -CurrentOperation '$Operation' -PercentComplete $Percent; Start-Sleep -Seconds 30")
            $gui.Handle = $gui.Worker.BeginInvoke()
            try {
                $deadline = (Get-Date).AddSeconds(15)
                while ($gui.Worker.Streams.Progress.Count -lt 1 -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Milliseconds 50
                }
                InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }
            }
            finally {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
            $gui
        }
    }

    It 'names the categories that are still running once only a few are left' {
        $gui = Show-TestProgress -Status 'Hardware, Windows Update' -Operation '8 of 10 done' -Percent 80
        $gui.Controls.RunTitle.Text | Should -Be 'Checking: Hardware, Windows Update'
        $gui.Controls.RunStep.Text | Should -Be '8 of 10 done'
        $gui.Controls.RunPercent.Text | Should -Be '80 %'
    }

    It 'only says how many are running while there are many' {
        $gui = Show-TestProgress -Status 'System, Specifications, Hardware, Software, Event Log' -Operation '5 of 10 done' -Percent 50
        $gui.Controls.RunTitle.Text | Should -Be 'Checking 5 categories at the same time ...'
        $gui.Controls.RunStep.Text | Should -Be '5 of 10 done'
    }
}

Describe 'A repeated check and a check that was asked for' -Skip:(-not $isSta) {
    It 'lets only the repeated check reuse what was measured earlier' {
        foreach ($background in $true, $false) {
            $gui = New-TestWindow
            try {
                # The module is never loaded: the runspace gets a manifest that does not exist.
                $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'missing.psd1'
                InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Background = $background } { Invoke-WindowCheck -Gui $Gui -Background:$Background }
                $arguments = @($gui.Worker.Commands.Commands[0].Parameters | ForEach-Object { $_.Value })
                $arguments[-1] | Should -Be $background -Because 'the last argument of the check is whether it may use remembered measurements'
            }
            finally {
                $gui.Timer.Stop()
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }
}
