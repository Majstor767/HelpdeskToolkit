# Tests for what the window gained from the comparison with other health tools: the
# Timeline page, the points of the score per category, the Internet tile of the Live
# monitor and the button that opens the support page of the maker.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $today = (Get-Date).Date
    $testResults = @(
        New-TestResult -Category 'System' -Check 'Uptime' -Status Warning -Value '9 d' -Recommendation 'Restart.'
        New-TestResult -Category 'Specifications' -Check 'Serial number' -Status Info -Value 'CNT4012XYZ'
        New-TestResult -Category 'Specifications' -Check 'Warranty and support' -Status Info -Value 'Dell Inc.: looked up with the serial number on the support page of the manufacturer' -Recommendation 'The support page shows the warranty.'
        New-TestResult -Category 'Security' -Check 'Firewall' -Status Critical -Value 'Disabled' -Recommendation 'Turn it on.'
        New-TestResult -Category 'Security' -Check 'SmartScreen' -Status Warning -Value 'Disabled' -Recommendation 'Turn it on.'
        New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
    )

    # The time line of a report: two days, newest first, times as text.
    function Get-TestTimeline {
        @(
            [PSCustomObject]@{ Time = '{0:yyyy-MM-dd} 14:20' -f $today; Level = 'Problem'; Kind = 'Program crashed'; Title = 'editor.exe'; Count = 3 }
            [PSCustomObject]@{ Time = '{0:yyyy-MM-dd} 09:05' -f $today; Level = 'Change'; Kind = 'Update installed'; Title = 'Antivirus definitions'; Count = 2 }
            [PSCustomObject]@{ Time = '{0:yyyy-MM-dd} 16:40' -f $today.AddDays(-1); Level = 'Change'; Kind = 'Program installed'; Title = 'Contoso Edit'; Count = 1 }
            [PSCustomObject]@{ Time = '{0:yyyy-MM-dd} 08:00' -f $today.AddDays(-5); Level = 'Problem'; Kind = 'Unexpected shutdown'; Title = ''; Count = 1 }
        )
    }

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param([object[]]$Result = $testResults, [object[]]$Timeline = (Get-TestTimeline), [switch]$NoTimeline)

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $report = New-TestReport -Result $Result
        if (-not $NoTimeline) {
            $report | Add-Member -NotePropertyName Timeline -NotePropertyValue @($Timeline)
        }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report }
        $gui
    }

    function Show-TestPage {
        param($Gui, [string]$Name, [switch]$KeepScroll)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui; Name = $Name; KeepScroll = [bool]$KeepScroll } { Show-WindowPage -Gui $Gui -Name $Name -KeepScroll:$KeepScroll }
    }
}

