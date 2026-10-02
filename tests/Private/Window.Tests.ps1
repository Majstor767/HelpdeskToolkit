# Tests for the application window. The window is created but never shown, so the
# tests run unattended. Clicking through the real window is covered by manual testing.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param()

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }

    $testResults = @(
        New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d' -Description 'Time since start.' -Allowed '0 - 7 days' -Typical '0 - 3 days'
        New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '10 programs and 2 more' -Details 'Extra One', 'Extra Two' -Recommendation 'Disable some.'
        New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free' -Recommendation 'Free up space.'
        New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
    )
}

Describe 'New-HealthCheckWindow' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
    }

    It 'creates a window without showing it' {
        $gui.Window | Should -BeOfType [System.Windows.Window]
        $gui.Window.IsVisible | Should -BeFalse
    }

    It 'exposes the control <_> that the code relies on' -ForEach @(
        'RunButton', 'SkipNetworkCheckBox', 'DaysComboBox', 'ProgressBar', 'StatusText', 'ComputerText'
        'CategoryList', 'PageTitle', 'PageSubtitle', 'OverviewPanel', 'ResultItems', 'ResultScroll', 'EmptyText'
        'VerdictBorder', 'VerdictText', 'CriticalCount', 'WarningCount', 'OkCount', 'InfoCount'
        'OpenReportButton', 'SaveAsButton', 'ElevateButton', 'ElevationText'
        'RunPanel', 'RunTitle', 'RunStep', 'RunPercent'
        'MonitorPanel', 'MonitorTileCpu', 'MonitorTileCpuSub', 'MonitorTileMemory', 'MonitorTileMemorySub'
        'MonitorTileGpu', 'MonitorTileGpuSub', 'MonitorTileUptime', 'MonitorTileUptimeSub'
        'MonitorCpuText', 'MonitorCpuDetail', 'MonitorCpuGraph', 'MonitorCpuLine', 'MonitorCpuArea', 'MonitorProcessors'
        'MonitorMemoryText', 'MonitorMemoryBar', 'MonitorMemoryGraph', 'MonitorMemoryLine', 'MonitorMemoryArea', 'MonitorMemoryStats'
        'MonitorGpus', 'MonitorGpuEmpty', 'MonitorGpuGraphFrame', 'MonitorGpuGraph', 'MonitorGpuLine', 'MonitorGpuArea'
        'MonitorDisks', 'MonitorVolumes', 'MonitorNetwork', 'MonitorSensors'
        'MonitorProcesses', 'MonitorMemoryProcesses', 'MonitorIoProcesses', 'MonitorIoEmpty'
    ) {
        $gui.Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'starts with the report buttons disabled, because there is nothing to save yet' {
        $gui.Controls.OpenReportButton.IsEnabled | Should -BeFalse
        $gui.Controls.SaveAsButton.IsEnabled | Should -BeFalse
    }

    It 'starts with the two pages that need no health check, and a hint' {
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'Live monitor')
        $gui.Controls.PageSubtitle.Text | Should -Match 'Run check'
    }

    It 'starts with the progress panel and the Live monitor hidden' {
        $gui.Controls.RunPanel.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MonitorPanel.Visibility | Should -Be 'Collapsed'
    }

    It 'gives the Run button the rounded template and an icon' {
        $gui.Controls.RunButton.Template | Should -Be $gui.Window.FindResource('ButtonTemplate')
        # One character of the icon font, from its private range.
        [int][char]([string]$gui.Controls.RunButton.Tag) | Should -BeGreaterThan 0xE000
    }

    It 'gives the buttons of the side bar the look of the page list, each with an icon' {
        foreach ($name in 'OpenReportButton', 'CopySummaryButton', 'SaveAsButton', 'ElevateButton', 'SettingsButton') {
            $button = $gui.Controls[$name]
            $button.Style | Should -Be $gui.Window.FindResource('NavActionButton') -Because "$name belongs to the side bar"
            ([string]$button.Tag).Length | Should -Be 1
            [int][char]([string]$button.Tag) | Should -BeGreaterThan 0xE000
        }
    }

    It 'keeps the text of the Run button a plain string, because the code replaces it while a check runs' {
        $gui.Controls.RunButton.Content | Should -Be 'Run check'
    }

    It 'starts with empty histories for the graphs of the Live monitor' {
        $gui.MonitorHistory.Keys | Sort-Object | Should -Be @('Cpu', 'Disk', 'Gpu', 'Latency', 'Memory', 'NetworkDown', 'NetworkUp')
        $gui.MonitorHistory.Cpu.Count | Should -Be 0
    }

    It 'knows where the module is, for the background runspaces' {
        $gui.ManifestPath | Should -Exist
        $gui.ManifestPath | Should -BeLike '*HelpdeskToolkit.psd1'
    }

    It 'offers history periods that Get-PCHealthReport accepts' {
        foreach ($item in $gui.Controls.DaysComboBox.Items) {
            [int]$item.Tag | Should -BeGreaterThan 0
            [int]$item.Tag | Should -BeLessOrEqual 365
        }
    }

    It 'uses the application icon' {
        $gui.Window.Icon | Should -Not -BeNullOrEmpty
    }
}

