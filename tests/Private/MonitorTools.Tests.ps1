# Tests for the tools of the Live monitor page: pause, refresh rate, recording into a
# file, warnings, the network and disk graphs and the details of a program.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    # The test limits warn above 90 % after three measurements in a row.
    Set-TestThreshold

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param()

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.OutputFolder = Join-Path -Path $TestDrive -ChildPath 'Recordings'
        $gui
    }

    # A snapshot as Get-PerformanceSnapshot returns it; single parts are replaced through -Change.
    function New-TestSnapshot {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([hashtable]$Change = @{})

        $parts = [ordered]@{
            TakenAt         = [datetime]'2026-01-15 10:30:05'
            Cpu             = [PSCustomObject]@{ Percent = 37; FrequencyMHz = 3460; BaseFrequencyMHz = 2400; Processors = @() }
            System          = [PSCustomObject]@{ Processes = 212; Threads = 3456; Handles = 98765; UptimeSeconds = 93784 }
            Memory          = [PSCustomObject]@{
                TotalBytes = 16GB; UsedBytes = 8GB; AvailableBytes = 8GB; Percent = 50; CommittedBytes = 10GB; CommitLimitBytes = 20GB
                CachedBytes = 5GB; PagedPoolBytes = 1GB; NonPagedPoolBytes = 512MB; PageFilePercent = 7
            }
            Gpu             = @([PSCustomObject]@{ Name = 'Contoso Graphics 770'; Percent = 25; Engines = @(); DedicatedUsedBytes = 2GB; DedicatedTotalBytes = 8GB; SharedUsedBytes = 0 })
            GpuSensors      = @([PSCustomObject]@{ Name = 'Contoso Graphics 770'; TemperatureC = 61; FanPercent = 35; PowerWatts = 90; PowerLimitWatts = 200 })
            Disks           = @(
                [PSCustomObject]@{ Name = 'Disk 0 (C:)'; Percent = 12; ReadBytesPerSecond = 2MB; WriteBytesPerSecond = 512KB; QueueLength = 0 }
                [PSCustomObject]@{ Name = 'Disk 1 (D:)'; Percent = 40; ReadBytesPerSecond = 1MB; WriteBytesPerSecond = 512KB; QueueLength = 0 }
            )
            Volumes         = @()
            DriveHealth     = [PSCustomObject]@{ State = 'RequiresAdmin'; Message = ''; Drives = @() }
            Network         = @(
                [PSCustomObject]@{ Name = 'Contoso Ethernet'; ReceivedBytesPerSecond = 125000; SentBytesPerSecond = 25000; LinkBitsPerSecond = 1000000000 }
                [PSCustomObject]@{ Name = 'Contoso Wi-Fi'; ReceivedBytesPerSecond = 125000; SentBytesPerSecond = 0; LinkBitsPerSecond = 0 }
            )
            Thermal         = @()
            Battery         = $null
            Processes       = @([PSCustomObject]@{ Name = 'contoso-app'; Percent = 18; MemoryBytes = 1GB; IoBytesPerSecond = 0 })
            MemoryProcesses = @([PSCustomObject]@{ Name = 'browser'; Percent = 2; MemoryBytes = 3GB; IoBytesPerSecond = 0 })
            IoProcesses     = @([PSCustomObject]@{ Name = 'backup'; Percent = 1; MemoryBytes = 50MB; IoBytesPerSecond = 3MB })
        }
        foreach ($key in $Change.Keys) {
            $parts[$key] = $Change[$key]
        }
        [PSCustomObject]$parts
    }

    # Histories as the window keeps them, filled with the given values.
    function New-TestHistory {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([double[]]$Cpu = @(), [double[]]$Memory = @(), [double[]]$Disk = @())

        $history = @{}
        foreach ($name in 'Cpu', 'Memory', 'Gpu', 'Disk', 'NetworkDown', 'NetworkUp') {
            $history[$name] = New-Object -TypeName 'System.Collections.Generic.List[double]'
        }
        $Cpu | ForEach-Object { $history.Cpu.Add($_) }
        $Memory | ForEach-Object { $history.Memory.Add($_) }
        $Disk | ForEach-Object { $history.Disk.Add($_) }
        $history
    }
}

