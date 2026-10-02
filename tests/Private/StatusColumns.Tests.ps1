# Tests for the page of a category: its results side by side in four columns, one per
# status, as compact cards that open on a click.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $statuses = 'Critical', 'Warning', 'OK', 'Info'

    # The order in which the checks ran is deliberately not the order of the columns.
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

    # The cards of one column.
    function Get-TestColumn {
        param($Gui, [string]$Status)
        , @($Gui.Controls["Column${Status}Items"].ItemsSource)
    }
}

Describe 'The columns of a category page' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
    }

    Context 'the layout' {
        BeforeAll {
            $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        }

        It 'exposes the control <_>' -ForEach @(
            'ColumnsPanel'
            'ColumnCritical', 'ColumnCriticalCount', 'ColumnCriticalItems', 'ColumnCriticalScroll', 'ColumnCriticalEmpty'
            'ColumnWarning', 'ColumnWarningCount', 'ColumnWarningItems', 'ColumnWarningScroll', 'ColumnWarningEmpty'
            'ColumnOK', 'ColumnOKCount', 'ColumnOKItems', 'ColumnOKScroll', 'ColumnOKEmpty'
            'ColumnInfo', 'ColumnInfoCount', 'ColumnInfoItems', 'ColumnInfoScroll', 'ColumnInfoEmpty'
        ) {
            $gui.Controls[$_] | Should -Not -BeNullOrEmpty
        }

        It 'puts the columns side by side, the most severe status on the left' {
            $gui.Controls.ColumnsPanel.Rows | Should -Be 1
            @($gui.Controls.ColumnsPanel.Children).Name | Should -Be @('ColumnCritical', 'ColumnWarning', 'ColumnOK', 'ColumnInfo')
        }

        It 'starts with the columns hidden: there is nothing to show before the first check' {
            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Collapsed'
        }
    }

    Context 'a category' {
        BeforeAll {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Hardware'
        }

        It 'shows the columns in place of the list' {
            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Visible'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Collapsed'
            $gui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
        }

        It 'puts every result into the column of its status' {
            (Get-TestColumn -Gui $gui -Status 'Critical').SourceCheck | Should -Be 'Disk (C:)'
            (Get-TestColumn -Gui $gui -Status 'Warning').SourceCheck | Should -Be @('Memory usage', 'Drive health')
            (Get-TestColumn -Gui $gui -Status 'OK').SourceCheck | Should -Be @('CPU load', 'Disk (D:)')
            (Get-TestColumn -Gui $gui -Status 'Info').SourceCheck | Should -Be 'Top memory consumers'
        }

        It 'only holds results of its own status in a column' {
            foreach ($status in $statuses) {
                (Get-TestColumn -Gui $gui -Status $status).Status | Select-Object -Unique | Should -Be $status
            }
        }

        It 'says in the head of every column how many results it has' {
            $gui.Controls.ColumnCriticalCount.Text | Should -Be '1'
            $gui.Controls.ColumnWarningCount.Text | Should -Be '2'
            $gui.Controls.ColumnOKCount.Text | Should -Be '2'
            $gui.Controls.ColumnInfoCount.Text | Should -Be '1'
        }

        It 'shows all four columns' {
            foreach ($status in $statuses) {
                $gui.Controls["Column$status"].Visibility | Should -Be 'Visible'
                $gui.Controls["Column${status}Empty"].Visibility | Should -Be 'Collapsed'
            }
        }

        It 'shows the results of that category only' {
            $all = foreach ($status in $statuses) { (Get-TestColumn -Gui $gui -Status $status).SourceCategory }
            $all | Select-Object -Unique | Should -Be 'Hardware'
            @($all).Count | Should -Be 6
        }

        It 'still holds all cards of the page in one list, most severe first' {
            @($gui.Controls.ResultItems.ItemsSource).Status | Should -Be @('Critical', 'Warning', 'Warning', 'OK', 'OK', 'Info')
        }

        It 'says so in a column that has no result' {
            Show-TestPage -Gui $gui -Name 'Network'

            $gui.Controls.ColumnCriticalEmpty.Visibility | Should -Be 'Visible'
            $gui.Controls.ColumnCriticalEmpty.Text | Should -Be 'Nothing here.'
            $gui.Controls.ColumnCriticalCount.Text | Should -Be '0'
            (Get-TestColumn -Gui $gui -Status 'Critical').Count | Should -Be 0
            # The empty column stays in its place, so the others do not move.
            $gui.Controls.ColumnCritical.Visibility | Should -Be 'Visible'
            (Get-TestColumn -Gui $gui -Status 'OK').SourceCheck | Should -Be 'DNS resolution'
        }
    }

    Context 'pages without columns' {
        BeforeEach {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Hardware'
        }

        It 'lists the Overview: its cards need the full width for the fix' {
            Show-TestPage -Gui $gui -Name 'Overview'
            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Visible'
        }

        It 'lists search results, which come from all categories' {
            $gui.Controls.SearchBox.Text = 'disk'
            Show-TestPage -Gui $gui -Name 'Hardware'
            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Visible'
            @($gui.Controls.ResultItems.ItemsSource).SourceCheck | Should -Be @('Disk (C:)', 'Disk (D:)')
        }

        It 'hides the columns on the <_> page' -ForEach 'Live monitor', 'Settings' {
            Show-TestPage -Gui $gui -Name $_
            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Collapsed'
            $gui.Controls.ResultScroll.Visibility | Should -Be 'Collapsed'
        }

        It 'hides the columns before the first check' {
            $empty = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
            Show-TestPage -Gui $empty -Name 'Overview'
            $empty.Controls.ColumnsPanel.Visibility | Should -Be 'Collapsed'
            $empty.Controls.EmptyText.Visibility | Should -Be 'Visible'
        }
    }

    Context 'the status filter' {
        BeforeEach {
            $gui = New-TestWindow
        }

        It 'leaves the columns <Visible> for the filter "<Tag>"' -ForEach @(
            @{ Tag = 'Problems'; Visible = @('Critical', 'Warning') }
            @{ Tag = 'OK'; Visible = @('OK') }
            @{ Tag = 'Critical'; Visible = @('Critical') }
            @{ Tag = ''; Visible = @('Critical', 'Warning', 'OK', 'Info') }
        ) {
            $gui.Controls.StatusFilter.SelectedItem = $gui.Controls.StatusFilter.Items | Where-Object { [string]$_.Tag -eq $Tag }
            Show-TestPage -Gui $gui -Name 'Hardware'

            $shown = $statuses | Where-Object { $gui.Controls["Column$_"].Visibility -eq 'Visible' }
            $shown | Should -Be $Visible
        }

        It 'shows an empty column, not an empty page, when no result has the chosen status' {
            $gui.Controls.StatusFilter.SelectedItem = $gui.Controls.StatusFilter.Items | Where-Object { [string]$_.Tag -eq 'Critical' }
            Show-TestPage -Gui $gui -Name 'Network'

            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Visible'
            $gui.Controls.ColumnCriticalEmpty.Visibility | Should -Be 'Visible'
            $gui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
        }
    }

    Context 'open and closed cards' {
        BeforeEach {
            $gui = New-TestWindow
            Show-TestPage -Gui $gui -Name 'Hardware'
        }

        It 'opens the problems from the start, so their fix is in view, and leaves the rest closed' {
            (Get-TestColumn -Gui $gui -Status 'Critical').Expanded | Should -Be $true
            (Get-TestColumn -Gui $gui -Status 'Warning').Expanded | Should -Be @($true, $true)
            (Get-TestColumn -Gui $gui -Status 'OK').Expanded | Should -Be @($false, $false)
            (Get-TestColumn -Gui $gui -Status 'Info').Expanded | Should -Be $false
        }

        It 'hands a card everything its details show' {
            $card = (Get-TestColumn -Gui $gui -Status 'Critical')[0]
            $card.Check | Should -Be 'Disk (C:)'
            $card.Value | Should -Be '3 % free'
            $card.Recommendation | Should -Be 'Free up space.'
            $card.ActionLabel | Should -Be 'Open Storage settings'
        }

        It 'remembers a card the user has opened' {
            $toggle = New-Object -TypeName System.Windows.Controls.Primitives.ToggleButton
            $toggle.DataContext = (Get-TestColumn -Gui $gui -Status 'OK')[0]
            $toggle.IsChecked = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $toggle } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

            $gui.CardState['Hardware|CPU load'] | Should -BeTrue
            Show-TestPage -Gui $gui -Name 'Hardware'
            (Get-TestColumn -Gui $gui -Status 'OK').Expanded | Should -Be @($true, $false)
        }

        It 'remembers a problem the user has closed' {
            $toggle = New-Object -TypeName System.Windows.Controls.Primitives.ToggleButton
            $toggle.DataContext = (Get-TestColumn -Gui $gui -Status 'Warning')[1]
            $toggle.IsChecked = $false
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $toggle } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

            Show-TestPage -Gui $gui -Name 'Hardware'
            (Get-TestColumn -Gui $gui -Status 'Warning').Expanded | Should -Be @($true, $false)
        }

        It 'keeps that through the results of an automatic check' {
            $gui.CardState['Hardware|CPU load'] = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $testResults) } { Show-WindowReport -Gui $Gui -Report $Report -KeepPage }

            $gui.Page | Should -Be 'Hardware'
            (Get-TestColumn -Gui $gui -Status 'OK').Expanded | Should -Be @($true, $false)
        }

        It 'starts afresh with a check the user starts' {
            $gui.CardState['Hardware|CPU load'] = $true
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $testResults) } { Show-WindowReport -Gui $Gui -Report $Report }

            $gui.CardState.Count | Should -Be 0
        }

        It 'opens the place in Windows for the button of a card' {
            Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
            $button = New-Object -TypeName System.Windows.Controls.Button
            $button.DataContext = (Get-TestColumn -Gui $gui -Status 'Critical')[0]
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

            Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -ParameterFilter { $Check -eq 'Disk (C:)' -and $Category -eq 'Hardware' }
            # A button is not the card itself: nothing is remembered about open or closed.
            $gui.CardState.Count | Should -Be 0
        }

        It 'says so when Windows cannot open the place' {
            Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $false }
            $button = New-Object -TypeName System.Windows.Controls.Button
            $button.DataContext = (Get-TestColumn -Gui $gui -Status 'Critical')[0]
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source }

            $gui.Controls.StatusText.Text | Should -Be 'Windows could not open that place.'
        }

        It 'ignores a click on something that is not a card' {
            Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
            $button = New-Object -TypeName System.Windows.Controls.Button
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source } } | Should -Not -Throw
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCardClick -Gui $Gui -Source $null } } | Should -Not -Throw
            Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 0 -Exactly
        }
    }

    Context 'the way from a notice' {
        It 'opens the card of the result in the column of its status and frames it' {
            $gui = New-TestWindow
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'CPU load' } | Should -BeTrue

            $gui.Controls.ColumnsPanel.Visibility | Should -Be 'Visible'
            $card = (Get-TestColumn -Gui $gui -Status 'OK') | Where-Object SourceCheck -eq 'CPU load'
            $card.Highlight | Should -Be 'Yes'
            # A card that is closed by default is opened, so the user sees what the notice was about.
            $card.Expanded | Should -BeTrue
        }

        It 'frames no other card' {
            $gui = New-TestWindow
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResult -Gui $Gui -Category 'Hardware' -Check 'Memory usage' } | Out-Null

            $framed = foreach ($status in $statuses) { (Get-TestColumn -Gui $gui -Status $status) | Where-Object Highlight -eq 'Yes' }
            @($framed).SourceCheck | Should -Be 'Memory usage'
        }
    }

    Context 'in Croatian' {
        It 'names the columns and their empty text in the language of the window' {
            try {
                InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
                $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
                $gui.Controls.ColumnCriticalEmpty.Text | Should -Not -Be 'Nothing here.'
                $gui.Controls.ColumnCriticalEmpty.Text | Should -Match '^Ovdje nema'
            }
            finally {
                InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
            }
        }
    }
}