Describe 'ConvertTo-WindowItem' {
    It 'combines the allowed range and the typical value into one line' {
        $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[0] } { ConvertTo-WindowItem -Result $Result }
        $item.Reference | Should -Be 'Allowed: 0 - 7 days   |   Typical: 0 - 3 days'
        $item.Description | Should -Be 'Time since start.'
    }

    It 'leaves the optional texts empty, so the card hides those lines' {
        $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[3] } { ConvertTo-WindowItem -Result $Result }
        $item.Reference | Should -Be ''
        $item.More | Should -Be ''
        $item.MoreHeader | Should -Be ''
        $item.Recommendation | Should -Be ''
    }

    It 'puts the remaining items of a long list behind a "Show N more" section' {
        $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[1] } { ConvertTo-WindowItem -Result $Result }
        $item.MoreHeader | Should -Be 'Show 2 more'
        $item.More | Should -Be "Extra One`nExtra Two"
    }

    It 'labels the recommendation of a problem as a recommended fix' {
        $problem = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[2] } { ConvertTo-WindowItem -Result $Result }
        $problem.RecommendationLabel | Should -Be 'RECOMMENDED FIX'
        $problem.Recommendation | Should -Be 'Free up space.'

        $advice = New-TestResult -Status Info -Recommendation 'Consider it.'
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $advice } { ConvertTo-WindowItem -Result $Result }).RecommendationLabel | Should -Be 'ADVICE'
    }

    It 'shows the category only when asked to' {
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[2] } { ConvertTo-WindowItem -Result $Result }).Category | Should -Be ''
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[2] } { ConvertTo-WindowItem -Result $Result -ShowCategory }).Category | Should -Be 'Hardware'
    }
}

Describe 'Show-WindowReport' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        $report = New-TestReport -Result $testResults
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report }
    }

    It 'shows the count of every status' {
        $gui.Controls.CriticalCount.Text | Should -Be '1'
        $gui.Controls.WarningCount.Text | Should -Be '1'
        $gui.Controls.OkCount.Text | Should -Be '1'
        $gui.Controls.InfoCount.Text | Should -Be '1'
    }

    It 'shows the verdict' {
        $gui.Controls.VerdictBorder.Visibility | Should -Be 'Visible'
        $gui.Controls.VerdictText.Text | Should -Be 'Action required. Critical problems: 1, warnings: 1.'
    }

    It 'lists Overview, Live monitor, every category in the order it ran, and the settings' {
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'Live monitor', 'System', 'Hardware', 'Network')
    }

    It 'marks every entry with the worst status and the number of problems' {
        $entries = @($gui.Controls.CategoryList.ItemsSource)
        ($entries | Where-Object Name -eq 'Overview').Worst | Should -Be 'Critical'
        ($entries | Where-Object Name -eq 'Overview').Badge | Should -Be '2'
        ($entries | Where-Object Name -eq 'System').Worst | Should -Be 'Warning'
        ($entries | Where-Object Name -eq 'System').Badge | Should -Be '1'
        ($entries | Where-Object Name -eq 'Network').Worst | Should -Be 'Info'
        ($entries | Where-Object Name -eq 'Network').Badge | Should -Be ''
        ($entries | Where-Object Name -eq 'Live monitor').Worst | Should -Be 'Info'
        ($entries | Where-Object Name -eq 'Live monitor').Badge | Should -Be ''
    }

    It 'shows the pages first and the categories under the heading CHECKS, also after the entries were replaced' {
        $groups = @($gui.Controls.CategoryList.Items.Groups)
        $groups.Count | Should -Be 2
        $groups[0].Name | Should -Be ''
        @($groups[0].Items).Name | Should -Be @('Overview', 'Live monitor')
        $groups[1].Name | Should -Be 'CHECKS'
        @($groups[1].Items).Name | Should -Be @('System', 'Hardware', 'Network')
        # Selecting by position still means the order of the list on the screen.
        $gui.Controls.CategoryList.Items[2].Name | Should -Be 'System'
    }

    It 'opens the Overview page with the problems, critical first' {
        $gui.Controls.CategoryList.SelectedIndex | Should -Be 0
        $gui.Controls.PageTitle.Text | Should -Be 'Overview'
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Visible'
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be @('Disk (C:)', 'Startup programs')
        @($gui.Controls.ResultItems.ItemsSource).Category | Should -Be @('Hardware', 'System')
    }

    It 'enables the report buttons' {
        $gui.Controls.OpenReportButton.IsEnabled | Should -BeTrue
        $gui.Controls.SaveAsButton.IsEnabled | Should -BeTrue
    }

    It 'mentions the skipped checks when the run was not elevated' {
        $gui.Controls.StatusText.Text | Should -Match 'Requires admin'
    }

    It 'says "No problems found" when every result is OK or Info' {
        $okGui = New-TestWindow
        $okReport = New-TestReport -Result @(New-TestResult -Status OK; New-TestResult -Status Info) -IsElevated $true
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $okGui; Report = $okReport } { Show-WindowReport -Gui $Gui -Report $Report }

        $okGui.Controls.VerdictText.Text | Should -Be 'No problems found. All checks passed.'
        $okGui.Controls.StatusText.Text | Should -Not -Match 'Requires admin'
        $okGui.Controls.EmptyText.Visibility | Should -Be 'Visible'
        $okGui.Controls.EmptyText.Text | Should -Be 'No problems found.'
        @($okGui.Controls.CategoryList.ItemsSource)[0].Badge | Should -Be ''
    }
}

