# Tests for what happens after the first check: the automatic check in the background,
# the notices about new problems, the way from a notice to its result, and the
# Settings button that replaced the entry in the page list.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param()

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }

    # A report whose results have the given statuses.
    function New-TestStateReport {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Uptime = 'OK', [string]$Disk = 'OK', [string]$Memory = 'OK', [string]$Time = '2026-01-15 10:30:00')

        $report = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status $Uptime -Value '9 d' -Recommendation 'Restart the computer.'
            New-TestResult -Category 'Hardware' -Check 'CPU load' -Status OK -Value '12 %'
            New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status $Memory -Value '91 % (14.5 GB of 16 GB used)' -Recommendation 'Close programs.'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status $Disk -Value '3 % free' -Recommendation 'Free up space.'
            New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
        )
        $report.GeneratedAt = $Time
        $report
    }

    function Show-TestReport {
        param($Gui, $Report, [switch]$KeepPage)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui; Report = $Report; KeepPage = [bool]$KeepPage } { Show-WindowReport -Gui $Gui -Report $Report -KeepPage:$KeepPage }
    }

    # Lets the window receive a finished check that returns the given report.
    function Complete-TestCheck {
        param($Gui, $Report, [switch]$Background)

        $Gui.Worker = [powershell]::Create()
        [void]$Gui.Worker.AddScript('param($Report) $Report.PSObject.TypeNames.Insert(0, "HelpdeskToolkit.HealthReport"); $Report').AddArgument($Report)
        $Gui.Handle = $Gui.Worker.BeginInvoke()
        [void]$Gui.Handle.AsyncWaitHandle.WaitOne(10000)
        $Gui.Background = [bool]$Background
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui } { Receive-WindowCheck -Gui $Gui }
    }
}

Describe 'The Settings button' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    BeforeEach {
        $gui = New-TestWindow
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Disk Critical)
    }

    It 'is a button with a gear below the page list, not an entry of the list' {
        $gui.Controls.SettingsButton | Should -Not -BeNullOrEmpty
        $gui.Controls.SettingsButton.Content | Should -Be 'Settings'
        # The gear of the icon font of Windows
        [int][char]$gui.Controls.SettingsButton.Tag | Should -Be 0xE713
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Not -Contain 'Settings'
    }

    It 'opens the settings and takes the selection off the page list' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings' }

        $gui.Page | Should -Be 'Settings'
        $gui.Controls.SettingsPanel.Visibility | Should -Be 'Visible'
        $gui.Controls.CategoryList.SelectedIndex | Should -Be -1
        $gui.Loading | Should -BeFalse
    }

    It 'is drawn like the selected entry while its page is open, and like the others afterwards' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings' }
        [string]$gui.Controls.SettingsButton.Background.Color | Should -Be ([string]$gui.Window.FindResource('SelectedBrush').Color)

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        [string]$gui.Controls.SettingsButton.Background.Color | Should -Not -Be ([string]$gui.Window.FindResource('SelectedBrush').Color)
        $gui.Page | Should -Be 'Overview'
    }

    It 'stays on the settings when the page is drawn again without a name' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings'; Show-WindowPage -Gui $Gui }
        $gui.Controls.SettingsPanel.Visibility | Should -Be 'Visible'
    }

    It 'is clicked by Ctrl+,' {
        $script:clicked = 0
        $gui.Controls.SettingsButton.Add_Click({ $script:clicked++ })
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'OemComma' -Control } | Should -BeTrue
        $clicked | Should -Be 1
    }

    It 'lists its shortcut on the Settings page' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowSetting -Gui $Gui }
        @($gui.Controls.ShortcutItems.ItemsSource).Name | Should -Contain 'Ctrl+,'
    }
}