Describe 'Get-MonitorAlert' {
    It 'gives no warning while everything is calm' {
        $history = New-TestHistory -Cpu 20, 30, 25 -Memory 50, 50, 50 -Disk 5, 5, 5
        @(InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = (New-TestSnapshot) } { Get-MonitorAlert -History $History -Snapshot $Snapshot }).Count | Should -Be 0
    }

    It 'warns when the processor stayed above the limit, and names the busiest program' {
        $history = New-TestHistory -Cpu 40, 95, 97, 99
        InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = (New-TestSnapshot) } { Get-MonitorAlert -History $History -Snapshot $Snapshot } |
            Should -Be 'The processor has been above 90 % for the last 3 measurements. Busiest program: contoso-app (18 %).'
    }

    It 'does not warn about a single high value' {
        $history = New-TestHistory -Cpu 95, 97, 50, 99
        @(InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = (New-TestSnapshot) } { Get-MonitorAlert -History $History -Snapshot $Snapshot }).Count | Should -Be 0
    }

    It 'does not warn before enough measurements were taken' {
        $history = New-TestHistory -Cpu 99, 99
        @(InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = (New-TestSnapshot) } { Get-MonitorAlert -History $History -Snapshot $Snapshot }).Count | Should -Be 0
    }

    It 'warns when the memory stayed full, and names the program that uses the most' {
        $history = New-TestHistory -Memory 92, 93, 94
        InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = (New-TestSnapshot) } { Get-MonitorAlert -History $History -Snapshot $Snapshot } |
            Should -Be 'The memory has been more than 90 % full for the last 3 measurements. Program using the most memory: browser (3 GB).'
    }

    It 'warns when a disk stayed busy, and names the program that reads and writes the most' {
        $history = New-TestHistory -Disk 100, 98, 99
        InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = (New-TestSnapshot) } { Get-MonitorAlert -History $History -Snapshot $Snapshot } |
            Should -Be 'A disk has been busy above 90 % for the last 3 measurements. Program reading and writing the most: backup (3 MB/s).'
    }

    It 'warns at once when the graphics card is too hot' {
        $hot = New-TestSnapshot -Change @{ GpuSensors = @([PSCustomObject]@{ Name = 'Contoso Graphics 770'; TemperatureC = 91; FanPercent = 100; PowerWatts = 190; PowerLimitWatts = 200 }) }
        InModuleScope HelpdeskToolkit -Parameters @{ History = (New-TestHistory); Snapshot = $hot } { Get-MonitorAlert -History $History -Snapshot $Snapshot } |
            Should -Match '^The graphics card Contoso Graphics 770 is at 91 .C\. Check that its fans turn'
    }

    It 'returns several warnings when several things are wrong' {
        $history = New-TestHistory -Cpu 95, 95, 95 -Memory 95, 95, 95
        @(InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = (New-TestSnapshot) } { Get-MonitorAlert -History $History -Snapshot $Snapshot }).Count | Should -Be 2
    }

    It 'still warns when no program can be named' {
        $history = New-TestHistory -Cpu 95, 95, 95
        $noPrograms = New-TestSnapshot -Change @{ Processes = @() }
        InModuleScope HelpdeskToolkit -Parameters @{ History = $history; Snapshot = $noPrograms } { Get-MonitorAlert -History $History -Snapshot $Snapshot } |
            Should -Be 'The processor has been above 90 % for the last 3 measurements.'
    }
}

