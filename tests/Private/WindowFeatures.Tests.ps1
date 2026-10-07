# Tests for the features of the window that go beyond showing a report: themes and
# language, score and changes, search and filter, buttons that open Windows, shortcuts,
# saving and copying, and the tools of the Live monitor. The window is created but
# never shown, so the tests run unattended.

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
        param([string]$Theme = 'Light')

        $gui = InModuleScope HelpdeskToolkit -Parameters @{ Theme = $Theme } { New-HealthCheckWindow -Theme $Theme }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.OutputFolder = Join-Path -Path $TestDrive -ChildPath 'Output'
        $gui
    }

    # Shows the test report in a new window and returns the window table.
    function Show-TestReport {
        param([object[]]$Result = $testResults, $Previous)

        $window = New-TestWindow
        $parameters = @{ Gui = $window; Report = (New-TestReport -Result $Result) }
        if ($Previous) {
            $parameters.Previous = $Previous
        }
        InModuleScope HelpdeskToolkit -Parameters @{ Parameters = $parameters } { Show-WindowReport @Parameters }
        $window
    }

    $testResults = @(
        New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d' -Description 'Time since start.'
        New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '20 programs' -Recommendation 'Disable some.'
        New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free' -Recommendation 'Free up space.'
        New-TestResult -Category 'Hardware' -Check 'Battery' -Status OK -Value '80 % (plugged in)'
        New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
        New-TestResult -Category 'Network' -Check 'Computer name' -Status Info -Value 'TEST-PC-01' -Recommendation 'Only an example.'
    )
}

Describe 'New-HealthCheckWindow: theme and language' -Skip:(-not $isSta) {
    It 'exposes the control <_> that the new features rely on' -ForEach @(
        'CopySummaryButton', 'FilterPanel', 'SearchBox', 'SearchHint', 'StatusFilter', 'ScoreCount', 'ScoreBorder'
        'ChangesBorder', 'ChangesTitle', 'ChangesItems', 'SettingsPanel', 'LanguageBox', 'ThemeBox', 'RestartButton'
        'ShortcutItems', 'AboutText', 'DataFolderText', 'OpenDataFolderButton'
        'MonitorPauseButton', 'MonitorIntervalBox', 'MonitorRecordButton', 'MonitorRecordMinutes', 'MonitorRecordText', 'MonitorAlerts'
        'MonitorDiskGraph', 'MonitorDiskLine', 'MonitorDiskArea', 'MonitorNetworkGraph', 'MonitorNetworkDownLine', 'MonitorNetworkUpLine', 'MonitorNetworkCaption'
        'MonitorProgramCard', 'MonitorProgramTitle', 'MonitorProgramDetails', 'MonitorProgramHint'
    ) {
        (New-TestWindow).Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'uses the light colors by default' {
        $gui = New-TestWindow
        $gui.Theme | Should -Be 'Light'
        [string]$gui.Window.Background.Color | Should -Be '#FFF3F5F8'
        [string]$gui.Window.FindResource('SurfaceBrush').Color | Should -Be '#FFFFFFFF'
    }

    It 'replaces the colors of the brushes for the dark theme' {
        $gui = New-TestWindow -Theme Dark
        $gui.Theme | Should -Be 'Dark'
        [string]$gui.Window.Background.Color | Should -Be '#FF0F141B'
        [string]$gui.Window.FindResource('SurfaceBrush').Color | Should -Be '#FF1A212B'
        [string]$gui.Window.FindResource('TextBrush').Color | Should -Be '#FFE6EBF2'
    }

    It 'keeps a brush that the dark theme does not list' {
        [string](New-TestWindow -Theme Dark).Window.FindResource('PrimaryBrush').Color | Should -Be '#FF3B7DDD'
    }

    It 'shows the texts of the layout in the chosen language' {
        try {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
            $gui = New-TestWindow

            $gui.Controls.RunButton.Content | Should -Be 'Pokreni provjeru'
            $gui.Controls.StatusText.Text | Should -Be 'Spremno. Klikni Pokreni provjeru da pregledaš ovo računalo.'
            $gui.Window.Title | Should -Be 'HelpdeskToolkit - provjera računala'
            @($gui.Controls.CategoryList.ItemsSource).Label | Should -Be @('Pregled', 'Praćenje uživo')
            $gui.Controls.SettingsButton.Content | Should -Be 'Postavke'
            # The names the code works with stay English.
            @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'Live monitor')
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
        }
    }

    It 'leaves the icons of the buttons alone when it translates' {
        try {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
            [int][char]([string](New-TestWindow).Controls.RunButton.Tag) | Should -Be 0xE768
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
        }
    }
}