Describe 'Show-WindowPage' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        $report = New-TestReport -Result $testResults
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report }
    }

    It 'shows every check of the chosen category, not only the problems' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }

        $gui.Controls.PageTitle.Text | Should -Be 'System'
        $gui.Controls.PageSubtitle.Text | Should -Be '1 Warning, 1 OK'
        # The warning comes before the result that is fine.
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be @('Startup programs', 'Uptime')
    }

    It 'hides the verdict and the status counts on a category page' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Network' }
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Collapsed'
        $gui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
    }

    It 'shows the page of the entry selected in the category list when no name is given' {
        $gui.Controls.CategoryList.SelectedIndex = 3
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui }
        $gui.Controls.PageTitle.Text | Should -Be 'Hardware'
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be @('Disk (C:)')
    }

    It 'returns to the Overview with the verdict and the status counts' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Visible'
        $gui.Controls.PageSubtitle.Text | Should -Match '^These 2 results need attention'
    }

    It 'shows the hint to run a check before the first check has run' {
        $emptyGui = New-TestWindow
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $emptyGui } { Show-WindowPage -Gui $Gui -Name 'System' } } | Should -Not -Throw
        $emptyGui.Controls.PageTitle.Text | Should -Be 'Overview'
        $emptyGui.Controls.EmptyText.Visibility | Should -Be 'Visible'
        $emptyGui.Controls.EmptyText.Text | Should -Match 'Run check'
    }

    Context 'the Live monitor page' {
        BeforeAll {
            # The real functions start a background runspace that measures this computer.
            Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
            Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
            $monitorGui = New-TestWindow
        }

        It 'shows the monitor instead of the result cards and starts measuring, without a health check' {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $monitorGui } { Show-WindowPage -Gui $Gui -Name 'Live monitor' }

            $monitorGui.Controls.PageTitle.Text | Should -Be 'Live monitor'
            $monitorGui.Controls.MonitorPanel.Visibility | Should -Be 'Visible'
            $monitorGui.Controls.ResultScroll.Visibility | Should -Be 'Collapsed'
            $monitorGui.Controls.OverviewPanel.Visibility | Should -Be 'Collapsed'
            $monitorGui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
            Should -Invoke -ModuleName HelpdeskToolkit Enable-WindowMonitor -Times 1 -Exactly
        }

        It 'stops measuring and shows the result cards again when another page is opened' {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $monitorGui } { Show-WindowPage -Gui $Gui -Name 'Overview' }

            $monitorGui.Controls.MonitorPanel.Visibility | Should -Be 'Collapsed'
            $monitorGui.Controls.ResultScroll.Visibility | Should -Be 'Visible'
            Should -Invoke -ModuleName HelpdeskToolkit Disable-WindowMonitor -Times 1 -Exactly
        }
    }
}

Describe 'ConvertTo-WindowNavigationItem' {
    It 'takes the worst status of the results and counts the problems' {
        $entry = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults } { ConvertTo-WindowNavigationItem -Name 'Overview' -Result $Result }
        $entry.Name | Should -Be 'Overview'
        $entry.Worst | Should -Be 'Critical'
        $entry.Badge | Should -Be '2'
    }

    It 'prefers OK over Info and shows no badge without problems' {
        $results = @(New-TestResult -Status Info; New-TestResult -Status OK)
        $entry = InModuleScope HelpdeskToolkit -Parameters @{ Result = $results } { ConvertTo-WindowNavigationItem -Name 'Network' -Result $Result }
        $entry.Worst | Should -Be 'OK'
        $entry.Badge | Should -Be ''
    }

    It 'uses the neutral status "None" for an entry without results, unless another one is given' {
        InModuleScope HelpdeskToolkit {
            (ConvertTo-WindowNavigationItem -Name 'Overview').Worst | Should -Be 'None'
            (ConvertTo-WindowNavigationItem -Name 'Live monitor' -EmptyStatus 'Info').Worst | Should -Be 'Info'
        }
    }

    It 'gives every page and every category an icon of its own' {
        $names = 'Overview', 'Live monitor', 'Timeline', 'System', 'Specifications', 'Hardware', 'Software',
        'Event Log', 'Windows Update', 'Security', 'Network', 'Printers', 'Services'
        $icons = InModuleScope HelpdeskToolkit -Parameters @{ Names = $names } {
            foreach ($name in $Names) { (ConvertTo-WindowNavigationItem -Name $name).Icon }
        }
        @($icons).Count | Should -Be $names.Count
        @($icons | Select-Object -Unique).Count | Should -Be $names.Count
        foreach ($icon in $icons) {
            $icon.Length | Should -Be 1
            [int][char]$icon | Should -BeGreaterThan 0xE000
        }
    }

    It 'puts the pages in a group without a heading and the categories under CHECKS' {
        InModuleScope HelpdeskToolkit {
            foreach ($name in 'Overview', 'Live monitor', 'Timeline') {
                (ConvertTo-WindowNavigationItem -Name $name).Group | Should -Be ''
            }
            (ConvertTo-WindowNavigationItem -Name 'Security').Group | Should -Be 'CHECKS'
        }
    }

    It 'gives a category it does not know a general icon instead of none' {
        $icon = InModuleScope HelpdeskToolkit { (ConvertTo-WindowNavigationItem -Name 'Something new').Icon }
        $icon.Length | Should -Be 1
    }
}

Describe 'ConvertTo-WindowGraph' {
    BeforeAll {
        Add-Type -AssemblyName PresentationCore, WindowsBase
    }

    It 'puts the newest value at the right edge and older ones one step to the left' {
        $graph = InModuleScope HelpdeskToolkit { ConvertTo-WindowGraph -Value 0, 50, 100 -Width 100 -Height 50 -Capacity 11 }

        # 11 values fit into a width of 100, so one step is 10.
        @($graph.Line | ForEach-Object { $_.X }) | Should -Be @(80, 90, 100)
    }

    It 'draws 0 % on the bottom edge and 100 % on the top edge' {
        $graph = InModuleScope HelpdeskToolkit { ConvertTo-WindowGraph -Value 0, 50, 100 -Width 100 -Height 50 -Capacity 11 }
        @($graph.Line | ForEach-Object { $_.Y }) | Should -Be @(50, 25, 0)
    }

    It 'closes the area along the bottom edge' {
        $graph = InModuleScope HelpdeskToolkit { ConvertTo-WindowGraph -Value 0, 50, 100 -Width 100 -Height 50 -Capacity 11 }

        $graph.Area.Count | Should -Be 5
        $graph.Area[3].X | Should -Be 100
        $graph.Area[3].Y | Should -Be 50
        $graph.Area[4].X | Should -Be 80
        $graph.Area[4].Y | Should -Be 50
    }

    It 'draws only the newest values when there are more than fit' {
        $graph = InModuleScope HelpdeskToolkit { ConvertTo-WindowGraph -Value 10, 20, 30, 40, 50 -Width 20 -Height 100 -Capacity 3 }
        @($graph.Line | ForEach-Object { $_.X }) | Should -Be @(0, 10, 20)
        @($graph.Line | ForEach-Object { $_.Y }) | Should -Be @(70, 60, 50)
    }

    It 'keeps values outside 0 - 100 inside the drawing area' {
        $graph = InModuleScope HelpdeskToolkit { ConvertTo-WindowGraph -Value -5, 140 -Width 10 -Height 40 -Capacity 2 }
        @($graph.Line | ForEach-Object { $_.Y }) | Should -Be @(40, 0)
    }

    It 'returns empty shapes when nothing was measured yet' {
        $graph = InModuleScope HelpdeskToolkit { ConvertTo-WindowGraph -Value @() -Width 100 -Height 50 }
        $graph.Line.Count | Should -Be 0
        $graph.Area.Count | Should -Be 0
    }
}

