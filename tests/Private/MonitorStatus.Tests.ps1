# Tests for the status dots on the tiles of the Live monitor and the advice behind them.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    # The test limits: processor and memory are fine up to 85 %, the graphics card up
    # to 95 %; the average of three measurements is judged, a rise is looked for in six.
    Set-TestThreshold

    function New-TestSnapshot {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param($GpuTemperature = 55, [object[]]$Processes = @([PSCustomObject]@{ Name = 'contoso-app'; Percent = 71; MemoryBytes = 1GB }))

        [PSCustomObject]@{
            Processes       = $Processes
            MemoryProcesses = @([PSCustomObject]@{ Name = 'browser'; MemoryBytes = 3GB })
            GpuSensors      = @(
                if ($null -ne $GpuTemperature) {
                    [PSCustomObject]@{ Name = 'Contoso Graphics 770'; TemperatureC = $GpuTemperature }
                }
            )
        }
    }

    function New-TestHistory {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([double[]]$Cpu = @(), [double[]]$Memory = @(), [double[]]$Gpu = @())

        $history = @{}
        foreach ($name in 'Cpu', 'Memory', 'Gpu', 'Disk', 'NetworkDown', 'NetworkUp') {
            $history[$name] = New-Object -TypeName 'System.Collections.Generic.List[double]'
        }
        $Cpu | ForEach-Object { $history.Cpu.Add($_) }
        $Memory | ForEach-Object { $history.Memory.Add($_) }
        $Gpu | ForEach-Object { $history.Gpu.Add($_) }
        $history
    }

    # The judgement of one tile for the given histories.
    function Get-TestStatus {
        param([string]$Name, [hashtable]$History, $Snapshot = (New-TestSnapshot))

        InModuleScope HelpdeskToolkit -Parameters @{ History = $History; Snapshot = $Snapshot } { Get-MonitorStatus -History $History -Snapshot $Snapshot } |
            Where-Object Name -eq $Name
    }
}