Describe 'ConvertTo-WindowItem: status text, button and language' {
    It 'offers the place in Windows for a result that has a recommendation' {
        $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[2] } { ConvertTo-WindowItem -Result $Result }
        $item.ActionLabel | Should -Be 'Open Storage settings'
        $item.SourceCheck | Should -Be 'Disk (C:)'
        $item.SourceCategory | Should -Be 'Hardware'
    }

    It 'offers no button without a recommendation, even when the check has a place' {
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[4] } { ConvertTo-WindowItem -Result $Result }).ActionLabel | Should -Be ''
    }

    It 'offers no button for a check without a place, even when it has a recommendation' {
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[5] } { ConvertTo-WindowItem -Result $Result }).ActionLabel | Should -Be ''
    }

    It 'shows the status as text and keeps the original for the colors' {
        $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[1] } { ConvertTo-WindowItem -Result $Result }
        $item.Status | Should -Be 'Warning'
        $item.StatusText | Should -Be 'Warning'
    }

    Context 'in Croatian' {
        BeforeAll {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
            $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $testResults[2] } { ConvertTo-WindowItem -Result $Result -ShowCategory }
        }

        AfterAll {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
        }

        It 'translates the status, the category, the value and the labels' {
            $item.StatusText | Should -Be 'Kritično'
            $item.Category | Should -Be 'Hardver'
            $item.Value | Should -Be '2 % slobodno'
            $item.RecommendationLabel | Should -Be 'PREPORUČENO RJEŠENJE'
            $item.ActionLabel | Should -Be 'Otvori postavke pohrane'
        }

        It 'keeps the original status and names, which the colors and the button depend on' {
            $item.Status | Should -Be 'Critical'
            $item.SourceCheck | Should -Be 'Disk (C:)'
            $item.SourceCategory | Should -Be 'Hardware'
        }

        It 'translates the first part of a name and keeps the drive letter or device name' {
            $item.Check | Should -Be 'Disk (C:)'
            $drive = New-TestResult -Category 'Hardware' -Check 'Drive details: Contoso SSD' -Status OK
            (InModuleScope HelpdeskToolkit -Parameters @{ Result = $drive } { ConvertTo-WindowItem -Result $Result }).Check | Should -Be 'Detalji pogona: Contoso SSD'
        }

        It 'translates the caption of the list that opens on a click' {
            $long = New-TestResult -Check 'Scheduled tasks' -Details 'A', 'B', 'C'
            (InModuleScope HelpdeskToolkit -Parameters @{ Result = $long } { ConvertTo-WindowItem -Result $Result }).MoreHeader | Should -Be 'Prikaži još 3'
        }
    }
}