Describe 'The Timeline page' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    Context 'the page list' {
        It 'has a Timeline entry after the Live monitor, before the categories' {
            $gui = New-TestWindow
            @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'Live monitor', 'Timeline', 'System', 'Specifications', 'Security', 'Network')
        }

        It 'has no Timeline entry for a report that an older version saved without one' {
            $gui = New-TestWindow -NoTimeline
            @($gui.Controls.CategoryList.ItemsSource).Name | Should -Not -Contain 'Timeline'
        }

        It 'has no Timeline entry before the first check' {
            $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
            @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'Live monitor')
        }
    }

    Context 'showing the page' {
        BeforeAll {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Timeline'
            $days = @($gui.Controls.TimelineItems.ItemsSource)
        }

        It 'shows the panel of the timeline in place of the results, without the result filters' {
            $gui.Page | Should -Be 'Timeline'
            $gui.Controls.PageTitle.Text | Should -Be 'Timeline'
            $gui.Controls.TimelinePanel.Visibility | Should -Be 'Visible'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Collapsed'
            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.OverviewPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.FilterPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
        }

        It 'counts the problems and the changes of the whole time line' {
            $gui.Controls.TimelineSummary.Text | Should -Be '2 problems and 2 changes on record'
        }

        It 'groups the entries by day, newest day first, and names today and yesterday' {
            $days.Count | Should -Be 3
            $days[0].Day | Should -Be 'Today'
            $days[1].Day | Should -Be 'Yesterday'
            $days[2].Day | Should -Be $today.AddDays(-5).ToString('dddd, yyyy-MM-dd', [cultureinfo]'en-US')
        }

        It 'says for each day how many problems and changes it had' {
            $days[0].Summary | Should -Be '1 problem, 1 change'
            $days[1].Summary | Should -Be '1 change'
            $days[2].Summary | Should -Be '1 problem'
        }

        It 'shows the time, what happened and how often' {
            $crash = $days[0].Events[0]
            $crash.Time | Should -Be '14:20'
            $crash.Level | Should -Be 'Problem'
            $crash.Kind | Should -Be 'Program crashed'
            $crash.Title | Should -Be 'editor.exe'
            $crash.Times | Should -Be ('{0} 3' -f [char]0xD7)
            # Something that happened once needs no number.
            $days[1].Events[0].Times | Should -Be ''
        }

        It 'hides the panel again on every other page' -ForEach @('Overview', 'System', 'Live monitor', 'Settings') {
            $other = New-TestWindow
            Show-TestPage -Gui $other -Name 'Timeline'
            Show-TestPage -Gui $other -Name $_
            $other.Controls.TimelinePanel.Visibility | Should -Be 'Collapsed'
        }
    }

    Context 'the filter of the page' {
        BeforeAll {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Timeline'
        }

        It 'offers everything, the problems or the changes' {
            @($gui.Controls.TimelineFilter.Items | ForEach-Object { [string]$_.Tag }) | Should -Be @('', 'Problem', 'Change')
            $gui.Controls.TimelineFilter.SelectedIndex | Should -Be 0
        }

        It 'leaves only the problems' {
            $gui.Controls.TimelineFilter.SelectedIndex = 1
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTimeline -Gui $Gui }
            $days = @($gui.Controls.TimelineItems.ItemsSource)
            $days.Count | Should -Be 2
            @($days | ForEach-Object { $_.Events } | ForEach-Object { $_.Level }) | Sort-Object -Unique | Should -Be 'Problem'
            # The count at the top stays that of the whole time line.
            $gui.Controls.TimelineSummary.Text | Should -Be '2 problems and 2 changes on record'
        }

        It 'leaves only the changes' {
            $gui.Controls.TimelineFilter.SelectedIndex = 2
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTimeline -Gui $Gui }
            @($gui.Controls.TimelineItems.ItemsSource | ForEach-Object { $_.Events } | ForEach-Object { $_.Kind }) | Should -Be @('Update installed', 'Program installed')
        }
    }

    Context 'with nothing on record' {
        It 'says so instead of showing an empty page' {
            $gui = New-TestWindow -Timeline @()
            Show-TestPage -Gui $gui -Name 'Timeline'
            @($gui.Controls.TimelineItems.ItemsSource).Count | Should -Be 0
            $gui.Controls.EmptyText.Visibility | Should -Be 'Visible'
            $gui.Controls.EmptyText.Text | Should -Be 'Windows has nothing on record for the last weeks.'
        }

        It 'says that nothing of the chosen kind is on record' {
            $gui = New-TestWindow -Timeline @([PSCustomObject]@{ Time = '2026-01-14 09:05'; Level = 'Change'; Kind = 'Program installed'; Title = 'Contoso Edit'; Count = 1 })
            Show-TestPage -Gui $gui -Name 'Timeline'
            $gui.Controls.TimelineFilter.SelectedIndex = 1
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTimeline -Gui $Gui }
            $gui.Controls.EmptyText.Text | Should -Be 'Nothing of that kind is on record.'
            $gui.Controls.EmptyText.Visibility | Should -Be 'Visible'
        }
    }

    Context 'when an automatic check replaces the report' {
        It 'stays on the Timeline page and shows the new time line' {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Timeline'
            $gui.Controls.CategoryList.SelectedIndex = 2

            $newer = New-TestReport -Result $testResults
            $newer | Add-Member -NotePropertyName Timeline -NotePropertyValue @([PSCustomObject]@{ Time = '2026-01-14 09:05'; Level = 'Change'; Kind = 'Driver installed'; Title = 'Contoso Graphics 770'; Count = 1 })
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $newer } { Show-WindowReport -Gui $Gui -Report $Report -KeepPage }

            $gui.Page | Should -Be 'Timeline'
            $gui.Controls.TimelinePanel.Visibility | Should -Be 'Visible'
            @($gui.Controls.TimelineItems.ItemsSource)[0].Events[0].Kind | Should -Be 'Driver installed'
        }
    }
}

