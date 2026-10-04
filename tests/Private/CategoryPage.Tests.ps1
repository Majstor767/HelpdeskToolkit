# Tests for the page of a category: the count per status as chips that filter, the
# problems as wide cards with their fix next to them, and everything else as tiles in
# three columns that open on a click.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $statuses = 'Critical', 'Warning', 'OK', 'Info'
    # The dot between the name of a group and its count
    $dot = [char]0x00B7

    # The order in which the checks ran is deliberately not the order on the page.
    $testResults = @(
        New-TestResult -Category 'Hardware' -Check 'CPU load' -Status OK -Value '12 %' -Description 'How busy the processor is.'
        New-TestResult -Category 'Hardware' -Check 'Top memory consumers' -Status Info -Value 'browser (3 GB)'
        New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status Warning -Value '91 %' -Recommendation 'Close programs.'
        New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '3 % free' -Recommendation 'Free up space.'
        New-TestResult -Category 'Hardware' -Check 'Disk (D:)' -Status OK -Value '60 % free'
        New-TestResult -Category 'Hardware' -Check 'Drive health' -Status Warning -Value 'Warning' -Recommendation 'Back up the data.'
        New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
        New-TestResult -Category 'Network' -Check 'DNS resolution' -Status OK -Value 'test.example resolved'
    )

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param([object[]]$Result = $testResults)

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $Result) } { Show-WindowReport -Gui $Gui -Report $Report }
        $gui
    }

    function Show-TestPage {
        param($Gui, [string]$Name, [switch]$KeepScroll)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui; Name = $Name; KeepScroll = [bool]$KeepScroll } { Show-WindowPage -Gui $Gui -Name $Name -KeepScroll:$KeepScroll }
    }

    function Set-TestFilter {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only selects an entry of a list in memory.')]
        param($Gui, [string]$Tag)
        $Gui.Controls.StatusFilter.SelectedItem = $Gui.Controls.StatusFilter.Items | Where-Object { [string]$_.Tag -eq $Tag }
    }

    # The wide cards at the top of the page.
    function Get-TestProblem {
        param($Gui)
        , @($Gui.Controls.ProblemItems.ItemsSource)
    }

    # The tiles of one column, or of all three in the order they are read: row by row.
    function Get-TestTile {
        param($Gui, [int]$Column = 0)

        if ($Column -gt 0) {
            return , @($Gui.Controls["TileColumn$Column"].ItemsSource)
        }
        $lists = 1..3 | ForEach-Object { , @($Gui.Controls["TileColumn$_"].ItemsSource) }
        $rows = ($lists | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
        , @(
            for ($row = 0; $row -lt $rows; $row++) {
                foreach ($list in $lists) {
                    if ($row -lt $list.Count) { $list[$row] }
                }
            }
        )
    }
}