Describe 'The Overview before and during the first check' -Skip:(-not $isSta) {
    It 'asks to start a check while there are no results' {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        $gui.Controls.EmptyText.Text | Should -Be 'No results yet. Click Run check.'
    }

    It 'says that the check is running instead of "No results yet"' {
        $gui = New-TestWindow
        # A module path that does not exist: the background runspace fails at once
        # instead of examining this computer.
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }

            $gui.Controls.EmptyText.Text | Should -Be 'Checking the computer ... The results appear here as soon as the check is finished.'
            $gui.Controls.EmptyText.Visibility | Should -Be 'Visible'
            $gui.Controls.PageSubtitle.Text | Should -Be 'The check is running. It takes about half a minute.'
        }
        finally {
            $gui.Timer.Stop()
            $gui.Worker.Stop()
            $gui.Worker.Dispose()
        }
    }

    It 'shows the hint again when the first check has failed' {
        $gui = New-TestWindow
        $gui.Worker = [powershell]::Create()
        [void]$gui.Worker.AddScript('Write-Error "Module could not be loaded"')
        $gui.Handle = $gui.Worker.BeginInvoke()
        [void]$gui.Handle.AsyncWaitHandle.WaitOne(10000)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        $gui.Controls.EmptyText.Text | Should -Match '^Checking the computer'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }
        $gui.Controls.EmptyText.Text | Should -Be 'No results yet. Click Run check.'
    }

    It 'leaves the Live monitor open when a check is started from it' {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        $gui = New-TestWindow
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Live monitor' }
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }
            $gui.Controls.MonitorPanel.Visibility | Should -Be 'Visible'
            $gui.Page | Should -Be 'Live monitor'
        }
        finally {
            $gui.Timer.Stop()
            $gui.Worker.Stop()
            $gui.Worker.Dispose()
        }
    }
}

Describe 'Invoke-WindowAutoCheck' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Invoke-WindowCheck { }
    }

    BeforeEach {
        $gui = New-TestWindow
        $gui.Settings = @{ Language = 'en'; Theme = 'System'; MonitorIntervalSeconds = 2; AutoCheckMinutes = 5; StartupElevation = 'Ask' }
        $gui.Report = New-TestStateReport
        $gui.LastCheckAt = (Get-Date).AddMinutes(-6)
    }

    It 'repeats the check in the background when the last one ended long enough ago' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowAutoCheck -Gui $Gui } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 1 -Exactly -ParameterFilter { $Background }
    }

    It 'waits until the interval of the settings has passed' {
        $gui.LastCheckAt = (Get-Date).AddMinutes(-4)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowAutoCheck -Gui $Gui } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly
    }

    It 'follows the interval of the settings' {
        $gui.Settings.AutoCheckMinutes = 30
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowAutoCheck -Gui $Gui } | Should -BeFalse
        $gui.LastCheckAt = (Get-Date).AddMinutes(-31)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowAutoCheck -Gui $Gui } | Should -BeTrue
    }

    It 'does nothing when the setting is "Never"' {
        $gui.Settings.AutoCheckMinutes = 0
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowAutoCheck -Gui $Gui } | Should -BeFalse
    }

    It 'does nothing before the first check, which the user starts' {
        $gui.Report = $null
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowAutoCheck -Gui $Gui } | Should -BeFalse
    }

    It 'does nothing while a check is running' {
        $gui.Worker = 'a check is already running'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowAutoCheck -Gui $Gui } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowCheck -Times 0 -Exactly
    }
}

Describe 'Invoke-WindowCheck -Background' -Skip:(-not $isSta) {
    It 'starts the check without the progress panel and leaves the results in place' {
        $gui = New-TestWindow
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Disk Critical)
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui -Background }

            $gui.Background | Should -BeTrue
            $gui.Worker | Should -BeOfType [powershell]
            $gui.Controls.RunPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.RunButton.IsEnabled | Should -BeFalse
            $gui.Controls.RunButton.Content | Should -Be 'Updating ...'
            $gui.Controls.StatusText.Text | Should -Match '^Checking again in the background'
            @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be 'Disk (C:)'
        }
        finally {
            $gui.Timer.Stop()
            $gui.Worker.Stop()
            $gui.Worker.Dispose()
        }
    }

    It 'marks a check the user starts as not automatic' {
        $gui = New-TestWindow
        $gui.Background = $true
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }
            $gui.Background | Should -BeFalse
            $gui.Controls.RunPanel.Visibility | Should -Be 'Visible'
        }
        finally {
            $gui.Timer.Stop()
            $gui.Worker.Stop()
            $gui.Worker.Dispose()
        }
    }
}