Describe 'The points of the score on the Overview' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    It 'says which categories cost how many points, the most expensive first' {
        $gui = New-TestWindow
        $gui.Controls.ScoreDetailText.Visibility | Should -Be 'Visible'
        # Test penalties: 15 per critical result, 4 per warning
        $gui.Controls.ScoreDetailText.Text | Should -Be 'Points lost: Security -19, System -4'
        $gui.Controls.ScoreCount.Text | Should -Be '77'
    }

    It 'is hidden when no points were lost' {
        $gui = New-TestWindow -Result @(New-TestResult -Status OK)
        $gui.Controls.ScoreDetailText.Visibility | Should -Be 'Collapsed'
    }

    It 'puts the same into the summary that is copied for a ticket' {
        $report = New-TestReport -Result $testResults
        $text = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthSummaryText -Report $Report }
        ($text -split "`r`n")[1] | Should -Be 'Checked: 2026-01-15 10:30:00  |  Health score: 77 of 100 (Security -19, System -4)'
    }
}

Describe 'The button that opens the support page of the maker' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { }
    }

    It 'is offered on the card of a maker whose page is known' {
        $gui = New-TestWindow
        Show-TestPage -Gui $gui -Name 'Specifications'
        $card = @($gui.Controls.ResultItems.ItemsSource) | Where-Object SourceCheck -eq 'Warranty and support'
        $card.ActionLabel | Should -Be 'Open the support page'
        $card.SourceValue | Should -Match '^Dell Inc\.'
    }

    It 'opens the page of that maker and copies the serial number of the report' {
        $gui = New-TestWindow
        $opened = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowSupportPage -Gui $Gui -Value 'Dell Inc.: looked up with the serial number' }

        $opened | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'https://www.dell.com/support/home' }
        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 1 -Exactly -ParameterFilter { $Value -eq 'CNT4012XYZ' }
        $gui.Controls.StatusText.Text | Should -Be 'The support page is open. The serial number CNT4012XYZ was copied: paste it into the search field there (Ctrl+V).'
    }

    It 'never puts the serial number into the address' {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowSupportPage -Gui $Gui -Value 'Dell Inc.' } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -ParameterFilter { $FilePath -match 'CNT4012XYZ' -or $ArgumentList -match 'CNT4012XYZ' }
    }

    It 'copies nothing when the maker did not set a serial number' {
        $results = @($testResults | Where-Object Check -ne 'Serial number') + (New-TestResult -Category 'Specifications' -Check 'Serial number' -Status Info -Value 'Not set by the manufacturer')
        $gui = New-TestWindow -Result $results
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowSupportPage -Gui $Gui -Value 'Dell Inc.' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 0 -Exactly
        $gui.Controls.StatusText.Text | Should -Be 'The support page is open. Enter the serial number from the label of the computer there.'
    }

    It 'still opens the page when the clipboard is busy' {
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { throw 'The clipboard is in use' }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowSupportPage -Gui $Gui -Value 'Dell Inc.' } | Should -BeTrue
        $gui.Controls.StatusText.Text | Should -Be 'The support page is open. Enter the serial number CNT4012XYZ there.'
    }

    It 'opens nothing for a maker that is not listed' {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowSupportPage -Gui $Gui -Value 'Contoso Computers' } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly
        $gui.Controls.StatusText.Text | Should -Be 'Windows could not open that place.'
    }

    It 'is what a click on the button of that card does' {
        $gui = New-TestWindow
        Show-TestPage -Gui $gui -Name 'Specifications'
        $card = @($gui.Controls.ResultItems.ItemsSource) | Where-Object SourceCheck -eq 'Warranty and support'
        $button = New-Object -TypeName System.Windows.Controls.Button
        $button.DataContext = $card

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Button = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Button }
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'https://www.dell.com/support/home' }
        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 1 -Exactly
    }
}