Describe 'Show-WindowReport: score and changes' -Skip:(-not $isSta) {
    It 'shows the score in the color of its level: <Level> for <Critical> critical results and <Warning> warnings' -ForEach @(
        @{ Critical = 0; Warning = 1; Score = '96'; Level = 'OkBrush' }
        @{ Critical = 1; Warning = 2; Score = '77'; Level = 'WarningBrush' }
        @{ Critical = 3; Warning = 0; Score = '55'; Level = 'CriticalBrush' }
    ) {
        $results = @(
            1..$Critical | Where-Object { $Critical -gt 0 } | ForEach-Object { New-TestResult -Status Critical }
            1..$Warning | Where-Object { $Warning -gt 0 } | ForEach-Object { New-TestResult -Status Warning }
            New-TestResult -Status OK
        )
        $gui = Show-TestReport -Result $results

        $gui.Controls.ScoreCount.Text | Should -Be $Score
        $gui.Controls.ScoreCount.Foreground | Should -Be $gui.Window.FindResource($Level)
        $gui.Controls.ScoreBorder.BorderBrush | Should -Be $gui.Window.FindResource($Level)
    }

    It 'shows no score for a report of an older version that has none' {
        $gui = New-TestWindow
        $old = New-TestReport -Result $testResults | Select-Object -Property * -ExcludeProperty Score
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $old } { Show-WindowReport -Gui $Gui -Report $Report }
        $gui.Controls.ScoreCount.Text | Should -Be '-'
    }

    It 'enables the buttons that need a report' {
        $gui = Show-TestReport
        $gui.Controls.CopySummaryButton.IsEnabled | Should -BeTrue
        $gui.Controls.OpenReportButton.IsEnabled | Should -BeTrue
    }

    It 'hides the changes when there is no earlier report' {
        (Show-TestReport).Controls.ChangesBorder.Visibility | Should -Be 'Collapsed'
    }

    Context 'with the report of the previous check' {
        BeforeAll {
            $previous = New-TestReport -Result @(
                New-TestResult -Category 'System' -Check 'Uptime' -Status Warning -Value '9 d'
                New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '20 programs'
                New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Warning -Value '12 % free'
                New-TestResult -Category 'Hardware' -Check 'Battery' -Status OK -Value '80 %'
            )
            $previous.GeneratedAt = '2026-01-08 09:00:00'
            $gui = Show-TestReport -Previous $previous
            $changes = @($gui.Controls.ChangesItems.ItemsSource)
        }

        It 'says since when and how much changed' {
            $gui.Controls.ChangesBorder.Visibility | Should -Be 'Visible'
            $gui.Controls.ChangesTitle.Text | Should -Be 'Since the last check (2026-01-08 09:00:00): 1 new or worse, 1 resolved or better'
        }

        It 'lists every change with its check and the two statuses' {
            $changes.Change | Should -Be @('Worse', 'Resolved')
            $changes[0].Text | Should -Be 'Hardware / Disk (C:)'
            $changes[0].Transition | Should -Be 'Warning -> Critical'
            $changes[1].Text | Should -Be 'System / Uptime'
        }

        It 'marks what got worse and what got better, for the color of the badge' {
            $changes.Level | Should -Be @('Worse', 'Better')
        }

        It 'remembers the previous report' {
            $gui.PreviousReport.GeneratedAt | Should -Be '2026-01-08 09:00:00'
        }

        It 'says so when the problems are the same as last time' {
            $same = New-TestReport -Result $testResults
            $same.GeneratedAt = '2026-01-08 09:00:00'
            $unchanged = Show-TestReport -Previous $same

            $unchanged.Controls.ChangesTitle.Text | Should -Be 'No change in the problems since the last check (2026-01-08 09:00:00).'
            @($unchanged.Controls.ChangesItems.ItemsSource).Count | Should -Be 0
        }
    }

    It 'starts a new report without the search text and the filter of the old one' {
        $gui = Show-TestReport
        $gui.Controls.SearchBox.Text = 'disk'
        $gui.Controls.StatusFilter.SelectedIndex = 2
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $testResults) } { Show-WindowReport -Gui $Gui -Report $Report }

        $gui.Controls.SearchBox.Text | Should -Be ''
        $gui.Controls.StatusFilter.SelectedIndex | Should -Be 0
        $gui.Loading | Should -BeFalse
    }
}