Describe 'Show-WindowMonitor' -Skip:(-not $isSta) {
    BeforeAll {
        Set-TestThreshold

        # A complete snapshot as Get-PerformanceSnapshot returns it. Single parts are
        # replaced by the tests through -Change.
        function New-TestSnapshot {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([hashtable]$Change = @{})

            $parts = [ordered]@{
                TakenAt         = [datetime]'2026-01-15 10:30:05'
                Cpu             = [PSCustomObject]@{
                    Percent = 37; FrequencyMHz = 3460; BaseFrequencyMHz = 2400
                    Processors = @(
                        [PSCustomObject]@{ Name = 'CPU 0'; Percent = 70; FrequencyMHz = 3460; Parked = $false }
                        [PSCustomObject]@{ Name = 'CPU 1'; Percent = 4; FrequencyMHz = 2400; Parked = $true }
                    )
                }
                System          = [PSCustomObject]@{ Processes = 212; Threads = 3456; Handles = 98765; UptimeSeconds = 93784 }
                Memory          = [PSCustomObject]@{
                    TotalBytes = 16GB; UsedBytes = 8GB; AvailableBytes = 8GB; Percent = 50
                    CommittedBytes = 10GB; CommitLimitBytes = 20GB
                    CachedBytes = 5GB; PagedPoolBytes = 1.5GB; NonPagedPoolBytes = 512MB; PageFilePercent = 7
                }
                Gpu             = @([PSCustomObject]@{
                        Name = 'Contoso Graphics 770'; Percent = 25
                        Engines = @([PSCustomObject]@{ Name = '3D'; Percent = 25 }, [PSCustomObject]@{ Name = 'Video decode'; Percent = 6 })
                        DedicatedUsedBytes = 2GB; DedicatedTotalBytes = 8GB; SharedUsedBytes = 256MB
                    })
                GpuSensors      = @([PSCustomObject]@{ Name = 'Contoso Graphics 770'; TemperatureC = 61; FanPercent = 35; PowerWatts = 90; PowerLimitWatts = 200 })
                Disks           = @([PSCustomObject]@{ Name = 'Disk 0 (C:)'; Percent = 12; ReadBytesPerSecond = 2MB; WriteBytesPerSecond = 512KB; QueueLength = 0 })
                Volumes         = @(
                    [PSCustomObject]@{ Name = 'C:'; Label = 'System'; TotalBytes = 200GB; FreeBytes = 100GB; Percent = 50 }
                    [PSCustomObject]@{ Name = 'D:'; Label = ''; TotalBytes = 100GB; FreeBytes = 10GB; Percent = 90 }
                    [PSCustomObject]@{ Name = 'E:'; Label = ''; TotalBytes = 100GB; FreeBytes = 2GB; Percent = 98 }
                )
                DriveHealth     = [PSCustomObject]@{ State = 'RequiresAdmin'; Message = ''; Drives = @() }
                Network         = @([PSCustomObject]@{ Name = 'Contoso Ethernet'; ReceivedBytesPerSecond = 125000; SentBytesPerSecond = 1250; LinkBitsPerSecond = 1000000000 })
                Thermal         = @()
                Battery         = $null
                Processes       = @([PSCustomObject]@{ Name = 'contoso-app'; Percent = 18; MemoryBytes = 1GB; IoBytesPerSecond = 0 })
                MemoryProcesses = @([PSCustomObject]@{ Name = 'browser'; Percent = 2; MemoryBytes = 300MB; IoBytesPerSecond = 0 })
                IoProcesses     = @([PSCustomObject]@{ Name = 'backup'; Percent = 1; MemoryBytes = 50MB; IoBytesPerSecond = 3MB })
            }
            foreach ($key in $Change.Keys) {
                $parts[$key] = $Change[$key]
            }
            [PSCustomObject]$parts
        }

        function Show-TestSnapshot {
            param([hashtable]$Change = @{})

            $window = New-TestWindow
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $window; Snapshot = (New-TestSnapshot -Change $Change) } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }
            $window
        }

        $degree = [char]176
        $gui = Show-TestSnapshot
    }

    Context 'processor' {
        It 'shows the total load and the current clock speed' {
            $gui.Controls.MonitorCpuText.Text | Should -Be '37 % at 3.5 GHz'
            $gui.Controls.MonitorTileCpu.Text | Should -Be '37 %'
            $gui.Controls.MonitorTileCpuSub.Text | Should -Be '3.5 GHz'
        }

        It 'shows one meter per logical processor' {
            $rows = @($gui.Controls.MonitorProcessors.ItemsSource)
            $rows.Name | Should -Be @('CPU 0', 'CPU 1')
            $rows.Text | Should -Be @('70 %', '4 %')
        }

        It 'explains the speed and the parking state of a processor in its tooltip' {
            $rows = @($gui.Controls.MonitorProcessors.ItemsSource)
            $rows[0].Tip | Should -Be '3.5 GHz'
            $rows[1].Tip | Should -Be '2.4 GHz, parked by Windows to save power'
        }

        It 'shows the base speed and the counts of the system' {
            $gui.Controls.MonitorCpuDetail.Text | Should -Be 'Base speed 2.4 GHz  |  2 logical processors  |  212 processes  |  3,456 threads  |  98,765 handles'
        }

        It 'shows the time since Windows started' {
            $gui.Controls.MonitorTileUptime.Text | Should -Be '1 d 2 h'
            $gui.Controls.MonitorTileUptimeSub.Text | Should -Be '212 processes'
        }
    }

    It 'gives every meter a plain number, because WPF leaves the meter empty otherwise' {
        foreach ($list in 'MonitorProcessors', 'MonitorGpus', 'MonitorDisks', 'MonitorVolumes') {
            foreach ($row in @($gui.Controls[$list].ItemsSource)) {
                $row.Percent.GetType().Name | Should -Be 'Double' -Because "the meters of $list are bound to Percent"
            }
        }
    }

    Context 'memory' {
        It 'shows the memory in use' {
            $gui.Controls.MonitorMemoryText.Text | Should -Be '50 % (8 GB of 16 GB in use)'
            $gui.Controls.MonitorMemoryBar.Value | Should -Be 50
            $gui.Controls.MonitorTileMemory.Text | Should -Be '50 %'
            $gui.Controls.MonitorTileMemorySub.Text | Should -Be '8 GB of 16 GB'
        }

        It 'breaks the memory down into <Name>: <Text>' -ForEach @(
            @{ Name = 'In use'; Text = '8 GB' }
            @{ Name = 'Available'; Text = '8 GB' }
            @{ Name = 'Cached'; Text = '5 GB' }
            @{ Name = 'Committed (RAM plus page file)'; Text = '10 GB of 20 GB' }
            @{ Name = 'Paged pool'; Text = '1.5 GB' }
            @{ Name = 'Non-paged pool'; Text = '512 MB' }
            @{ Name = 'Page file'; Text = '7 % used' }
        ) {
            (@($gui.Controls.MonitorMemoryStats.ItemsSource) | Where-Object Name -eq $Name).Text | Should -Be $Text
        }

        It 'leaves out the parts of the breakdown that could not be read' {
            $memory = [PSCustomObject]@{
                TotalBytes = 16GB; UsedBytes = 8GB; AvailableBytes = 8GB; Percent = 50; CommittedBytes = 10GB; CommitLimitBytes = 20GB
                CachedBytes = $null; PagedPoolBytes = $null; NonPagedPoolBytes = $null; PageFilePercent = $null
            }
            $partial = Show-TestSnapshot -Change @{ Memory = $memory }
            @($partial.Controls.MonitorMemoryStats.ItemsSource).Name | Should -Be @('In use', 'Available', 'Committed (RAM plus page file)')
        }
    }

    Context 'graphics' {
        It 'shows the load and the memory of the graphics adapter' {
            @($gui.Controls.MonitorGpus.ItemsSource).Text | Should -Be '25 %  |  2 GB of 8 GB memory'
            $gui.Controls.MonitorGpuEmpty.Visibility | Should -Be 'Collapsed'
            $gui.Controls.MonitorGpuGraphFrame.Visibility | Should -Be 'Visible'
        }

        It 'shows the load per engine and the shared memory' {
            @($gui.Controls.MonitorGpus.ItemsSource).Detail | Should -Be '3D 25 %  |  Video decode 6 %  |  shared memory 256 MB'
        }

        It 'shows the load and the temperature on the tile' {
            $gui.Controls.MonitorTileGpu.Text | Should -Be '25 %'
            $gui.Controls.MonitorTileGpuSub.Text | Should -Be "61 ${degree}C"
        }

        It 'shows the name on the tile when the card has no temperature sensor that can be read' {
            $noSensor = Show-TestSnapshot -Change @{ GpuSensors = @() }
            $noSensor.Controls.MonitorTileGpuSub.Text | Should -Be 'Contoso Graphics 770'
        }

        It 'shows the memory in use when the size of the graphics memory is not known' {
            $adapter = [PSCustomObject]@{ Name = 'GPU 1'; Percent = 3; Engines = @(); DedicatedUsedBytes = 1GB; DedicatedTotalBytes = 0; SharedUsedBytes = 0 }
            $unknown = Show-TestSnapshot -Change @{ Gpu = @($adapter) }
            @($unknown.Controls.MonitorGpus.ItemsSource).Text | Should -Be '3 %  |  1 GB memory in use'
            @($unknown.Controls.MonitorGpus.ItemsSource).Detail | Should -Be ''
        }
    }

    Context 'disks' {
        It 'shows disk rates in bytes per second' {
            @($gui.Controls.MonitorDisks.ItemsSource).Text | Should -Be 'active 12 %  |  read 2 MB/s  |  write 512 KB/s'
        }

        It 'adds the queue length only when requests are waiting' {
            $disk = [PSCustomObject]@{ Name = 'Disk 0 (C:)'; Percent = 100; ReadBytesPerSecond = 0; WriteBytesPerSecond = 1MB; QueueLength = 4 }
            $busy = Show-TestSnapshot -Change @{ Disks = @($disk) }
            @($busy.Controls.MonitorDisks.ItemsSource).Text | Should -Be 'active 100 %  |  read 0 KB/s  |  write 1 MB/s  |  queue 4'
        }

        It 'shows the space on every drive letter, with its label' {
            $rows = @($gui.Controls.MonitorVolumes.ItemsSource)
            $rows.Name | Should -Be @('C: System', 'D:', 'E:')
            # The drive Windows is installed on says so; which one that is depends on the computer.
            $expected = '50 % used  |  100 GB free of 200 GB'
            if ($env:SystemDrive -eq 'C:') {
                $expected += '  |  Windows drive'
            }
            $rows[0].Text | Should -Be $expected
        }

        It 'colors the meter of a drive by the limits of the disk space check' {
            # Test limits: warning below 15 % free, critical below 5 % free.
            @($gui.Controls.MonitorVolumes.ItemsSource).Level | Should -Be @('Normal', 'Warning', 'Critical')
        }
    }

    It 'shows network rates in bits per second, and the link speed' {
        @($gui.Controls.MonitorNetwork.ItemsSource).Text | Should -Be 'down 1 Mbps  |  up 10 Kbps  |  link 1 Gbps'
    }

    Context 'sensors' {
        It 'shows temperature, fan and power draw of the graphics card' {
            $row = @($gui.Controls.MonitorSensors.ItemsSource) | Where-Object Name -eq 'Contoso Graphics 770'
            $row.Text | Should -Be "61 ${degree}C  |  fan 35 %  |  90 W of 200 W"
        }

        It 'leaves out the values a graphics card does not report' {
            $sensor = [PSCustomObject]@{ Name = 'Contoso Mobile GPU'; TemperatureC = 48; FanPercent = $null; PowerWatts = $null; PowerLimitWatts = $null }
            $laptop = Show-TestSnapshot -Change @{ GpuSensors = @($sensor) }
            (@($laptop.Controls.MonitorSensors.ItemsSource) | Where-Object Name -eq 'Contoso Mobile GPU').Text | Should -Be "48 ${degree}C"
        }

        It 'says that the drive sensors need administrator rights' {
            (@($gui.Controls.MonitorSensors.ItemsSource) | Where-Object Name -eq 'Drives').Text | Should -Be 'temperature and wear need administrator rights'
        }

        It 'shows temperature, wear and hours of use of every drive for an administrator' {
            $health = [PSCustomObject]@{
                State = 'OK'; Message = ''
                Drives = @(
                    [PSCustomObject]@{ Name = 'Contoso SSD 512'; TemperatureC = 41; WearPercent = 3; PowerOnHours = 5231 }
                    [PSCustomObject]@{ Name = 'Contoso HD 2000'; TemperatureC = 36; WearPercent = $null; PowerOnHours = $null }
                    [PSCustomObject]@{ Name = 'Contoso USB Stick'; TemperatureC = $null; WearPercent = $null; PowerOnHours = $null }
                )
            }
            $rows = @((Show-TestSnapshot -Change @{ DriveHealth = $health }).Controls.MonitorSensors.ItemsSource)

            ($rows | Where-Object Name -eq 'Contoso SSD 512').Text | Should -Be "41 ${degree}C  |  wear 3 %  |  5,231 h powered on"
            ($rows | Where-Object Name -eq 'Contoso HD 2000').Text | Should -Be "36 ${degree}C"
            ($rows | Where-Object Name -eq 'Contoso USB Stick').Text | Should -Be 'reports no sensor values'
            $rows | Where-Object Name -eq 'Drives' | Should -BeNullOrEmpty
        }

        It 'says why the drive sensors could not be read' {
            $health = [PSCustomObject]@{ State = 'Unavailable'; Message = 'The storage service does not answer'; Drives = @() }
            $rows = @((Show-TestSnapshot -Change @{ DriveHealth = $health }).Controls.MonitorSensors.ItemsSource)
            ($rows | Where-Object Name -eq 'Drives').Text | Should -Be 'could not be read: The storage service does not answer'
        }

        It 'shows the thermal zones of the firmware' {
            $rows = @((Show-TestSnapshot -Change @{ Thermal = @([PSCustomObject]@{ Name = 'TZ00'; TemperatureC = 47 }) }).Controls.MonitorSensors.ItemsSource)
            ($rows | Where-Object Name -eq 'Thermal zone TZ00').Text | Should -Be "47 ${degree}C"
        }

        It 'shows the battery with the remaining time while it is in use' {
            $battery = [PSCustomObject]@{ Percent = 64; PluggedIn = $false; MinutesRemaining = 130 }
            $rows = @((Show-TestSnapshot -Change @{ Battery = $battery }).Controls.MonitorSensors.ItemsSource)
            ($rows | Where-Object Name -eq 'Battery').Text | Should -Be '64 %  |  on battery  |  about 2 h 10 min left'
        }

        It 'shows a battery that is being charged without a remaining time' {
            $battery = [PSCustomObject]@{ Percent = 90; PluggedIn = $true; MinutesRemaining = $null }
            $rows = @((Show-TestSnapshot -Change @{ Battery = $battery }).Controls.MonitorSensors.ItemsSource)
            ($rows | Where-Object Name -eq 'Battery').Text | Should -Be '90 %  |  plugged in'
        }
    }

    Context 'programs' {
        It 'lists the busiest programs' {
            @($gui.Controls.MonitorProcesses.ItemsSource).Name | Should -Be 'contoso-app'
            @($gui.Controls.MonitorProcesses.ItemsSource).Text | Should -Be '18 %  |  1 GB'
        }

        It 'lists the programs that use the most memory, in megabytes below one gigabyte' {
            @($gui.Controls.MonitorMemoryProcesses.ItemsSource).Name | Should -Be 'browser'
            @($gui.Controls.MonitorMemoryProcesses.ItemsSource).Text | Should -Be '300 MB'
        }

        It 'lists the programs that read and write the most data' {
            @($gui.Controls.MonitorIoProcesses.ItemsSource).Name | Should -Be 'backup'
            @($gui.Controls.MonitorIoProcesses.ItemsSource).Text | Should -Be '3 MB/s'
            $gui.Controls.MonitorIoEmpty.Visibility | Should -Be 'Collapsed'
        }

        It 'says so when no program reads or writes' {
            $quiet = Show-TestSnapshot -Change @{ IoProcesses = @() }
            $quiet.Controls.MonitorIoEmpty.Visibility | Should -Be 'Visible'
        }
    }

    Context 'history graphs' {
        It 'adds one point per measurement to the graph of every component' {
            $historyGui = New-TestWindow
            foreach ($percent in 10, 20, 30) {
                $cpu = [PSCustomObject]@{ Percent = $percent; FrequencyMHz = 3000; BaseFrequencyMHz = 2400; Processors = @() }
                InModuleScope HelpdeskToolkit -Parameters @{ Gui = $historyGui; Snapshot = (New-TestSnapshot -Change @{ Cpu = $cpu }) } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }
            }

            $historyGui.MonitorHistory.Cpu.ToArray() | Should -Be @(10, 20, 30)
            $historyGui.Controls.MonitorCpuLine.Points.Count | Should -Be 3
            $historyGui.Controls.MonitorCpuArea.Points.Count | Should -Be 5
            $historyGui.Controls.MonitorMemoryLine.Points.Count | Should -Be 3
            $historyGui.Controls.MonitorGpuLine.Points.Count | Should -Be 3
        }

        It 'keeps only the last 60 measurements' {
            $fullGui = New-TestWindow
            1..65 | ForEach-Object { $fullGui.MonitorHistory.Cpu.Add($_) }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $fullGui; Snapshot = (New-TestSnapshot) } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }

            $fullGui.MonitorHistory.Cpu.Count | Should -Be 60
            $fullGui.MonitorHistory.Cpu[59] | Should -Be 37
            $fullGui.MonitorHistory.Cpu[0] | Should -Be 7
        }
    }

    It 'shows when the data was measured' {
        $gui.Controls.PageSubtitle.Text | Should -Match 'Updated 10:30:05'
    }

    It 'copes with a snapshot whose parts could not be read' {
        $empty = @{
            Cpu = $null; System = $null; Memory = $null; Gpu = @(); GpuSensors = @(); Disks = @(); Volumes = @(); Network = @()
            Processes = @(); MemoryProcesses = @(); IoProcesses = @()
        }
        { $script:emptyGui = Show-TestSnapshot -Change $empty } | Should -Not -Throw

        $emptyGui.Controls.MonitorCpuText.Text | Should -Be 'Not available'
        $emptyGui.Controls.MonitorMemoryText.Text | Should -Be 'Not available'
        $emptyGui.Controls.MonitorTileCpu.Text | Should -Be '-'
        $emptyGui.Controls.MonitorTileUptime.Text | Should -Be '-'
        $emptyGui.Controls.MonitorGpuEmpty.Visibility | Should -Be 'Visible'
        $emptyGui.Controls.MonitorGpuGraphFrame.Visibility | Should -Be 'Collapsed'
        @($emptyGui.Controls.MonitorDisks.ItemsSource).Count | Should -Be 0
        @($emptyGui.Controls.MonitorVolumes.ItemsSource).Count | Should -Be 0
    }
}