Describe 'The page of a category' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    Context 'the layout' {
        BeforeAll {
            $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        }

        It 'exposes the control <_>' -ForEach @(
            'CategoryPanel', 'CategoryChips'
            'ChipCritical', 'ChipCriticalCount', 'ChipWarning', 'ChipWarningCount', 'ChipOK', 'ChipOKCount', 'ChipInfo', 'ChipInfoCount'
            'ProblemSection', 'ProblemTitle', 'ProblemItems'
            'TileSection', 'TileTitle', 'TileColumn1', 'TileColumn2', 'TileColumn3'
        ) {
            $gui.Controls[$_] | Should -Not -BeNullOrEmpty
        }

        It 'puts the chips in the order Critical, Warning, OK, Info, each standing for its status' {
            @($gui.Controls.CategoryChips.Children).Name | Should -Be @('ChipCritical', 'ChipWarning', 'ChipOK', 'ChipInfo')
            @($gui.Controls.CategoryChips.Children).Tag | Should -Be $statuses
        }

        It 'starts with the page hidden: there is nothing to show before the first check' {
            $gui.Controls.CategoryPanel.Visibility | Should -Be 'Collapsed'
        }

        It 'no longer has the four columns' {
            $gui.Controls.ContainsKey('ColumnsPanel') | Should -BeFalse
        }
    }

    Context 'a category with problems' {
        BeforeAll {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Hardware'
        }

        It 'shows the page in place of the list' {
            $gui.Controls.CategoryPanel.Visibility | Should -Be 'Visible'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Collapsed'
            $gui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
        }

        It 'says how many checks need attention' {
            $gui.Controls.PageSubtitle.Text | Should -Be '3 of 6 checks need attention.'
        }

        It 'counts the results of every status on its chip' {
            $gui.Controls.ChipCriticalCount.Text | Should -Be '1'
            $gui.Controls.ChipWarningCount.Text | Should -Be '2'
            $gui.Controls.ChipOKCount.Text | Should -Be '2'
            $gui.Controls.ChipInfoCount.Text | Should -Be '1'
        }

        It 'has no chip chosen while nothing is filtered' {
            foreach ($status in $statuses) {
                $gui.Controls["Chip$status"].IsChecked | Should -BeFalse
                $gui.Controls["Chip$status"].IsEnabled | Should -BeTrue
            }
        }

        It 'lists the problems first, the critical one before the warnings' {
            (Get-TestProblem -Gui $gui).SourceCheck | Should -Be @('Disk (C:)', 'Memory usage', 'Drive health')
            $gui.Controls.ProblemSection.Visibility | Should -Be 'Visible'
            $gui.Controls.ProblemTitle.Text | Should -Be "NEEDS ATTENTION  $dot  3"
        }

        It 'hands a problem everything its card shows' {
            $card = (Get-TestProblem -Gui $gui)[0]
            $card.Check | Should -Be 'Disk (C:)'
            $card.Value | Should -Be '3 % free'
            $card.Recommendation | Should -Be 'Free up space.'
            $card.ActionLabel | Should -Be 'Open Storage settings'
        }

        It 'shows everything else as tiles, the results that are fine before the information' {
            (Get-TestTile -Gui $gui).SourceCheck | Should -Be @('CPU load', 'Disk (D:)', 'Top memory consumers')
            (Get-TestTile -Gui $gui).Status | Should -Be @('OK', 'OK', 'Info')
            $gui.Controls.TileSection.Visibility | Should -Be 'Visible'
            $gui.Controls.TileTitle.Text | Should -Be "EVERYTHING ELSE  $dot  3"
        }

        It 'shows the results of that category only' {
            $problems = Get-TestProblem -Gui $gui
            $tiles = Get-TestTile -Gui $gui
            $all = @($problems) + @($tiles)
            $all.SourceCategory | Select-Object -Unique | Should -Be 'Hardware'
            $all.Count | Should -Be 6
        }

        It 'still holds all cards of the page in one list, most severe first' {
            @($gui.Controls.ResultItems.ItemsSource).Status | Should -Be @('Critical', 'Warning', 'Warning', 'OK', 'OK', 'Info')
        }
    }

    Context 'the three columns of tiles' {
        It 'fills them row by row, so the order is read from left to right' {
            $results = 1..7 | ForEach-Object { New-TestResult -Category 'System' -Check "Check $_" -Status OK -Value "$_" }
            $gui = New-TestWindow -Result $results
            Show-TestPage -Gui $gui -Name 'System'

            (Get-TestTile -Gui $gui -Column 1).SourceCheck | Should -Be @('Check 1', 'Check 4', 'Check 7')
            (Get-TestTile -Gui $gui -Column 2).SourceCheck | Should -Be @('Check 2', 'Check 5')
            (Get-TestTile -Gui $gui -Column 3).SourceCheck | Should -Be @('Check 3', 'Check 6')
        }

        It 'leaves a column empty when there are fewer tiles than columns' {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Network'

            (Get-TestTile -Gui $gui -Column 1).Count | Should -Be 1
            (Get-TestTile -Gui $gui -Column 2).Count | Should -Be 1
            (Get-TestTile -Gui $gui -Column 3).Count | Should -Be 0
        }
    }

    Context 'a category without problems' {
        BeforeAll {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Network'
        }

        It 'says that nothing needs attention' {
            $gui.Controls.PageSubtitle.Text | Should -Be 'Nothing needs attention among these 2 checks.'
        }

        It 'leaves the part for the problems out and calls the tiles the results' {
            $gui.Controls.ProblemSection.Visibility | Should -Be 'Collapsed'
            (Get-TestProblem -Gui $gui).Count | Should -Be 0
            $gui.Controls.TileTitle.Text | Should -Be "RESULTS  $dot  2"
            (Get-TestTile -Gui $gui).SourceCheck | Should -Be @('DNS resolution', 'Proxy')
        }

        It 'shows a chip without results as not available' {
            $gui.Controls.ChipCriticalCount.Text | Should -Be '0'
            $gui.Controls.ChipCritical.IsEnabled | Should -BeFalse
            $gui.Controls.ChipOK.IsEnabled | Should -BeTrue
        }
    }

    Context 'other pages' {
        BeforeEach {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Hardware'
        }

        It 'lists the Overview as before' {
            Show-TestPage -Gui $gui -Name 'Overview'
            $gui.Controls.CategoryPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Visible'
        }

        It 'lists search results, which come from all categories' {
            $gui.Controls.SearchBox.Text = 'disk'
            Show-TestPage -Gui $gui -Name 'Hardware'
            $gui.Controls.CategoryPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Visible'
            @($gui.Controls.ResultItems.ItemsSource).SourceCheck | Should -Be @('Disk (C:)', 'Disk (D:)')
        }

        It 'hides the page of a category on the <_> page' -ForEach 'Live monitor', 'Settings' {
            Show-TestPage -Gui $gui -Name $_
            $gui.Controls.CategoryPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Collapsed'
        }

        It 'hides it before the first check' {
            $empty = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
            Show-TestPage -Gui $empty -Name 'Overview'
            $empty.Controls.CategoryPanel.Visibility | Should -Be 'Collapsed'
            $empty.Controls.EmptyText.Visibility | Should -Be 'Visible'
        }
    }

    Context 'the status filter' {
        BeforeEach {
            $gui = New-TestWindow
        }

        It 'leaves <Problems> problems and <Tiles> tiles for the filter "<Tag>", with the chips <Chosen> chosen' -ForEach @(
            @{ Tag = ''; Problems = 3; Tiles = 3; Chosen = @() }
            @{ Tag = 'Problems'; Problems = 3; Tiles = 0; Chosen = @('Critical', 'Warning') }
            @{ Tag = 'Critical'; Problems = 1; Tiles = 0; Chosen = @('Critical') }
            @{ Tag = 'Warning'; Problems = 2; Tiles = 0; Chosen = @('Warning') }
            @{ Tag = 'OK'; Problems = 0; Tiles = 2; Chosen = @('OK') }
            @{ Tag = 'Info'; Problems = 0; Tiles = 1; Chosen = @('Info') }
        ) {
            Set-TestFilter -Gui $gui -Tag $Tag
            Show-TestPage -Gui $gui -Name 'Hardware'

            (Get-TestProblem -Gui $gui).Count | Should -Be $Problems
            (Get-TestTile -Gui $gui).Count | Should -Be $Tiles
            $gui.Controls.ProblemSection.Visibility | Should -Be $(if ($Problems) { 'Visible' } else { 'Collapsed' })
            $gui.Controls.TileSection.Visibility | Should -Be $(if ($Tiles) { 'Visible' } else { 'Collapsed' })
            @($statuses | Where-Object { $gui.Controls["Chip$_"].IsChecked }) | Should -Be $Chosen
        }

        It 'keeps counting the whole category on the chips' {
            Set-TestFilter -Gui $gui -Tag 'OK'
            Show-TestPage -Gui $gui -Name 'Hardware'

            $gui.Controls.ChipCriticalCount.Text | Should -Be '1'
            $gui.Controls.ChipWarningCount.Text | Should -Be '2'
            $gui.Controls.PageSubtitle.Text | Should -Be '3 of 6 checks need attention.'
        }

        It 'says so when no result has the chosen status, and lets the chip be taken back' {
            Set-TestFilter -Gui $gui -Tag 'Critical'
            Show-TestPage -Gui $gui -Name 'Network'

            $gui.Controls.CategoryPanel.Visibility | Should -Be 'Visible'
            $gui.Controls.EmptyText.Visibility | Should -Be 'Visible'
            $gui.Controls.EmptyText.Text | Should -Be 'No result has the chosen status.'
            $gui.Controls.ChipCritical.IsChecked | Should -BeTrue
            $gui.Controls.ChipCritical.IsEnabled | Should -BeTrue
        }
    }

    Context 'a click on a chip' {
        BeforeEach {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Hardware'
        }

        It 'chooses the status of the chip in the filter' {
            $gui.Controls.ChipOK.IsChecked = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowChipClick -Gui $Gui -Source $Gui.Controls.ChipOK } | Should -Be 'OK'
            [string]$gui.Controls.StatusFilter.SelectedItem.Tag | Should -Be 'OK'

            # The window draws the page again when the filter changes.
            Show-TestPage -Gui $gui -Name 'Hardware'
            (Get-TestTile -Gui $gui).Status | Select-Object -Unique | Should -Be 'OK'
            (Get-TestProblem -Gui $gui).Count | Should -Be 0
        }

        It 'shows everything again with a second click on the chosen chip' {
            Set-TestFilter -Gui $gui -Tag 'OK'
            Show-TestPage -Gui $gui -Name 'Hardware'

            $gui.Controls.ChipOK.IsChecked = $false
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowChipClick -Gui $Gui -Source $Gui.Controls.ChipOK } | Should -Be ''
            [string]$gui.Controls.StatusFilter.SelectedItem.Tag | Should -Be ''
        }

        It 'ignores a click on something that is not a chip' {
            $button = New-Object -TypeName System.Windows.Controls.Button
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowChipClick -Gui $Gui -Source $Source } | Should -Be ''
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowChipClick -Gui $Gui -Source $null } | Should -Be ''
            [string]$gui.Controls.StatusFilter.SelectedItem.Tag | Should -Be ''
        }
    }

    Context 'open and closed tiles' {
        BeforeEach {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Hardware'
        }

        It 'starts with the tiles closed' {
            (Get-TestTile -Gui $gui).Expanded | Should -Be @($false, $false, $false)
        }

        It 'remembers a tile the user has opened' {
            $toggle = New-Object -TypeName System.Windows.Controls.Primitives.ToggleButton
            $toggle.DataContext = (Get-TestTile -Gui $gui)[0]
            $toggle.IsChecked = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $toggle } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

            $gui.CardState['Hardware|CPU load'] | Should -BeTrue
            Show-TestPage -Gui $gui -Name 'Hardware'
            (Get-TestTile -Gui $gui).Expanded | Should -Be @($true, $false, $false)
        }

        It 'keeps that through the results of an automatic check' {
            $gui.CardState['Hardware|CPU load'] = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $testResults) } { Show-WindowReport -Gui $Gui -Report $Report -KeepPage }

            $gui.Page | Should -Be 'Hardware'
            (Get-TestTile -Gui $gui).Expanded | Should -Be @($true, $false, $false)
        }

        It 'starts afresh with a check the user starts' {
            $gui.CardState['Hardware|CPU load'] = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $testResults) } { Show-WindowReport -Gui $Gui -Report $Report }

            $gui.CardState.Count | Should -Be 0
        }

        It 'opens the place in Windows for the button of a problem' {
            Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
            $button = New-Object -TypeName System.Windows.Controls.Button
            $button.DataContext = (Get-TestProblem -Gui $gui)[0]
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

            Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -ParameterFilter { $Check -eq 'Disk (C:)' -and $Category -eq 'Hardware' }
            # A button is not the tile itself: nothing is remembered about open or closed.
            $gui.CardState.Count | Should -Be 0
        }

        It 'says so when Windows cannot open the place' {
            Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $false }
            $button = New-Object -TypeName System.Windows.Controls.Button
            $button.DataContext = (Get-TestProblem -Gui $gui)[0]
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

            $gui.Controls.StatusText.Text | Should -Be 'Windows could not open that place.'
        }

        It 'ignores a click on something that is not a card' {
            Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
            $button = New-Object -TypeName System.Windows.Controls.Button
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source } } | Should -Not -Throw
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCardClick -Gui $Gui -Source $null } } | Should -Not -Throw
            # A chip is clicked inside the same panel, but it is no card.
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCardClick -Gui $Gui -Source $Gui.Controls.ChipOK } } | Should -Not -Throw
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 0 -Exactly
            $gui.CardState.Count | Should -Be 0
        }
    }

    Context 'the way from a notice' {
        It 'opens the tile of the result and frames it' {
            $gui = New-TestWindow
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'CPU load' } | Should -BeTrue

            $gui.Controls.CategoryPanel.Visibility | Should -Be 'Visible'
            $tile = (Get-TestTile -Gui $gui) | Where-Object SourceCheck -eq 'CPU load'
            $tile.Highlight | Should -Be 'Yes'
            # A tile is closed by default; this one is opened, so the user sees what the notice was about.
            $tile.Expanded | Should -BeTrue
        }

        It 'frames the card of a problem, and no other' {
            $gui = New-TestWindow
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'Memory usage' } | Should -BeTrue

            $problems = Get-TestProblem -Gui $gui
            $tiles = Get-TestTile -Gui $gui
            $framed = (@($problems) + @($tiles)) | Where-Object Highlight -eq 'Yes'
            @($framed).SourceCheck | Should -Be 'Memory usage'
        }
    }

    Context 'in Croatian' {
        It 'names the groups of the page in the language of the window' {
            try {
                InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
                $gui = New-TestWindow
                Show-TestPage -Gui $gui -Name 'Hardware'

                $gui.Controls.ProblemTitle.Text | Should -Not -Match 'NEEDS ATTENTION'
                $gui.Controls.ProblemTitle.Text | Should -Match '^TRA'
                $gui.Controls.TileTitle.Text | Should -Match '^SVE OSTALO'
                $gui.Controls.PageSubtitle.Text | Should -Not -Match 'checks need attention'
            }
            finally {
                InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
            }
        }
    }
}

Describe 'The button "Run in background"' -Skip:(-not $isSta) {
    It 'sits in the side bar, above the button for administrator rights' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Controls.BackgroundButton.Content | Should -Be 'Run in background'
        $siblings = @($gui.Controls.BackgroundButton.Parent.Children)
        $siblings.IndexOf($gui.Controls.BackgroundButton) | Should -BeLessThan $siblings.IndexOf($gui.Controls.ElevateButton)
    }

    It 'is wired to send the window to the background' {
        $source = [System.IO.File]::ReadAllText((Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit\Public\Show-PCHealthCheck.ps1'))
        $source | Should -Match 'BackgroundButton\.Add_Click\(\{ Hide-WindowToTray -Gui \$script:HealthCheckWindow \}\)'
    }
}