Describe 'Show-WindowPage: search, filter and settings' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        $gui = Show-TestReport

        # Selects an entry of the status filter by its tag.
        function Set-TestFilter {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only changes a control of the test window.')]
            param([string]$Tag)
            $gui.Controls.StatusFilter.SelectedItem = $gui.Controls.StatusFilter.Items | Where-Object { [string]$_.Tag -eq $Tag }
        }
    }

    BeforeEach {
        $gui.Controls.SearchBox.Text = ''
        Set-TestFilter -Tag ''
    }

    It 'shows the search field and the filter on pages with results only' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }
        $gui.Controls.FilterPanel.Visibility | Should -Be 'Visible'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings' }
        $gui.Controls.FilterPanel.Visibility | Should -Be 'Collapsed'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = (New-TestWindow) } { Show-WindowPage -Gui $Gui -Name 'Overview' }
    }

    It 'hides them before the first check' {
        $empty = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $empty } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        $empty.Controls.FilterPanel.Visibility | Should -Be 'Collapsed'
    }

    It 'searches all results of the report, whatever page is open' {
        $gui.Controls.SearchBox.Text = 'program'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Network' }

        $gui.Controls.PageTitle.Text | Should -Be 'Search results'
        $gui.Controls.PageSubtitle.Text | Should -Be '1 of 6 results contain "program".'
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be 'Startup programs'
        @($gui.Controls.ResultItems.ItemsSource).Category | Should -Be 'System'
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Collapsed'
    }

    It 'finds a text in the value, the description and the recommendation, in any case' {
        foreach ($search in 'TEST-PC', 'time SINCE', 'free UP') {
            $gui.Controls.SearchBox.Text = $search
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
            @($gui.Controls.ResultItems.ItemsSource).Count | Should -Be 1 -Because "'$search' occurs in exactly one result"
        }
    }

    It 'says so when nothing is found' {
        $gui.Controls.SearchBox.Text = 'does not occur anywhere'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }

        @($gui.Controls.ResultItems.ItemsSource).Count | Should -Be 0
        $gui.Controls.EmptyText.Text | Should -Be 'Nothing found.'
        $gui.Controls.EmptyText.Visibility | Should -Be 'Visible'
    }

    It 'hides the hint inside the search field while it holds a text' {
        $gui.Controls.SearchBox.Text = 'disk'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        $gui.Controls.SearchHint.Visibility | Should -Be 'Collapsed'

        $gui.Controls.SearchBox.Text = ''
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        $gui.Controls.SearchHint.Visibility | Should -Be 'Visible'
    }

    It 'shows only the results with the chosen status on a category page' {
        Set-TestFilter -Tag 'OK'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Hardware' }

        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be 'Battery'
        # The subtitle and the chips still count the whole category.
        $gui.Controls.PageSubtitle.Text | Should -Be '1 of 2 checks need attention.'
        $gui.Controls.ChipCriticalCount.Text | Should -Be '1'
        $gui.Controls.ChipOKCount.Text | Should -Be '1'
    }

    It 'shows every result with the chosen status on the Overview, not only the problems' {
        Set-TestFilter -Tag 'Info'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }

        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be @('Proxy', 'Computer name')
        $gui.Controls.PageSubtitle.Text | Should -Be '2 of 6 results have the chosen status.'
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Visible'
    }

    It 'shows critical results and warnings for "Problems only"' {
        Set-TestFilter -Tag 'Problems'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be 'Startup programs'
    }

    It 'combines the search with the status filter' {
        $gui.Controls.SearchBox.Text = 'e'
        Set-TestFilter -Tag 'Critical'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be 'Disk (C:)'
    }

    It 'says so when no result of the page has the chosen status' {
        Set-TestFilter -Tag 'Critical'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Network' }
        $gui.Controls.EmptyText.Text | Should -Be 'No result has the chosen status.'
    }

    It 'shows the settings instead of the results on the Settings page' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings' }

        $gui.Controls.PageTitle.Text | Should -Be 'Settings'
        $gui.Controls.SettingsPanel.Visibility | Should -Be 'Visible'
        $gui.Controls.ResultScroll.Visibility | Should -Be 'Collapsed'
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Collapsed'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'System' }
        $gui.Controls.SettingsPanel.Visibility | Should -Be 'Collapsed'
        # The page of a category has a panel of its own.
        $gui.Controls.CategoryPanel.Visibility | Should -Be 'Visible'
    }
}

Describe 'Show-WindowSetting' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        $gui.Settings = @{ Language = 'hr'; Theme = 'Dark'; MonitorIntervalSeconds = 2; AutoCheckMinutes = 30; StartupElevation = 'Never' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowSetting -Gui $Gui }
    }

    It 'selects the language and the theme that are in use' {
        $gui.Controls.LanguageBox.SelectedItem.Tag | Should -Be 'hr'
        $gui.Controls.ThemeBox.SelectedItem.Tag | Should -Be 'Dark'
    }

    It 'selects how often the check is repeated' {
        $gui.Controls.AutoCheckBox.SelectedItem.Tag | Should -Be '30'
    }

    It 'selects what happens when the application starts' {
        $gui.Controls.StartupBox.SelectedItem.Tag | Should -Be 'Never'
    }

    It 'does not leave the window in the "being filled" state' {
        $gui.Loading | Should -BeFalse
    }

    It 'lists the keyboard shortcuts' {
        @($gui.Controls.ShortcutItems.ItemsSource).Name | Should -Contain 'F5'
        @($gui.Controls.ShortcutItems.ItemsSource).Name | Should -Contain 'Ctrl+Shift+C'
    }

    It 'shows the version and the folder of the application' {
        $gui.Controls.AboutText.Text | Should -Match '^HelpdeskToolkit \d+\.\d+\.\d+  \|  PowerShell \d'
        $gui.Controls.DataFolderText.Text | Should -Be (Join-Path -Path $TestDrive -ChildPath 'AppData')
    }
}