Describe 'Get-MonitorStatus' {
    It 'returns one judgement each for the processor, the memory and the graphics card' {
        $all = @(InModuleScope HelpdeskToolkit -Parameters @{ History = (New-TestHistory); Snapshot = (New-TestSnapshot) } { Get-MonitorStatus -History $History -Snapshot $Snapshot })
        $all.Name | Should -Be @('Cpu', 'Memory', 'Gpu')
    }

    It 'has no level before the first measurement' {
        $status = Get-TestStatus -Name 'Cpu' -History (New-TestHistory)
        $status.Level | Should -Be 'None'
        $status.Summary | Should -Be 'No measurement yet.'
    }

    It 'is green while the average is well below the limit' {
        $status = Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 20, 30, 40)
        $status.Level | Should -Be 'Ok'
        $status.Summary | Should -Be 'Fine: 30 % on average, up to 85 % is fine.'
    }

    It 'judges the average of the last measurements, so a single peak stays green' {
        (Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 10, 10, 100)).Level | Should -Be 'Ok'
    }

    It 'turns orange when the average comes close to the limit' {
        $status = Get-TestStatus -Name 'Memory' -History (New-TestHistory -Memory 78, 80, 82)
        $status.Level | Should -Be 'Near'
        $status.Summary | Should -Be 'Close to the limit: 80 % on average, up to 85 % is fine.'
    }

    It 'turns orange when the value keeps rising towards the limit' {
        # 55 to 70 in steps of 3: three more measurements like these reach 85 %.
        $status = Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 55, 58, 61, 64, 67, 70)
        $status.Level | Should -Be 'Near'
        $status.Summary | Should -Be 'Rising: 67 % on average and on the way to the limit of 85 %.'
    }

    It 'stays green when the value falls, or rises too slowly to reach the limit soon' {
        (Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 70, 67, 64, 61, 58, 55)).Level | Should -Be 'Ok'
        (Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 60, 60, 61, 61, 62, 62)).Level | Should -Be 'Ok'
    }

    It 'does not call a rise on an idle computer a trend' {
        # From 5 to 40 %: steep, but still below the load from which a rise counts.
        (Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 5, 12, 19, 26, 33, 40)).Level | Should -Be 'Ok'
    }

    It 'needs enough measurements before it looks for a rise' {
        (Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 55, 62, 69)).Level | Should -Be 'Ok'
    }

    It 'turns red when the average is above the limit' {
        $status = Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 88, 90, 95)
        $status.Level | Should -Be 'Over'
        $status.Summary | Should -Be 'Above the limit: 91 % on average, up to 85 % is fine. Click the triangle to see what to do.'
    }

    It 'names the program that uses the processor most in the advice' {
        $status = Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 90, 90, 90)
        $status.Title | Should -Be 'Processor: how to bring the load down'
        $status.Advice[0] | Should -Be 'The processor has been at 90 % on average over the last measurements; up to 85 % is fine.'
        $status.Advice[1] | Should -Be 'The program that uses the processor most right now is contoso-app (71 %). Close it, or what it has open, if you do not need it.'
        $status.Advice.Count | Should -BeGreaterThan 3
        $status.ActionCheck | Should -Be 'CPU load'
    }

    It 'gives the general advice when no program can be named' {
        $status = Get-TestStatus -Name 'Cpu' -History (New-TestHistory -Cpu 90, 90, 90) -Snapshot (New-TestSnapshot -Processes @())
        $status.Advice -join ' ' | Should -Not -Match 'right now is'
        $status.Advice.Count | Should -BeGreaterThan 2
    }

    It 'names the program that uses the most memory in the advice' {
        $status = Get-TestStatus -Name 'Memory' -History (New-TestHistory -Memory 92, 93, 94)
        $status.Level | Should -Be 'Over'
        $status.Title | Should -Be 'Memory: how to free it'
        $status.Advice[1] | Should -Be 'The program that uses the most memory right now is browser (3 GB). Close it, or some of its tabs and documents.'
        $status.ActionCheck | Should -Be 'Memory usage'
    }

    It 'does not advise closing a part of Windows that happens to use the most memory' {
        $snapshot = New-TestSnapshot
        $snapshot.MemoryProcesses = @(
            [PSCustomObject]@{ Name = 'Memory Compression'; MemoryBytes = 4GB }
            [PSCustomObject]@{ Name = 'System'; MemoryBytes = 3GB }
            [PSCustomObject]@{ Name = 'browser'; MemoryBytes = 2GB }
        )
        $status = Get-TestStatus -Name 'Memory' -History (New-TestHistory -Memory 92, 93, 94) -Snapshot $snapshot
        $status.Advice[1] | Should -Be 'The program that uses the most memory right now is browser (2 GB). Close it, or some of its tabs and documents.'
    }

    It 'names no program when only parts of Windows are in the list' {
        $snapshot = New-TestSnapshot
        $snapshot.MemoryProcesses = @([PSCustomObject]@{ Name = 'Memory Compression'; MemoryBytes = 4GB })
        $status = Get-TestStatus -Name 'Memory' -History (New-TestHistory -Memory 92, 93, 94) -Snapshot $snapshot
        ($status.Advice -join ' ') | Should -Not -Match 'Memory Compression'
        ($status.Advice -join ' ') | Should -Not -Match 'uses the most memory right now'
    }

    It 'judges the graphics card by its own, higher limit' {
        (Get-TestStatus -Name 'Gpu' -History (New-TestHistory -Gpu 80, 80, 80)).Level | Should -Be 'Ok'
        (Get-TestStatus -Name 'Gpu' -History (New-TestHistory -Gpu 88, 88, 88)).Level | Should -Be 'Near'
        (Get-TestStatus -Name 'Gpu' -History (New-TestHistory -Gpu 97, 98, 99)).Level | Should -Be 'Over'
    }

    It 'turns the graphics card orange when it gets hot, whatever its load' {
        $status = Get-TestStatus -Name 'Gpu' -History (New-TestHistory -Gpu 20, 20, 20) -Snapshot (New-TestSnapshot -GpuTemperature 78)
        $status.Level | Should -Be 'Near'
        $status.Summary | Should -Match '^Getting hot: 78 .C; the limit is 85 .C\.$'
    }

    It 'turns the graphics card red when it is too hot, and says how to cool it' {
        $status = Get-TestStatus -Name 'Gpu' -History (New-TestHistory -Gpu 20, 20, 20) -Snapshot (New-TestSnapshot -GpuTemperature 91)
        $status.Level | Should -Be 'Over'
        $status.Summary | Should -Match '^Too hot: 91 .C, up to 85 .C is fine\.'
        $status.Advice -join ' ' | Should -Match 'The graphics card is at 91 .C\. Clean the dust'
    }

    It 'keeps the graphics card red for its load when the temperature is only warm' {
        $status = Get-TestStatus -Name 'Gpu' -History (New-TestHistory -Gpu 99, 99, 99) -Snapshot (New-TestSnapshot -GpuTemperature 78)
        $status.Level | Should -Be 'Over'
        $status.Summary | Should -Match '^Above the limit: 99 %'
    }

    It 'judges a graphics card without a temperature sensor by its load alone' {
        (Get-TestStatus -Name 'Gpu' -History (New-TestHistory -Gpu 30, 30, 30) -Snapshot (New-TestSnapshot -GpuTemperature $null)).Level | Should -Be 'Ok'
    }
}