Describe 'The Internet tile of the Live monitor' -Skip:(-not $isSta) {
    BeforeAll {
        # A snapshot with only what this tile needs; the other parts are empty.
        function New-TestSnapshot {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param($Latency, [switch]$Old)

            $parts = [ordered]@{
                TakenAt = [datetime]'2026-01-15 10:30:05'; Cpu = $null; System = $null; Memory = $null; Gpu = @(); GpuSensors = @(); Disks = @(); Volumes = @()
                DriveHealth = $null; Thermal = @(); Battery = $null; Processes = @(); MemoryProcesses = @(); IoProcesses = @()
                Network = @([PSCustomObject]@{ Name = 'Contoso Ethernet'; ReceivedBytesPerSecond = 125000; SentBytesPerSecond = 1250; LinkBitsPerSecond = 0 })
            }
            if (-not $Old) {
                $parts.Latency = $Latency
            }
            [PSCustomObject]$parts
        }

        function Show-TestSnapshot {
            param($Gui, $Snapshot)
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui; Snapshot = $Snapshot } { Show-WindowMonitor -Gui $Gui -Snapshot $Snapshot }
        }

        function New-TestLatency {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param($Internet = 24, $Gateway = 0)
            [PSCustomObject]@{ Gateway = '192.0.2.254'; GatewayMs = $Gateway; Internet = '192.0.2.1'; InternetMs = $Internet }
        }
    }

    It 'exposes the control <_>' -ForEach @('MonitorLatencyTile', 'MonitorLatencyDot', 'MonitorTileLatency', 'MonitorTileLatencySub') {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'shows the answer time of the internet, the average and what was lost, with a green dot' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        Show-TestSnapshot -Gui $gui -Snapshot (New-TestSnapshot -Latency (New-TestLatency -Internet 20))
        Show-TestSnapshot -Gui $gui -Snapshot (New-TestSnapshot -Latency (New-TestLatency -Internet 24))

        $gui.Controls.MonitorTileLatency.Text | Should -Be '24 ms'
        $gui.Controls.MonitorTileLatencySub.Text | Should -Be 'average 22 ms, 0 % lost'
        $gui.Controls.MonitorLatencyDot.Fill | Should -Be $gui.Window.FindResource('OkBrush')
        $gui.Controls.MonitorLatencyTile.ToolTip | Should -Match '^Fine'
        $gui.MonitorHistory.Latency.ToArray() | Should -Be @(20, 24)
    }

    It 'lists the router and the internet below the adapters of the Network section' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        Show-TestSnapshot -Gui $gui -Snapshot (New-TestSnapshot -Latency (New-TestLatency -Internet 24 -Gateway 0))

        $rows = @($gui.Controls.MonitorNetwork.ItemsSource)
        $rows.Name | Should -Be @('Contoso Ethernet', 'Router answers (192.0.2.254)', 'Internet answers (192.0.2.1)')
        # An answer within the same millisecond
        $rows[1].Text | Should -Be 'under 1 ms'
        $rows[2].Text | Should -Be '24 ms  |  average 24 ms, 0 % lost'
    }

    It 'leaves out the router on a computer without a gateway' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $latency = [PSCustomObject]@{ Gateway = ''; GatewayMs = $null; Internet = '192.0.2.1'; InternetMs = 30 }
        Show-TestSnapshot -Gui $gui -Snapshot (New-TestSnapshot -Latency $latency)
        @($gui.Controls.MonitorNetwork.ItemsSource).Name | Should -Be @('Contoso Ethernet', 'Internet answers (192.0.2.1)')
    }

    It 'turns the dot red and says "no answer" when the internet stops answering' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        1..3 | ForEach-Object { Show-TestSnapshot -Gui $gui -Snapshot (New-TestSnapshot -Latency (New-TestLatency -Internet $null -Gateway 1)) }

        $gui.Controls.MonitorTileLatency.Text | Should -Be 'no answer'
        $gui.Controls.MonitorLatencyDot.Fill | Should -Be $gui.Window.FindResource('CriticalBrush')
        $gui.MonitorHistory.Latency.ToArray() | Should -Be @(-1, -1, -1)
        # The router still answers: the fault is beyond the local network.
        @($gui.Controls.MonitorNetwork.ItemsSource)[1].Text | Should -Be '1 ms'
    }

    It 'says that nothing is measured while the network tests are skipped' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        Show-TestSnapshot -Gui $gui -Snapshot (New-TestSnapshot -Latency $null)

        $gui.Controls.MonitorTileLatency.Text | Should -Be '-'
        $gui.Controls.MonitorTileLatencySub.Text | Should -Be 'not measured: network tests are skipped'
        $gui.Controls.MonitorLatencyDot.Fill | Should -Be $gui.Window.FindResource('NeutralBrush')
        @($gui.Controls.MonitorNetwork.ItemsSource).Count | Should -Be 1
        $gui.MonitorHistory.Latency.Count | Should -Be 0
    }

    It 'copes with a snapshot that has no answer times at all' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        { Show-TestSnapshot -Gui $gui -Snapshot (New-TestSnapshot -Old) } | Should -Not -Throw
        $gui.Controls.MonitorTileLatency.Text | Should -Be '-'
    }
}