Describe 'Invoke-WindowShortcut' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    BeforeEach {
        $gui = Show-TestReport
        # Counts the clicks a shortcut makes on the buttons.
        $script:clicks = @{}
        foreach ($name in 'RunButton', 'SaveAsButton', 'OpenReportButton', 'CopySummaryButton') {
            $gui.Controls[$name].Tag = $name
            $gui.Controls[$name].Add_Click({ $script:clicks[$this.Tag] = [int]$script:clicks[$this.Tag] + 1 })
        }
    }

    It 'clicks <Button> for <Description>' -ForEach @(
        @{ Key = 'F5'; Control = $false; Shift = $false; Button = 'RunButton'; Description = 'F5' }
        @{ Key = 'S'; Control = $true; Shift = $false; Button = 'SaveAsButton'; Description = 'Ctrl+S' }
        @{ Key = 'O'; Control = $true; Shift = $false; Button = 'OpenReportButton'; Description = 'Ctrl+O' }
        @{ Key = 'C'; Control = $true; Shift = $true; Button = 'CopySummaryButton'; Description = 'Ctrl+Shift+C' }
    ) {
        $handled = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Key = $Key; Control = $Control; Shift = $Shift } {
            Invoke-WindowShortcut -Gui $Gui -Key $Key -Control:$Control -Shift:$Shift
        }
        $handled | Should -BeTrue
        $clicks[$Button] | Should -Be 1
    }

    It 'does nothing while the button of the shortcut is disabled' {
        $gui.Controls.SaveAsButton.IsEnabled = $false
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'S' -Control } | Should -BeTrue
        $clicks['SaveAsButton'] | Should -BeNullOrEmpty
    }

    It 'leaves plain Ctrl+C to Windows, which copies the selected text' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'C' -Control } | Should -BeFalse
        $clicks['CopySummaryButton'] | Should -BeNullOrEmpty
    }

    It 'opens the Live monitor with Ctrl+M' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'M' -Control } | Should -BeTrue
        $gui.Controls.CategoryList.SelectedItem.Name | Should -Be 'Live monitor'
    }

    It 'clears the search with Esc, and leaves Esc alone when there is nothing to clear' {
        $gui.Controls.SearchBox.Text = 'disk'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Escape' } | Should -BeTrue
        $gui.Controls.SearchBox.Text | Should -Be ''
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Escape' } | Should -BeFalse
    }

    It 'goes to the Overview for Ctrl+F when the open page has no search field' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Settings' }
        $gui.Controls.FilterPanel.Visibility | Should -Be 'Collapsed'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'F' -Control } | Should -BeTrue
        $gui.Controls.CategoryList.SelectedItem.Name | Should -Be 'Overview'
    }

    It 'returns $false for a key that is no shortcut' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'A' } | Should -BeFalse
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Q' -Control } | Should -BeFalse
    }
}

Describe 'Export-WindowReport' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Export-HealthReportHtml { $Path }
        Mock -ModuleName HelpdeskToolkit Export-HealthReportJson { $Path }
        Mock -ModuleName HelpdeskToolkit Export-HealthReportCsv { $Path }
        Mock -ModuleName HelpdeskToolkit Export-HealthReportPdf { $Path }
        $gui = Show-TestReport
        $folder = Join-Path -Path $TestDrive -ChildPath 'Exports\New'
    }

    It 'chooses <Command> for a file that ends in <Extension>' -ForEach @(
        @{ Extension = '.html'; Command = 'Export-HealthReportHtml' }
        @{ Extension = '.JSON'; Command = 'Export-HealthReportJson' }
        @{ Extension = '.csv'; Command = 'Export-HealthReportCsv' }
        @{ Extension = '.pdf'; Command = 'Export-HealthReportPdf' }
        @{ Extension = '.txt'; Command = 'Export-HealthReportHtml' }
    ) {
        $path = Join-Path -Path $folder -ChildPath "report$Extension"
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Path = $path } { Export-WindowReport -Gui $Gui -Path $Path } | Should -Be $path
        Should -Invoke -ModuleName HelpdeskToolkit $Command -Times 1 -Exactly -ParameterFilter { $Path -like "*report$Extension" }
    }

    It 'creates the folder and reports where the file is' {
        $folder | Should -Exist
        $gui.Controls.StatusText.Text | Should -Match '^Report saved: .+report'
    }

    It 'reports a failure in the status bar and returns nothing' {
        Mock -ModuleName HelpdeskToolkit Export-HealthReportPdf { throw 'No browser found' }
        $path = Join-Path -Path $folder -ChildPath 'failed.pdf'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Path = $path } { Export-WindowReport -Gui $Gui -Path $Path } | Should -BeNullOrEmpty
        $gui.Controls.StatusText.Text | Should -Be 'The report could not be saved: No browser found'
    }
}