Describe 'Show-WindowAdvice and Switch-WindowAdvice' -Skip:(-not $isSta) {
    BeforeAll {
        # Judgements as Get-MonitorStatus returns them, with the given levels.
        function New-TestStatus {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([string]$Cpu = 'Ok', [string]$Memory = 'Ok', [string]$Gpu = 'Ok')

            $levels = @{ Cpu = $Cpu; Memory = $Memory; Gpu = $Gpu }
            foreach ($name in 'Cpu', 'Memory', 'Gpu') {
                [PSCustomObject]@{
                    Name        = $name
                    Level       = $levels[$name]
                    Summary     = "summary of $name"
                    Title       = "title of $name"
                    Advice      = @("first advice for $name", "second advice for $name")
                    ActionCheck = 'CPU load'
                }
            }
        }

        function Show-TestStatus {
            param($Gui, [object[]]$Status)
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui; Status = $Status } { Show-WindowAdvice -Gui $Gui -Status $Status }
        }

        $colors = @{ Ok = 'OkBrush'; Near = 'WarningDotBrush'; Over = 'CriticalBrush'; None = 'NeutralBrush' }
    }

    BeforeEach {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
    }

    It 'exposes the control <_>' -ForEach @(
        'MonitorCpuDot', 'MonitorMemoryDot', 'MonitorGpuDot'
        'MonitorCpuAdviceButton', 'MonitorMemoryAdviceButton', 'MonitorGpuAdviceButton'
        'MonitorAdviceCard', 'MonitorAdviceTitle', 'MonitorAdviceItems', 'MonitorAdviceAction'
    ) {
        $gui.Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'starts with grey dots, no triangles and no advice' {
        [string]$gui.Controls.MonitorCpuDot.Fill.Color | Should -Be ([string]$gui.Window.FindResource('NeutralBrush').Color)
        $gui.Controls.MonitorCpuAdviceButton.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MonitorAdviceCard.Visibility | Should -Be 'Collapsed'
    }

    It 'colors the dot <Level> with the <Brush>' -ForEach @(
        @{ Level = 'Ok'; Brush = 'OkBrush' }
        @{ Level = 'Near'; Brush = 'WarningDotBrush' }
        @{ Level = 'Over'; Brush = 'CriticalBrush' }
        @{ Level = 'None'; Brush = 'NeutralBrush' }
    ) {
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Memory $Level)
        [string]$gui.Controls.MonitorMemoryDot.Fill.Color | Should -Be ([string]$gui.Window.FindResource($Brush).Color)
        $gui.Controls.MonitorMemoryDot.ToolTip | Should -Be 'summary of Memory'
    }

    It 'shows the triangle only on a tile whose value is above its limit' {
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Cpu 'Over' -Memory 'Near')
        $gui.Controls.MonitorCpuAdviceButton.Visibility | Should -Be 'Visible'
        $gui.Controls.MonitorMemoryAdviceButton.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MonitorGpuAdviceButton.Visibility | Should -Be 'Collapsed'
        # The advice opens with a click, not by itself.
        $gui.Controls.MonitorAdviceCard.Visibility | Should -Be 'Collapsed'
    }

    It 'opens the advice of a tile when its triangle is clicked' {
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Cpu 'Over')
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowAdvice -Gui $Gui -Name 'Cpu' }

        $gui.MonitorAdvice | Should -Be 'Cpu'
        $gui.Controls.MonitorAdviceCard.Visibility | Should -Be 'Visible'
        $gui.Controls.MonitorAdviceTitle.Text | Should -Be 'title of Cpu'
        @($gui.Controls.MonitorAdviceItems.ItemsSource).Text | Should -Be @('first advice for Cpu', 'second advice for Cpu')
        $gui.Controls.MonitorAdviceAction.Content | Should -Be 'Open Task Manager'
        $gui.Controls.MonitorCpuAdviceButton.IsChecked | Should -BeTrue
    }

    It 'closes the advice with a second click' {
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Cpu 'Over')
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowAdvice -Gui $Gui -Name 'Cpu'; Switch-WindowAdvice -Gui $Gui -Name 'Cpu' }

        $gui.MonitorAdvice | Should -Be ''
        $gui.Controls.MonitorAdviceCard.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MonitorCpuAdviceButton.IsChecked | Should -BeFalse
    }

    It 'shows one advice at a time' {
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Cpu 'Over' -Memory 'Over')
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowAdvice -Gui $Gui -Name 'Cpu'; Switch-WindowAdvice -Gui $Gui -Name 'Memory' }

        $gui.Controls.MonitorAdviceTitle.Text | Should -Be 'title of Memory'
        $gui.Controls.MonitorCpuAdviceButton.IsChecked | Should -BeFalse
        $gui.Controls.MonitorMemoryAdviceButton.IsChecked | Should -BeTrue
    }

    It 'keeps the advice open, with the newest text, while the value stays above its limit' {
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Cpu 'Over')
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowAdvice -Gui $Gui -Name 'Cpu' }

        $newer = @(New-TestStatus -Cpu 'Over')
        $newer[0].Advice = @('newer advice')
        Show-TestStatus -Gui $gui -Status $newer

        $gui.Controls.MonitorAdviceCard.Visibility | Should -Be 'Visible'
        @($gui.Controls.MonitorAdviceItems.ItemsSource).Text | Should -Be 'newer advice'
    }

    It 'closes the advice and hides the triangle when the value is back below its limit' {
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Cpu 'Over')
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowAdvice -Gui $Gui -Name 'Cpu' }
        Show-TestStatus -Gui $gui -Status (New-TestStatus -Cpu 'Near')

        $gui.MonitorAdvice | Should -Be ''
        $gui.Controls.MonitorAdviceCard.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MonitorCpuAdviceButton.Visibility | Should -Be 'Collapsed'
    }
}