Describe 'Get-ProgramDetail' {
    BeforeAll {
        # A process as Get-Process returns it.
        function New-TestProcess {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param($Path, $StartTime, [long]$Memory, [int]$ThreadCount)

            [PSCustomObject]@{ Path = $Path; StartTime = $StartTime; WorkingSet64 = $Memory; Threads = @(1..$ThreadCount) }
        }

        $program = Join-Path -Path $env:SystemRoot -ChildPath 'System32\notepad.exe'
    }

    It 'adds up the processes of the program and returns the earliest start' {
        Mock -ModuleName HelpdeskToolkit Get-Process {
            New-TestProcess -Path $program -StartTime ([datetime]'2026-01-15 09:00:00') -Memory 1GB -ThreadCount 10
            New-TestProcess -Path $program -StartTime ([datetime]'2026-01-15 08:15:30') -Memory 512MB -ThreadCount 5
        }
        $details = @(InModuleScope HelpdeskToolkit { Get-ProgramDetail -Name 'notepad' })

        ($details | Where-Object Name -eq 'Processes').Text | Should -Be '2'
        ($details | Where-Object Name -eq 'Threads').Text | Should -Be '15'
        ($details | Where-Object Name -eq 'Memory in use').Text | Should -Be '1.5 GB'
        ($details | Where-Object Name -eq 'Running since').Text | Should -Be '2026-01-15 08:15:30'
    }

    It 'returns the program file once, with what the file says about itself' {
        Mock -ModuleName HelpdeskToolkit Get-Process {
            New-TestProcess -Path $program -StartTime (Get-Date) -Memory 1MB -ThreadCount 1
            New-TestProcess -Path $program -StartTime (Get-Date) -Memory 1MB -ThreadCount 1
        }
        $details = @(InModuleScope HelpdeskToolkit { Get-ProgramDetail -Name 'notepad' })

        ($details | Where-Object Name -eq 'Program file').Text | Should -Be $program
        ($details | Where-Object Name -eq 'Maker').Text | Should -Match 'Microsoft'
    }

    It 'says that path and start time are not available for a protected process' {
        Mock -ModuleName HelpdeskToolkit Get-Process { New-TestProcess -Path $null -StartTime $null -Memory 100MB -ThreadCount 4 }
        $details = @(InModuleScope HelpdeskToolkit { Get-ProgramDetail -Name 'System' })

        ($details | Where-Object Name -eq 'Program file').Text | Should -Be 'not available without administrator rights'
        ($details | Where-Object Name -eq 'Running since').Text | Should -Be 'not available without administrator rights'
        $details | Where-Object Name -eq 'Maker' | Should -BeNullOrEmpty
    }

    It 'returns nothing for a program that has ended' {
        Mock -ModuleName HelpdeskToolkit Get-Process { }
        @(InModuleScope HelpdeskToolkit { Get-ProgramDetail -Name 'gone' }).Count | Should -Be 0
    }
}

Describe 'Show-WindowProgram' -Skip:(-not $isSta) {
    It 'shows the details below the program lists' {
        Mock -ModuleName HelpdeskToolkit Get-ProgramDetail { [PSCustomObject]@{ Name = 'Processes'; Text = '3' } }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowProgram -Gui $Gui -Name 'browser' }

        $gui.Controls.MonitorProgramTitle.Text | Should -Be 'browser'
        @($gui.Controls.MonitorProgramDetails.ItemsSource).Text | Should -Be '3'
        $gui.Controls.MonitorProgramCard.Visibility | Should -Be 'Visible'
        $gui.Controls.MonitorProgramHint.Visibility | Should -Be 'Collapsed'
    }

    It 'says so when the program has ended in the meantime' {
        Mock -ModuleName HelpdeskToolkit Get-ProgramDetail { }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowProgram -Gui $Gui -Name 'gone' }
        @($gui.Controls.MonitorProgramDetails.ItemsSource).Text | Should -Be 'The program is no longer running.'
    }
}