Describe 'Show-WindowReport -KeepPage' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    BeforeEach {
        $gui = New-TestWindow
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Disk Critical)
    }

    It 'replaces the content of the page that is open instead of going to the Overview' {
        $gui.Controls.CategoryList.SelectedIndex = 3
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui }
        $gui.Page | Should -Be 'Hardware'

        Show-TestReport -Gui $gui -Report (New-TestStateReport -Disk Critical -Memory Warning) -KeepPage

        $gui.Page | Should -Be 'Hardware'
        $gui.Controls.PageTitle.Text | Should -Be 'Hardware'
        $gui.Controls.CategoryList.SelectedItem.Name | Should -Be 'Hardware'
        $gui.Controls.PageSubtitle.Text | Should -Be '1 Critical, 1 Warning, 1 OK'
        $gui.Loading | Should -BeFalse
    }

    It 'updates the counts and the badges of the page list' {
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Disk Critical -Memory Warning) -KeepPage

        $gui.Controls.WarningCount.Text | Should -Be '1'
        (@($gui.Controls.CategoryList.ItemsSource) | Where-Object Name -eq 'Hardware').Badge | Should -Be '2'
    }

    It 'keeps the search text and the status filter' {
        $gui.Controls.SearchBox.Text = 'disk'
        $gui.Controls.StatusFilter.SelectedIndex = 2
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Disk Critical -Memory Warning) -KeepPage

        $gui.Controls.SearchBox.Text | Should -Be 'disk'
        $gui.Controls.StatusFilter.SelectedIndex | Should -Be 2
        $gui.Controls.PageTitle.Text | Should -Be 'Search results'
    }

    It 'says in the status bar that the results were updated by themselves' {
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Time '2026-01-15 10:35:00') -KeepPage
        $gui.Controls.StatusText.Text | Should -Match '^Updated automatically: 5 results, checked 2026-01-15 10:35:00\.'
    }

    It 'leaves the Live monitor open and only updates the page list' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Live monitor' }
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Disk Critical -Memory Warning) -KeepPage

        $gui.Page | Should -Be 'Live monitor'
        $gui.Controls.MonitorPanel.Visibility | Should -Be 'Visible'
        $gui.Controls.CategoryList.SelectedItem.Name | Should -Be 'Live monitor'
    }

    It 'leaves the settings open' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings' }
        Show-TestReport -Gui $gui -Report (New-TestStateReport) -KeepPage

        $gui.Controls.SettingsPanel.Visibility | Should -Be 'Visible'
        $gui.Controls.CategoryList.SelectedIndex | Should -Be -1
    }

    It 'goes to the Overview when the category that was open is gone' {
        $gui.Page = 'Printers'
        Show-TestReport -Gui $gui -Report (New-TestStateReport) -KeepPage
        $gui.Page | Should -Be 'Overview'
    }

    It 'still opens the Overview without a filter for a report the user asked for' {
        $gui.Controls.SearchBox.Text = 'disk'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Hardware' }
        Show-TestReport -Gui $gui -Report (New-TestStateReport)

        $gui.Page | Should -Be 'Overview'
        $gui.Controls.SearchBox.Text | Should -Be ''
        $gui.Controls.CategoryList.SelectedIndex | Should -Be 0
    }
}

