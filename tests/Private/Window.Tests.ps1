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
    ) {
        $gui.Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'starts with the report buttons disabled, because there is nothing to save yet' {
        $gui.Controls.OpenReportButton.IsEnabled | Should -BeFalse
        $gui.Controls.SaveAsButton.IsEnabled | Should -BeFalse
    }

    It 'starts with an empty category list and a hint' {
        $gui.Controls.CategoryList.Items.Count | Should -Be 0
        $gui.Controls.PageSubtitle.Text | Should -Match 'Run check'
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
        $gui.Controls.VerdictText.Text | Should -Be 'Action required. 1 critical problem and 1 warning found.'
    }

    It 'lists Overview and then every category in the order it ran' {
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'System', 'Hardware', 'Network')
    }

    It 'marks every entry with the worst status and the number of problems' {
        $entries = @($gui.Controls.CategoryList.ItemsSource)
        ($entries | Where-Object Name -eq 'Overview').Worst | Should -Be 'Critical'
        ($entries | Where-Object Name -eq 'Overview').Badge | Should -Be '2'
        ($entries | Where-Object Name -eq 'System').Worst | Should -Be 'Warning'
        ($entries | Where-Object Name -eq 'System').Badge | Should -Be '1'
        ($entries | Where-Object Name -eq 'Network').Worst | Should -Be 'Info'
        ($entries | Where-Object Name -eq 'Network').Badge | Should -Be ''
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
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be @('Uptime', 'Startup programs')
    }

    It 'hides the verdict and the status counts on a category page' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Network' }
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Collapsed'
        $gui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
    }

    It 'shows the page of the entry selected in the category list when no name is given' {
        $gui.Controls.CategoryList.SelectedIndex = 2
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui }
        $gui.Controls.PageTitle.Text | Should -Be 'Hardware'
        @($gui.Controls.ResultItems.ItemsSource).Check | Should -Be @('Disk (C:)')
    }

    It 'returns to the Overview with the verdict and the status counts' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        $gui.Controls.OverviewPanel.Visibility | Should -Be 'Visible'
        $gui.Controls.PageSubtitle.Text | Should -Match '^These 2 results need attention'
    }

    It 'does nothing before the first check has run' {
        $emptyGui = New-TestWindow
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $emptyGui } { Show-WindowPage -Gui $Gui -Name 'System' } } | Should -Not -Throw
        $emptyGui.Controls.PageTitle.Text | Should -Be 'Overview'
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
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Be @('Overview', 'System')
        $gui.Controls.RunButton.IsEnabled | Should -BeTrue
        $gui.Controls.RunButton.Content | Should -Be 'Run check'
        $gui.Worker | Should -BeNullOrEmpty
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
    }
}