Describe 'Switch-WindowMonitorPause' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        $gui.Monitor = @{ Shared = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; IntervalSeconds = 2 }); LastSequence = 0 }
    }

    It 'pauses the measurements and offers to resume' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowMonitorPause -Gui $Gui }

        $gui.MonitorUserPaused | Should -BeTrue
        $gui.Monitor.Shared.Paused | Should -BeTrue
        $gui.Controls.MonitorPauseButton.Content | Should -Be 'Resume'
        [int][char]$gui.Controls.MonitorPauseButton.Tag | Should -Be 0xE768
        $gui.Controls.PageSubtitle.Text | Should -Match '^Paused'
    }

    It 'stays paused when the page is opened again' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Enable-WindowMonitor -Gui $Gui }
        $gui.Monitor.Shared.Paused | Should -BeTrue
    }

    It 'resumes on the next click' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowMonitorPause -Gui $Gui }

        $gui.MonitorUserPaused | Should -BeFalse
        $gui.Monitor.Shared.Paused | Should -BeFalse
        $gui.Controls.MonitorPauseButton.Content | Should -Be 'Pause'
        [int][char]$gui.Controls.MonitorPauseButton.Tag | Should -Be 0xE769
    }

    It 'can be used before the monitor was started' {
        $fresh = New-TestWindow
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $fresh } { Switch-WindowMonitorPause -Gui $Gui } } | Should -Not -Throw
        $fresh.MonitorUserPaused | Should -BeTrue
    }
}

Describe 'Enable-WindowMonitor: refresh rate' -Skip:(-not $isSta) {
    It 'hands the refresh rate of the settings to the background loop' {
        $gui = New-TestWindow
        $gui.Settings = @{ Language = 'en'; Theme = 'System'; MonitorIntervalSeconds = 10; AutoCheckMinutes = 5; StartupElevation = 'Ask' }
        # A module path that does not exist: the loop cannot measure this computer.
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Enable-WindowMonitor -Gui $Gui }
            $gui.Monitor.Shared.IntervalSeconds | Should -Be 10
        }
        finally {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui -Stop }
        }
    }
}