Describe 'The answer times in the monitor loop and in a recording' -Skip:(-not $isSta) {
    It 'tells the loop not to ping while "Skip network tests" is ticked' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Monitor = @{ Shared = [hashtable]::Synchronized(@{ Sequence = 0; Latency = $true; Error = $null; Snapshot = $null }); LastSequence = 0 }

        $gui.Controls.SkipNetworkCheckBox.IsChecked = $true
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui }
        $gui.Monitor.Shared.Latency | Should -BeFalse

        $gui.Controls.SkipNetworkCheckBox.IsChecked = $false
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui }
        $gui.Monitor.Shared.Latency | Should -BeTrue
    }

    It 'writes the answer times as the last two columns of a recording' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.OutputFolder = Join-Path -Path $TestDrive -ChildPath 'Recordings'
        $gui.Monitor = @{ Shared = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; IntervalSeconds = 2 }); LastSequence = 0; Worker = $null }
        $path = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Enable-WindowRecording -Gui $Gui -Minutes 5 }
        $delimiter = [string][cultureinfo]::CurrentCulture.TextInfo.ListSeparator

        $snapshot = [PSCustomObject]@{
            TakenAt = [datetime]'2026-01-15 10:30:05'; Cpu = $null; Memory = $null; Gpu = @(); GpuSensors = @(); Disks = @(); Network = @(); Processes = @()
            Latency = [PSCustomObject]@{ Gateway = '192.0.2.254'; GatewayMs = 2; Internet = '192.0.2.1'; InternetMs = $null }
        }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Snapshot = $snapshot } { Add-WindowRecordingRow -Gui $Gui -Snapshot $Snapshot }

        $lines = @(Get-Content -LiteralPath $path)
        ($lines[0] -split [regex]::Escape($delimiter))[-2..-1] | Should -Be @('PingRouterMs', 'PingInternetMs')
        # The router answered in 2 ms, the internet did not answer.
        ($lines[1] -split [regex]::Escape($delimiter))[-2..-1] | Should -Be @('2', '')
    }
}