Describe 'Show-WindowMonitor: status dots' -Skip:(-not $isSta) {
    It 'judges the measurements it has drawn and colors the dots' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $snapshot = [PSCustomObject]@{
            TakenAt         = [datetime]'2026-01-15 10:30:05'
            Cpu             = [PSCustomObject]@{ Percent = 97; FrequencyMHz = 3460; BaseFrequencyMHz = 2400; Processors = @() }
            System          = $null
            Memory          = [PSCustomObject]@{
                TotalBytes = 16GB; UsedBytes = 8GB; AvailableBytes = 8GB; Percent = 50; CommittedBytes = 10GB; CommitLimitBytes = 20GB
                CachedBytes = $null; PagedPoolBytes = $null; NonPagedPoolBytes = $null; PageFilePercent = $null
            }
            Gpu             = @()
            GpuSensors      = @()
            Disks           = @()
            Volumes         = @()
            DriveHealth     = $null
            Network         = @()
            Thermal         = @()
            Battery         = $null
            Processes       = @([PSCustomObject]@{ Name = 'contoso-app'; Percent = 90; MemoryBytes = 1GB })
            MemoryProcesses = @()
            IoProcesses     = @()
        }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = $snapshot } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }

        [string]$gui.Controls.MonitorCpuDot.Fill.Color | Should -Be ([string]$gui.Window.FindResource('CriticalBrush').Color)
        [string]$gui.Controls.MonitorMemoryDot.Fill.Color | Should -Be ([string]$gui.Window.FindResource('OkBrush').Color)
        [string]$gui.Controls.MonitorGpuDot.Fill.Color | Should -Be ([string]$gui.Window.FindResource('NeutralBrush').Color)
        $gui.Controls.MonitorCpuAdviceButton.Visibility | Should -Be 'Visible'
        @($gui.MonitorStatus).Count | Should -Be 3
    }
}