Describe 'Recording the Live monitor' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        $gui.Monitor = @{ Shared = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; IntervalSeconds = 2 }); LastSequence = 0; Worker = $null }
        $path = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Enable-WindowRecording -Gui $Gui -Minutes 5 }
        $delimiter = [string][cultureinfo]::CurrentCulture.TextInfo.ListSeparator
    }

    It 'creates the file in the report folder, named after the computer and the time' {
        $path | Should -Exist
        Split-Path -Path $path -Parent | Should -Be (Join-Path -Path $TestDrive -ChildPath 'Recordings')
        Split-Path -Path $path -Leaf | Should -Match ('^Monitor_{0}_\d{{8}}-\d{{6}}\.csv$' -f [regex]::Escape($env:COMPUTERNAME))
    }

    It 'writes the header line at once, with a byte order mark for Excel' {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0], $bytes[1], $bytes[2] | Should -Be @(0xEF, 0xBB, 0xBF)
        (Get-Content -LiteralPath $path -TotalCount 1) | Should -Be (('Time', 'CpuPercent', 'CpuSpeedMHz', 'MemoryPercent', 'MemoryUsedMB', 'GpuPercent', 'GpuTemperatureC',
                'DiskActivePercent', 'DiskReadKBps', 'DiskWriteKBps', 'NetworkDownKbps', 'NetworkUpKbps', 'BusiestProgram', 'BusiestProgramPercent',
                'PingRouterMs', 'PingInternetMs') -join $delimiter)
    }

    It 'turns the button into "Stop recording" and says where it records' {
        $gui.Controls.MonitorRecordButton.Content | Should -Be 'Stop recording'
        $gui.Controls.MonitorRecordMinutes.IsEnabled | Should -BeFalse
        $gui.Controls.MonitorRecordText.Visibility | Should -Be 'Visible'
        $gui.Controls.MonitorRecordText.Text | Should -BeLike "Recording to $path*"
    }

    It 'writes one line per measurement' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = (New-TestSnapshot) } { Add-WindowRecordingRow -Gui $Gui -Snapshot $Snapshot }
        $row = (Get-Content -LiteralPath $path)[1] -split [regex]::Escape($delimiter)

        $gui.Recorder.Rows | Should -Be 1
        $row[0] | Should -Be '2026-01-15 10:30:05'
        # processor 37 % at 3460 MHz, memory 50 % = 8192 MB
        $row[1..4] | Should -Be @('37', '3460', '50', '8192')
        # graphics 25 % at 61 degrees
        $row[5..6] | Should -Be @('25', '61')
        # busiest disk 40 %, both disks together read 3 MB/s and write 1 MB/s
        $row[7..9] | Should -Be @('40', '3072', '1024')
        # both adapters together: 250000 bytes/s down = 2000 kbit/s, 25000 bytes/s up = 200 kbit/s
        $row[10..11] | Should -Be @('2000', '200')
        $row[12..13] | Should -Be @('"contoso-app"', '18')
    }

    It 'leaves a value empty when it is not known' {
        $unknown = New-TestSnapshot -Change @{ Gpu = @(); GpuSensors = @(); Processes = @() }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = $unknown } { Add-WindowRecordingRow -Gui $Gui -Snapshot $Snapshot }
        $row = (Get-Content -LiteralPath $path)[2] -split [regex]::Escape($delimiter)

        $row[5..6] | Should -Be @('', '')
        $row[12..13] | Should -Be @('', '')
    }

    It 'shows how many measurements were written and how long it still records' {
        $gui.Controls.MonitorRecordText.Text | Should -Match '2 measurements  \|  5 min left$'
    }

    It 'keeps measuring on other pages while it records' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui }
        $gui.Monitor.Shared.Paused | Should -BeFalse
    }

    It 'ends by itself when its time is over' {
        $gui.Recorder.Until = (Get-Date).AddSeconds(-1)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = (New-TestSnapshot) } { Add-WindowRecordingRow -Gui $Gui -Snapshot $Snapshot }

        $gui.Recorder | Should -BeNullOrEmpty
        @(Get-Content -LiteralPath $path).Count | Should -Be 4
    }

    It 'returns the button to its resting state and says where the file is' {
        $gui.Controls.MonitorRecordButton.Content | Should -Be 'Record to file'
        $gui.Controls.MonitorRecordMinutes.IsEnabled | Should -BeTrue
        $gui.Controls.MonitorRecordText.Text | Should -Be "Recording saved: $path (3 measurements)"
        $gui.Controls.StatusText.Text | Should -Be "Recording saved: $path (3 measurements)"
    }

    It 'pauses the monitor again when the recording ends on another page' {
        # The monitor page is not open in this test window.
        $gui.Monitor.Shared.Paused | Should -BeTrue
    }

    It 'writes nothing when no recording runs' {
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = (New-TestSnapshot) } { Add-WindowRecordingRow -Gui $Gui -Snapshot $Snapshot } } | Should -Not -Throw
        @(Get-Content -LiteralPath $path).Count | Should -Be 4
    }

    It 'resumes a paused monitor, because a recording needs measurements' {
        $paused = New-TestWindow
        $paused.Monitor = @{ Shared = [hashtable]::Synchronized(@{ Paused = $true; Stop = $false; IntervalSeconds = 2 }); LastSequence = 0; Worker = $null }
        $paused.MonitorUserPaused = $true
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $paused } { Enable-WindowRecording -Gui $Gui -Minutes 1 } | Out-Null

        $paused.MonitorUserPaused | Should -BeFalse
        $paused.Monitor.Shared.Paused | Should -BeFalse
    }

    It 'ends the recording instead of failing when the file can no longer be written' {
        $broken = New-TestWindow
        $broken.Recorder = @{ Path = (Join-Path -Path $TestDrive -ChildPath 'no-such-folder\file.csv'); Delimiter = ','; Until = (Get-Date).AddMinutes(5); Rows = 0 }
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $broken; Snapshot = (New-TestSnapshot) } { Add-WindowRecordingRow -Gui $Gui -Snapshot $Snapshot } } | Should -Not -Throw
        $broken.Recorder | Should -BeNullOrEmpty
    }

    It 'is written to the file by every measurement the window receives' {
        Mock -ModuleName HelpdeskToolkit Show-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Add-WindowRecordingRow { }
        $receiving = New-TestWindow
        $receiving.Monitor = @{ Shared = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; Snapshot = (New-TestSnapshot); Error = $null; Sequence = 1 }); LastSequence = 0 }
        $receiving.Recorder = @{ Path = 'unused'; Delimiter = ','; Until = (Get-Date).AddMinutes(5); Rows = 0 }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $receiving } { Receive-WindowMonitor -Gui $Gui }

        Should -Invoke -ModuleName HelpdeskToolkit Add-WindowRecordingRow -Times 1 -Exactly
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowMonitor -Times 1 -Exactly
    }
}