Describe 'Get-PerformanceSnapshot -IncludeLatency' {
    BeforeAll {
        # The performance classes are not needed here; every part that cannot be read stays empty.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'not available in this test' }
        Mock -ModuleName HelpdeskToolkit Get-NvidiaGpuStatus { }
        Mock -ModuleName HelpdeskToolkit Get-NetworkLatency { [PSCustomObject]@{ Gateway = '192.0.2.254'; GatewayMs = 1; Internet = '192.0.2.1'; InternetMs = 18 } }
    }

    It 'sends nothing over the network without the switch' {
        $snapshot = Get-PerformanceSnapshot
        $snapshot.Latency | Should -BeNullOrEmpty
        Should -Invoke -ModuleName HelpdeskToolkit Get-NetworkLatency -Times 0 -Exactly
    }

    It 'measures the answer times with the switch, with the time limit of the configuration' {
        $snapshot = Get-PerformanceSnapshot -IncludeLatency
        $snapshot.Latency.InternetMs | Should -Be 18
        Should -Invoke -ModuleName HelpdeskToolkit Get-NetworkLatency -Times 1 -Exactly -ParameterFilter { $TimeoutMs -eq 1000 }
    }

    It 'still returns a snapshot when the answer times cannot be measured' {
        Mock -ModuleName HelpdeskToolkit Get-NetworkLatency { throw 'No network' }
        $snapshot = Get-PerformanceSnapshot -IncludeLatency
        $snapshot | Should -Not -BeNullOrEmpty
        $snapshot.Latency | Should -BeNullOrEmpty
    }
}

Describe 'The list of programs without support on another computer' {
    It 'is part of the script that is sent there, because the configuration file is not' {
        $script = InModuleScope HelpdeskToolkit { Get-RemoteModuleScript }
        $script | Should -Match '\$script:EndOfLife = @\(\(ConvertFrom-DataFileText -Text @'''
        $script | Should -Match 'Adobe Flash Player'
    }

    It 'gives a script that still parses' {
        $script = InModuleScope HelpdeskToolkit { Get-RemoteModuleScript }
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'is read from that text on the other side' {
        $text = [System.IO.File]::ReadAllText((Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit\Config\EndOfLife.psd1'))
        $products = @((InModuleScope HelpdeskToolkit -Parameters @{ Text = $text } { ConvertFrom-DataFileText -Text $Text }).Products)
        $products.Count | Should -BeGreaterThan 10
        $products[0].Match | Should -Be '^Adobe Flash Player'
    }
}

Describe 'Get-NetworkLatency' {
    It 'returns the addresses and no time for a target that does not answer' {
        # No gateway; the internet target of the test configuration is an address that
        # is reserved for documentation and never answers.
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { [PSCustomObject]@{ DefaultIPGateway = $null } }
        $latency = InModuleScope HelpdeskToolkit { Get-NetworkLatency -TimeoutMs 100 }

        $latency.Gateway | Should -Be ''
        $latency.GatewayMs | Should -BeNullOrEmpty
        $latency.Internet | Should -Be '192.0.2.1'
        $latency.InternetMs | Should -BeNullOrEmpty
    }

    It 'takes the first IPv4 gateway of the connected adapters' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance {
            [PSCustomObject]@{ DefaultIPGateway = @('fe80::1', '192.0.2.254') }
            [PSCustomObject]@{ DefaultIPGateway = @('192.0.2.253') }
        }
        (InModuleScope HelpdeskToolkit { Get-NetworkLatency -TimeoutMs 100 }).Gateway | Should -Be '192.0.2.254'
    }

    It 'still measures the internet when the adapters cannot be read' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'WMI is not working' }
        (InModuleScope HelpdeskToolkit { Get-NetworkLatency -TimeoutMs 100 }).Internet | Should -Be '192.0.2.1'
    }
}