Describe 'Receive-WindowMonitor' -Skip:(-not $isSta) {
    BeforeEach {
        Mock -ModuleName HelpdeskToolkit Show-WindowMonitor { }
        $gui = New-TestWindow
        $gui.Monitor = @{
            Shared       = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; Snapshot = [PSCustomObject]@{ TakenAt = Get-Date }; Error = $null; Sequence = 1 })
            LastSequence = 0
        }
    }

    It 'displays a new measurement once' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui; Receive-WindowMonitor -Gui $Gui }
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowMonitor -Times 1 -Exactly
        $gui.Monitor.LastSequence | Should -Be 1
    }

    It 'displays the next measurement when the background runspace has produced one' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui }
        $gui.Monitor.Shared.Sequence = 2
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui }
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowMonitor -Times 2 -Exactly
    }

    It 'reports a failed measurement in the subtitle instead of stopping' {
        $gui.Monitor.Shared.Error = 'WMI is not available'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui }
        $gui.Controls.PageSubtitle.Text | Should -Be 'The live data could not be read: WMI is not available'
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowMonitor -Times 0 -Exactly
    }

    It 'does nothing when the monitor was never started' {
        $gui.Monitor = $null
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui } } | Should -Not -Throw
    }
}

Describe 'Enable-WindowMonitor and Disable-WindowMonitor' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        # A module path that does not exist: the background loop then cannot measure, so
        # the test does not depend on this computer, but the loop itself still runs.
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Enable-WindowMonitor -Gui $Gui }
    }

    AfterAll {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui -Stop }
    }

    It 'starts one background runspace and the timer that shows its results' {
        $gui.Monitor.Worker | Should -BeOfType [powershell]
        $gui.Monitor.Shared.Paused | Should -BeFalse
        $gui.MonitorTimer.IsEnabled | Should -BeTrue
    }

    It 'keeps measuring in a loop and records a failure instead of ending' {
        $deadline = (Get-Date).AddSeconds(15)
        while ($gui.Monitor.Shared.Sequence -lt 2 -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 100
        }
        $gui.Monitor.Shared.Sequence | Should -BeGreaterOrEqual 2
        $gui.Monitor.Shared.Error | Should -Not -BeNullOrEmpty
    }

    It 'pauses when another page is opened and keeps the runspace for later' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui }
        $gui.Monitor.Shared.Paused | Should -BeTrue
        $gui.Monitor.Worker | Should -Not -BeNullOrEmpty
        $gui.MonitorTimer.IsEnabled | Should -BeFalse
    }

    It 'resumes with the same runspace when the page is opened again' {
        $worker = $gui.Monitor.Worker
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Enable-WindowMonitor -Gui $Gui }
        $gui.Monitor.Worker | Should -Be $worker
        $gui.Monitor.Shared.Paused | Should -BeFalse
        $gui.MonitorTimer.IsEnabled | Should -BeTrue
    }

    It 'ends the loop and releases the runspace when the window closes' {
        $shared = $gui.Monitor.Shared
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui -Stop }
        $shared.Stop | Should -BeTrue
        $gui.Monitor | Should -BeNullOrEmpty
        $gui.MonitorTimer.IsEnabled | Should -BeFalse
    }

    It 'can be stopped without ever having been started' {
        $freshGui = New-TestWindow
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $freshGui } { Disable-WindowMonitor -Gui $Gui -Stop } } | Should -Not -Throw
    }
}