Describe 'Notices about new problems' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }

        # The changes between two reports, as the automatic check finds them.
        function Get-TestChange {
            param($Before, $After)
            InModuleScope HelpdeskToolkit -Parameters @{ Before = $Before; After = $After } { @(Compare-PCHealthReport -Reference $Before -Difference $After) }
        }
    }

    BeforeEach {
        $gui = New-TestWindow
        $before = New-TestStateReport -Uptime Warning
        $after = New-TestStateReport -Uptime Warning -Memory Warning -Disk Critical
        Show-TestReport -Gui $gui -Report $after
    }

    It 'exposes the control <_>' -ForEach @('NoticeBorder', 'NoticeTitle', 'NoticeItems', 'NoticeCloseButton') {
        $gui.Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'starts without notices' {
        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Collapsed'
    }

    It 'announces every problem that is new, with its status, place and value' {
        $added = @(InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $before $after) } { Add-WindowNotice -Gui $Gui -Change $Change })

        $added.Count | Should -Be 2
        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Visible'
        $gui.Controls.NoticeTitle.Text | Should -Match '^The automatic check found 2 new problems, the last one at \d\d:\d\d\. Click one to see the result\.$'
        $rows = @($gui.Controls.NoticeItems.ItemsSource)
        $rows.Text | Should -Contain '[Critical] Hardware / Disk (C:): 3 % free'
        $rows.Text | Should -Contain '[Warning] Hardware / Memory usage: 91 % (14.5 GB of 16 GB used)'
        $rows[0].Link | Should -Be 'Show'
    }

    It 'words the title for a single problem' {
        $single = New-TestStateReport -Uptime Warning -Memory Warning
        Show-TestReport -Gui $gui -Report $single
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $before $single) } { Add-WindowNotice -Gui $Gui -Change $Change } | Out-Null

        $gui.Controls.NoticeTitle.Text | Should -Match '^The automatic check found a new problem at \d\d:\d\d\. Click it to see the result\.$'
    }

    It 'announces nothing for problems that got better or were there before' {
        $added = @(InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $after $before) } { Add-WindowNotice -Gui $Gui -Change $Change })
        $added.Count | Should -Be 0
        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Collapsed'
    }

    It 'shows the newest notice first and keeps a problem only once' {
        $memoryOnly = New-TestStateReport -Uptime Warning -Memory Warning
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $before $memoryOnly) } { Add-WindowNotice -Gui $Gui -Change $Change } | Out-Null
        # The next check: the disk is new, the memory got worse.
        $worse = New-TestStateReport -Uptime Warning -Memory Critical -Disk Critical
        Show-TestReport -Gui $gui -Report $worse
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $memoryOnly $worse) } { Add-WindowNotice -Gui $Gui -Change $Change } | Out-Null

        $rows = @($gui.Controls.NoticeItems.ItemsSource)
        $rows.Count | Should -Be 2
        @($rows | Where-Object Check -eq 'Memory usage').Text | Should -Match '^\[Critical\]'
    }

    It 'drops a notice whose problem is gone in the report on the screen' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $before $after) } { Add-WindowNotice -Gui $Gui -Change $Change } | Out-Null
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical) -KeepPage
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowNotice -Gui $Gui }

        @($gui.Controls.NoticeItems.ItemsSource).Check | Should -Be 'Disk (C:)'
    }

    It 'hides the bar when the notices are dismissed' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $before $after) } { Add-WindowNotice -Gui $Gui -Change $Change } | Out-Null
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowNotice -Gui $Gui -Clear }

        $gui.Notices.Count | Should -Be 0
        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Collapsed'
    }

    It 'shows the notices in the language of the window' {
        try {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Change = (Get-TestChange $before $after) } { Add-WindowNotice -Gui $Gui -Change $Change } | Out-Null

            @($gui.Controls.NoticeItems.ItemsSource).Text | Should -Contain '[Upozorenje] Hardver / Zauzeće memorije: 91 % (zauzeto 14.5 GB od 16 GB)'
            @($gui.Controls.NoticeItems.ItemsSource)[0].Link | Should -Be 'Prikaži'
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
        }
    }
}