Describe 'Get-LatencyStatus' {
    # Test limits: 150 ms, 5 % lost, judged over the last 6 measurements.
    BeforeAll {
        function Get-TestLatencyStatus {
            param([double[]]$History)
            InModuleScope HelpdeskToolkit -Parameters @{ History = $History } { Get-LatencyStatus -History $History }
        }
    }

    It 'has nothing to say before the first measurement' {
        $status = Get-TestLatencyStatus -History @()
        $status.Level | Should -Be 'None'
        $status.Value | Should -Be '-'
    }

    It 'is fine with quick answers and shows the newest one' {
        $status = Get-TestLatencyStatus -History 20, 22, 18, 24
        $status.Level | Should -Be 'Ok'
        $status.Value | Should -Be '24 ms'
        $status.Sub | Should -Be 'average 21 ms, 0 % lost'
        $status.Summary | Should -Match '^Fine'
    }

    It 'only looks at the last measurements' {
        # Six slow ones long ago, six quick ones since.
        (Get-TestLatencyStatus -History (@(900) * 6 + @(20) * 6)).Level | Should -Be 'Ok'
    }

    It 'turns orange when the answers are slow' {
        $status = Get-TestLatencyStatus -History 180, 200, 190, 170
        $status.Level | Should -Be 'Near'
        $status.Summary | Should -Match 'unsteady'
    }

    It 'turns red when many answers get lost, although the others are quick' {
        # One of six lost = 17 %, more than twice the 5 % that are fine
        $status = Get-TestLatencyStatus -History 20, -1, 20, 20, 20, 20
        $status.Level | Should -Be 'Over'
        $status.Sub | Should -Be 'average 20 ms, 17 % lost'
        $status.Summary | Should -Match 'bad'
    }

    It 'turns red when the answers are very slow' {
        (Get-TestLatencyStatus -History 400, 350, 380).Level | Should -Be 'Over'
    }

    It 'turns red and says so when the internet stopped answering' {
        $status = Get-TestLatencyStatus -History 20, 20, 20, -1, -1, -1
        $status.Level | Should -Be 'Over'
        $status.Value | Should -Be 'no answer'
        $status.Summary | Should -Match 'does not answer'
    }

    It 'copes with a history in which nothing ever answered' {
        $status = Get-TestLatencyStatus -History -1
        $status.Level | Should -Be 'Over'
        $status.Sub | Should -Be '100 % lost'
    }
}

Describe 'Get-HealthScoreBreakdown' {
    It 'tells how many points each category cost, the most expensive first' {
        $results = @(
            New-TestResult -Category 'System' -Status Warning
            New-TestResult -Category 'System' -Status OK
            New-TestResult -Category 'Security' -Status Critical
            New-TestResult -Category 'Security' -Status Warning
            New-TestResult -Category 'Network' -Status Info
        )
        $lost = @(InModuleScope HelpdeskToolkit -Parameters @{ Result = $results } { Get-HealthScoreBreakdown -Result $Result })

        $lost.Category | Should -Be @('Security', 'System')
        # Test penalties: 15 per critical result, 4 per warning
        $lost[0].Points | Should -Be 19
        $lost[0].Critical | Should -Be 1
        $lost[0].Warning | Should -Be 1
        $lost[1].Points | Should -Be 4
    }

    It 'returns nothing when no points were lost' {
        $results = @(New-TestResult -Status OK; New-TestResult -Status Info)
        InModuleScope HelpdeskToolkit -Parameters @{ Result = $results } { Get-HealthScoreBreakdown -Result $Result } | Should -BeNullOrEmpty
        InModuleScope HelpdeskToolkit { Get-HealthScoreBreakdown -Result @() } | Should -BeNullOrEmpty
    }

    It 'adds up to what the score lost' {
        $results = @(
            New-TestResult -Category 'System' -Status Warning
            New-TestResult -Category 'Hardware' -Status Critical
            New-TestResult -Category 'Hardware' -Status Warning
        )
        $lost = @(InModuleScope HelpdeskToolkit -Parameters @{ Result = $results } { Get-HealthScoreBreakdown -Result $Result })
        $report = New-TestReport -Result $results
        100 - ($lost | Measure-Object -Property Points -Sum).Sum | Should -Be $report.Score
    }
}