Describe 'Receive-WindowCheck' -Skip:(-not $isSta) {
    BeforeAll {
        # Starts a background runspace that returns whatever the script produces and
        # waits until it is done, like a finished health check.
        function Start-TestWorker {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only runs a short script in a background runspace.')]
            param($Gui, [string]$Script)

            $Gui.Worker = [powershell]::Create()
            [void]$Gui.Worker.AddScript($Script)
            $Gui.Handle = $Gui.Worker.BeginInvoke()
            [void]$Gui.Handle.AsyncWaitHandle.WaitOne(10000)
        }
    }

    It 'displays the report and re-enables the Run button when the background check has finished' {
        $gui = New-TestWindow
        $gui.Controls.RunButton.IsEnabled = $false
        Start-TestWorker -Gui $gui -Script @'
[PSCustomObject]@{
    PSTypeName = 'HelpdeskToolkit.HealthReport'
    ToolVersion = '9.9.9'; ComputerName = 'TEST-PC-01'; GeneratedAt = '2026-01-15 10:30:00'
    DurationSeconds = 1.5; IsElevated = $true; EventLogDays = 7
    Summary = @{ OK = 1; Warning = 0; Critical = 0; Info = 0 }
    Results = @([PSCustomObject]@{ Category = 'System'; Check = 'Uptime'; Description = ''; Status = 'OK'; Value = '1 d'; Details = @(); Allowed = ''; Typical = ''; Recommendation = '' })
}
'@
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

        $gui.Controls.OkCount.Text | Should -Be '1'
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'Live monitor', 'System')
        $gui.Controls.RunButton.IsEnabled | Should -BeTrue
        $gui.Controls.RunButton.Content | Should -Be 'Run check'
        $gui.Controls.RunPanel.Visibility | Should -Be 'Collapsed'
        $gui.Worker | Should -BeNullOrEmpty
    }

    It 'shows the category, the step and the percentage of a check that is still running' {
        $gui = New-TestWindow
        $gui.Worker = [powershell]::Create()
        # Progress of a Windows cmdlet (another activity) must not replace the progress
        # of the health check.
        [void]$gui.Worker.AddScript(@'
Write-Progress -Activity 'PC Health Check' -Status 'Hardware' -CurrentOperation 'step 3 of 10' -PercentComplete 20
Write-Progress -Activity 'Some Windows cmdlet' -Status 'Working' -PercentComplete 90
Start-Sleep -Seconds 30
'@)
        $gui.Handle = $gui.Worker.BeginInvoke()
        try {
            $deadline = (Get-Date).AddSeconds(15)
            while ($gui.Worker.Streams.Progress.Count -lt 2 -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

            $gui.Controls.RunTitle.Text | Should -Be 'Checking: Hardware'
            $gui.Controls.RunStep.Text | Should -Be 'step 3 of 10'
            $gui.Controls.RunPercent.Text | Should -Be '20 %'
            $gui.Controls.ProgressBar.HasAnimatedProperties | Should -BeTrue
            $gui.Worker | Should -Not -BeNullOrEmpty
        }
        finally {
            $gui.Worker.Stop()
            $gui.Worker.Dispose()
        }
    }

    It 'reports a failed check in the status bar instead of crashing the window' {
        $gui = New-TestWindow
        Start-TestWorker -Gui $gui -Script 'Write-Error "Module could not be loaded"'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

        $gui.Controls.StatusText.Text | Should -Match 'The check failed: Module could not be loaded'
        $gui.Controls.RunButton.IsEnabled | Should -BeTrue
        $gui.Report | Should -BeNullOrEmpty
    }

    It 'does nothing when no check is running' {
        $gui = New-TestWindow
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui } } | Should -Not -Throw
    }
}