Describe 'Show-WindowResult' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    BeforeEach {
        $gui = New-TestWindow
        Show-TestReport -Gui $gui -Report (New-TestStateReport -Memory Warning -Disk Critical)
    }

    It 'opens the page of the category and frames the card of the result' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'Memory usage' } | Should -BeTrue

        $gui.Page | Should -Be 'Hardware'
        $gui.Controls.CategoryList.SelectedItem.Name | Should -Be 'Hardware'
        $cards = @($gui.Controls.ResultItems.ItemsSource)
        ($cards | Where-Object SourceCheck -eq 'Memory usage').Highlight | Should -Be 'Yes'
        @($cards | Where-Object Highlight -eq 'Yes').Count | Should -Be 1
    }

    It 'removes search and filter first, so the result is certainly on the page' {
        $gui.Controls.SearchBox.Text = 'proxy'
        $gui.Controls.StatusFilter.SelectedIndex = 4
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'Disk (C:)' } | Should -BeTrue

        $gui.Controls.SearchBox.Text | Should -Be ''
        $gui.Controls.StatusFilter.SelectedIndex | Should -Be 0
        @($gui.Controls.ResultItems.ItemsSource).SourceCheck | Should -Contain 'Disk (C:)'
    }

    It 'leaves the settings and the Live monitor for the page of the result' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'Disk (C:)' } | Should -BeTrue

        $gui.Controls.SettingsPanel.Visibility | Should -Be 'Collapsed'
        $gui.Controls.ResultScroll.Visibility | Should -Be 'Visible'
    }

    It 'frames the card only once: the next time the page is drawn it is an ordinary card again' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'Memory usage' } | Out-Null
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Hardware' }

        @(@($gui.Controls.ResultItems.ItemsSource) | Where-Object Highlight -eq 'Yes').Count | Should -Be 0
    }

    It 'returns $false for a result the report does not have' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'No such check' } | Should -BeFalse
    }

    It 'returns $false before the first check' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = (New-TestWindow) } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'Disk (C:)' } | Should -BeFalse
    }
}

Describe 'Open-WindowNotice' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    It 'opens the result of the newest notice' {
        Mock -ModuleName HelpdeskToolkit Show-WindowResult { $true }
        $gui = New-TestWindow
        $gui.Notices['Hardware|Disk (C:)'] = [PSCustomObject]@{ Category = 'Hardware'; Check = 'Disk (C:)'; Status = 'Critical'; Value = '3 % free'; FoundAt = Get-Date }
        $gui.Notices['System|Uptime'] = [PSCustomObject]@{ Category = 'System'; Check = 'Uptime'; Status = 'Warning'; Value = '9 d'; FoundAt = Get-Date }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowNotice -Gui $Gui } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowResult -Times 1 -Exactly -ParameterFilter { $Category -eq 'System' -and $Check -eq 'Uptime' }
    }

    It 'only brings the window to the front when there is no notice' {
        Mock -ModuleName HelpdeskToolkit Show-WindowResult { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = (New-TestWindow) } { Open-WindowNotice -Gui $Gui } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowResult -Times 0 -Exactly
    }
}