Describe 'Show-WindowMonitor: graphs and warnings' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = (New-TestSnapshot) } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }
    }

    It 'follows the busiest disk in the disk graph' {
        $gui.MonitorHistory.Disk.ToArray() | Should -Be @(40)
        $gui.Controls.MonitorDiskLine.Points.Count | Should -Be 1
    }

    It 'adds up all adapters for the two lines of the network graph' {
        $gui.MonitorHistory.NetworkDown.ToArray() | Should -Be @(250000)
        $gui.MonitorHistory.NetworkUp.ToArray() | Should -Be @(25000)
        $gui.Controls.MonitorNetworkDownLine.Points.Count | Should -Be 1
        $gui.Controls.MonitorNetworkUpLine.Points.Count | Should -Be 1
    }

    It 'scales the network graph to the highest rate and names that rate' {
        # 250000 bytes per second are 2 Mbps; that is the top of the graph.
        $gui.Controls.MonitorNetworkCaption.Text | Should -Be 'download (blue) and upload (green), last 60 measurements, 0 - 2 Mbps'
        $gui.Controls.MonitorNetworkDownLine.Points[0].Y | Should -Be 0
        $gui.Controls.MonitorNetworkUpLine.Points[0].Y | Should -BeGreaterThan 50
    }

    It 'never scales the network graph below 100 KB/s, so an idle line stays flat' {
        $idle = New-TestWindow
        $quiet = New-TestSnapshot -Change @{ Network = @([PSCustomObject]@{ Name = 'Contoso Ethernet'; ReceivedBytesPerSecond = 1000; SentBytesPerSecond = 500; LinkBitsPerSecond = 0 }) }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $idle; Snapshot = $quiet } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }

        $idle.Controls.MonitorNetworkCaption.Text | Should -Match '0 - 819 Kbps$'
        $idle.Controls.MonitorNetworkDownLine.Points[0].Y | Should -BeGreaterThan 55
    }

    It 'shows the link speed only for an adapter that reports one' {
        @($gui.Controls.MonitorNetwork.ItemsSource).Text | Should -Be @('down 1 Mbps  |  up 200 Kbps  |  link 1 Gbps', 'down 1 Mbps  |  up 0 Kbps')
    }

    It 'shows a warning after a value stayed high' {
        $busy = New-TestWindow
        $cpu = [PSCustomObject]@{ Percent = 96; FrequencyMHz = 3000; BaseFrequencyMHz = 2400; Processors = @() }
        1..3 | ForEach-Object {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $busy; Snapshot = (New-TestSnapshot -Change @{ Cpu = $cpu }) } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }
        }
        @($busy.Controls.MonitorAlerts.ItemsSource).Text | Should -Match '^The processor has been above 90 %'
    }

    It 'shows no warning in the normal case' {
        @($gui.Controls.MonitorAlerts.ItemsSource).Count | Should -Be 0
    }

    It 'names the refresh rate in the subtitle' {
        $gui.Controls.PageSubtitle.Text | Should -Be 'What the computer is doing right now. Updated 10:30:05; refreshes about every 2 seconds.'
    }
}