Describe 'Invoke-ElevatedRestart' -Skip:(-not $isSta) {
    It 'starts the application again elevated and hidden, through the launcher script' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        $gui = New-TestWindow
        $started = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-ElevatedRestart -Gui $Gui }

        $started | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter {
            $Verb -eq 'RunAs' -and
            $WindowStyle -eq 'Hidden' -and
            $FilePath -like '*\WindowsPowerShell\v1.0\powershell.exe' -and
            ($ArgumentList -join ' ') -match 'Start-HelpdeskToolkit\.ps1'
        }
    }

    It 'keeps the window open and says so when the user declines the Windows prompt' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'The operation was canceled by the user.' }
        $gui = New-TestWindow
        $started = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-ElevatedRestart -Gui $Gui }

        $started | Should -BeFalse
        $gui.Controls.StatusText.Text | Should -Match 'Administrator rights were not granted'
    }
}

Describe 'Invoke-WindowCheck' -Skip:(-not $isSta) {
    It 'does not start a second check while one is running' {
        $gui = New-TestWindow
        $gui.Worker = 'a check is already running'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }

        $gui.Worker | Should -Be 'a check is already running'
        $gui.Controls.RunButton.IsEnabled | Should -BeTrue
        $gui.Controls.RunPanel.Visibility | Should -Be 'Collapsed'
    }

    It 'shows the empty progress panel and starts the check in the background' {
        $gui = New-TestWindow
        # A module path that does not exist: the background runspace fails at once
        # instead of examining this computer.
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        $gui.Controls.ProgressBar.Value = 80
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }

            $gui.Controls.RunPanel.Visibility | Should -Be 'Visible'
            $gui.Controls.RunPercent.Text | Should -Be '0 %'
            $gui.Controls.ProgressBar.Value | Should -Be 0
            $gui.Controls.RunButton.IsEnabled | Should -BeFalse
            $gui.Worker | Should -BeOfType [powershell]
        }
        finally {
            $gui.Timer.Stop()
            if ($gui.Worker) {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }
}