Describe 'Receive-WindowCheck: automatic check' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        # The window of the tests is never in front, so every new problem would raise a
        # Windows notification.
        Mock -ModuleName HelpdeskToolkit Show-WindowToast { }
        $history = Join-Path -Path $TestDrive -ChildPath 'AppData\History'
    }

    BeforeEach {
        $gui = New-TestWindow
        if (Test-Path -LiteralPath $history) {
            Remove-Item -LiteralPath $history -Recurse -Force
        }
        # The first check, started by the user
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Time '2026-01-15 10:30:00')
    }

    It 'remembers when a check ended, so the automatic check can count from there' {
        $gui.LastCheckAt | Should -BeOfType [datetime]
        ((Get-Date) - $gui.LastCheckAt).TotalSeconds | Should -BeLessThan 30
    }

    It 'adds the check of the user to the history' {
        @(Get-ChildItem -LiteralPath $history).Count | Should -Be 1
    }

    It 'replaces the results without adding the automatic check to the history' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:35:00') -Background

        $gui.Report.GeneratedAt | Should -Be '2026-01-15 10:35:00'
        $gui.Controls.CriticalCount.Text | Should -Be '1'
        @(Get-ChildItem -LiteralPath $history).Count | Should -Be 1
        $gui.Background | Should -BeFalse
        $gui.Controls.RunButton.IsEnabled | Should -BeTrue
        $gui.Controls.RunButton.Content | Should -Be 'Run check'
    }

    It 'announces a problem that is new at the top of the window' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:35:00') -Background

        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Visible'
        @($gui.Controls.NoticeItems.ItemsSource).Check | Should -Be 'Disk (C:)'
    }

    It 'raises a Windows notification while the window is not in front' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Memory Warning -Time '2026-01-15 10:35:00') -Background

        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowToast -Times 1 -Exactly -ParameterFilter {
            $Title -eq 'HelpdeskToolkit: 2 new problems' -and $Text -match 'Disk \(C:\): 3 % free' -and $Text -match 'Memory usage: 91 %'
        }
    }

    It 'words the notification for a single problem' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:35:00') -Background
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowToast -Times 1 -Exactly -ParameterFilter { $Title -eq 'HelpdeskToolkit: a new problem' }
    }

    It 'announces nothing when the automatic check finds the same problems as before' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Time '2026-01-15 10:35:00') -Background

        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Collapsed'
        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowToast -Times 0 -Exactly
    }

    It 'does not announce a problem a second time while it lasts' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:35:00') -Background
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:40:00') -Background

        Should -Invoke -ModuleName HelpdeskToolkit Show-WindowToast -Times 1 -Exactly
        # The notice stays until it is dismissed or the problem is gone.
        @($gui.Controls.NoticeItems.ItemsSource).Check | Should -Be 'Disk (C:)'
    }

    It 'takes a notice away when the next automatic check finds the problem gone' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:35:00') -Background
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Time '2026-01-15 10:40:00') -Background

        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Collapsed'
    }

    It 'keeps the page the user is reading' {
        $gui.Controls.CategoryList.SelectedIndex = 2
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui }
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:35:00') -Background

        $gui.Page | Should -Be 'System'
        $gui.Controls.PageTitle.Text | Should -Be 'System'
    }

    It 'keeps comparing with the check before the one of the user, not with the last automatic one' {
        # A second check of the user, so there is a previous report to compare with.
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Time '2026-01-15 11:00:00')
        $gui.PreviousReport.GeneratedAt | Should -Be '2026-01-15 10:30:00'

        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Disk Critical -Time '2026-01-15 11:05:00') -Background
        $gui.PreviousReport.GeneratedAt | Should -Be '2026-01-15 10:30:00'
        $gui.Controls.ChangesBorder.Visibility | Should -Be 'Visible'
    }

    It 'removes the notices when the user starts a check, which is a fresh look at everything' {
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:35:00') -Background
        Complete-TestCheck -Gui $gui -Report (New-TestStateReport -Uptime Warning -Disk Critical -Time '2026-01-15 10:40:00')

        $gui.Notices.Count | Should -Be 0
        $gui.Controls.NoticeBorder.Visibility | Should -Be 'Collapsed'
    }

    It 'reports an automatic check that failed and leaves the results in place' {
        $gui.Worker = [powershell]::Create()
        [void]$gui.Worker.AddScript('Write-Error "WMI is not available"')
        $gui.Handle = $gui.Worker.BeginInvoke()
        [void]$gui.Handle.AsyncWaitHandle.WaitOne(10000)
        $gui.Background = $true
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

        $gui.Controls.StatusText.Text | Should -Be 'The check failed: WMI is not available'
        $gui.Report.GeneratedAt | Should -Be '2026-01-15 10:30:00'
        $gui.Background | Should -BeFalse
    }
}

Describe 'Get-AppSetting: automatic check' {
    BeforeAll {
        $appData = Join-Path -Path $TestDrive -ChildPath 'AppData'
        New-Item -Path $appData -ItemType Directory -Force | Out-Null
        $file = Join-Path -Path $appData -ChildPath 'settings.json'
    }

    AfterAll {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }

    It 'repeats the check every five minutes unless the user chose otherwise' {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).AutoCheckMinutes | Should -Be 5
    }

    It 'reads the chosen interval, also "Never"' {
        Set-Content -LiteralPath $file -Value '{ "AutoCheckMinutes": 0 }'
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).AutoCheckMinutes | Should -Be 0
        Set-Content -LiteralPath $file -Value '{ "AutoCheckMinutes": 30 }'
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).AutoCheckMinutes | Should -Be 30
    }

    It 'replaces an interval the window does not offer with the default' {
        Set-Content -LiteralPath $file -Value '{ "AutoCheckMinutes": 1 }'
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).AutoCheckMinutes | Should -Be 5
    }
}