Describe 'Copy-WindowSummary' -Skip:(-not $isSta) {
    It 'puts the text summary on the clipboard and says so' {
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { }
        $gui = Show-TestReport
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Copy-WindowSummary -Gui $Gui } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 1 -Exactly -ParameterFilter { $Value -match 'PC Health Check - TEST-PC-01' -and $Value -match 'Disk \(C:\)' }
        $gui.Controls.StatusText.Text | Should -Match '^The summary was copied'
    }

    It 'reports it when another program holds the clipboard' {
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { throw 'The clipboard is in use' }
        $gui = Show-TestReport
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Copy-WindowSummary -Gui $Gui } | Should -BeFalse
        $gui.Controls.StatusText.Text | Should -Be 'The summary could not be copied: The clipboard is in use'
    }

    It 'does nothing before the first check' {
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = (New-TestWindow) } { Copy-WindowSummary -Gui $Gui } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 0 -Exactly
    }
}

Describe 'Receive-WindowCheck: history' -Skip:(-not $isSta) {
    BeforeAll {
        # Lets the window receive a finished check whose single result has the given status.
        function Complete-TestCheck {
            param($Gui, [string]$Status, [string]$Time)

            $Gui.Worker = [powershell]::Create()
            [void]$Gui.Worker.AddScript(@"
[PSCustomObject]@{
    PSTypeName = 'HelpdeskToolkit.HealthReport'
    ToolVersion = '9.9.9'; ComputerName = 'HISTORY-PC'; GeneratedAt = '$Time'
    DurationSeconds = 1.5; IsElevated = `$true; EventLogDays = 7; Score = 100
    Summary = @{ OK = 0; Warning = 0; Critical = 0; Info = 0 }
    Results = @([PSCustomObject]@{ Category = 'System'; Check = 'Uptime'; Description = ''; Status = '$Status'; Value = '1 d'; Details = @(); Allowed = ''; Typical = ''; Recommendation = '' })
}
"@)
            $Gui.Handle = $Gui.Worker.BeginInvoke()
            [void]$Gui.Handle.AsyncWaitHandle.WaitOne(10000)
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui } { Receive-WindowCheck -Gui $Gui }
        }

        $gui = New-TestWindow
        Complete-TestCheck -Gui $gui -Status 'OK' -Time '2026-01-08 09:00:00'
    }

    It 'adds the finished report to the history of the application' {
        Join-Path -Path $TestDrive -ChildPath 'AppData\History\PCHealth_HISTORY-PC_20260108-090000.json' | Should -Exist
    }

    It 'shows no changes after the first check of a computer' {
        $gui.Controls.ChangesBorder.Visibility | Should -Be 'Collapsed'
    }

    It 'compares the next check with the one before' {
        Complete-TestCheck -Gui $gui -Status 'Warning' -Time '2026-01-15 10:30:00'

        $gui.Controls.ChangesBorder.Visibility | Should -Be 'Visible'
        $gui.Controls.ChangesTitle.Text | Should -Be 'Since the last check (2026-01-08 09:00:00): 1 new or worse, 0 resolved or better'
        @($gui.Controls.ChangesItems.ItemsSource).Change | Should -Be 'New problem'
    }
}

Describe 'Invoke-AppRestart' -Skip:(-not $isSta) {
    It 'starts the application again without asking for administrator rights' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = (New-TestWindow) } { Invoke-AppRestart -Gui $Gui } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -like '*\WindowsPowerShell\v1.0\powershell.exe' -and $WindowStyle -eq 'Hidden' -and -not $Verb
        }
    }

    It 'tells the new copy to run the check at once, so it neither asks nor waits' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = (New-TestWindow) } { Invoke-AppRestart -Gui $Gui } | Out-Null

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter { ($ArgumentList -join ' ') -match ' -RunCheck\b' }
    }

    It 'keeps the window open and says why when the new copy cannot be started' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'Access is denied' }
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-AppRestart -Gui $Gui } | Should -BeFalse
        $gui.Controls.StatusText.Text | Should -Be 'The application could not be restarted: Access is denied'
    }
}
