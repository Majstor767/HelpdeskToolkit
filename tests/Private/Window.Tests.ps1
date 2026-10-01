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
        New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free'
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
        'VerdictBorder', 'VerdictText', 'CriticalCount', 'WarningCount', 'OkCount', 'InfoCount'
        'ProblemsOnlyCheckBox', 'OpenReportButton', 'SaveAsButton', 'ResultsGrid', 'EmptyText'
        'DetailTitle', 'DetailDescription', 'DetailResult', 'DetailAllowed', 'DetailTypical', 'DetailMore', 'DetailRecommendation'
    ) {
        $gui.Controls[$_] | Should -Not -BeNullOrEmpty
    }

    It 'starts with the report buttons disabled, because there is nothing to save yet' {
        $gui.Controls.OpenReportButton.IsEnabled | Should -BeFalse
        $gui.Controls.SaveAsButton.IsEnabled | Should -BeFalse
        $gui.Controls.ProblemsOnlyCheckBox.IsEnabled | Should -BeFalse
    }

    It 'offers event log periods that Get-PCHealthReport accepts' {
        foreach ($item in $gui.Controls.DaysComboBox.Items) {
            [int]$item.Tag | Should -BeGreaterThan 0
            [int]$item.Tag | Should -BeLessOrEqual 365
        }
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

    It 'lists all results' {
        @($gui.Controls.ResultsGrid.ItemsSource).Count | Should -Be 4
        $gui.Controls.EmptyText.Visibility | Should -Be 'Collapsed'
    }

    It 'enables the controls that need a report' {
        $gui.Controls.OpenReportButton.IsEnabled | Should -BeTrue
        $gui.Controls.SaveAsButton.IsEnabled | Should -BeTrue
        $gui.Controls.ProblemsOnlyCheckBox.IsEnabled | Should -BeTrue
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
    }
}

Describe 'Show-WindowResultList' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
        $gui.Report = New-TestReport -Result $testResults
    }

    It 'shows only problems, critical first, when the filter is on' {
        $gui.Controls.ProblemsOnlyCheckBox.IsChecked = $true
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResultList -Gui $Gui }

        $shown = @($gui.Controls.ResultsGrid.ItemsSource)
        $shown.Check | Should -Be @('Disk (C:)', 'Startup programs')
    }

    It 'shows everything again when the filter is off' {
        $gui.Controls.ProblemsOnlyCheckBox.IsChecked = $false
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResultList -Gui $Gui }

        @($gui.Controls.ResultsGrid.ItemsSource).Count | Should -Be 4
    }

    It 'says that there are no problems when the filter leaves nothing to show' {
        $gui.Report = New-TestReport -Result @(New-TestResult -Status OK)
        $gui.Controls.ProblemsOnlyCheckBox.IsChecked = $true
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResultList -Gui $Gui }

        $gui.Controls.EmptyText.Visibility | Should -Be 'Visible'
        $gui.Controls.EmptyText.Text | Should -Be 'No problems found.'
    }
}

Describe 'Show-WindowResultDetail' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = New-TestWindow
    }

    It 'shows the description, reference values, extra items and recommendation of a result' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Result = $testResults[1] } { Show-WindowResultDetail -Gui $Gui -Result $Result }

        $gui.Controls.DetailTitle.Text | Should -Be 'System - Startup programs'
        $gui.Controls.DetailResult.Text | Should -Be '10 programs and 2 more'
        $gui.Controls.DetailMore.Text | Should -Be 'Extra One, Extra Two'
        $gui.Controls.DetailRecommendation.Text | Should -Be 'Disable some.'
        $gui.Controls.DetailMore.Visibility | Should -Be 'Visible'
    }

    It 'hides the rows a result has no value for' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Result = $testResults[3] } { Show-WindowResultDetail -Gui $Gui -Result $Result }

        $gui.Controls.DetailResult.Visibility | Should -Be 'Visible'
        $gui.Controls.DetailAllowed.Visibility | Should -Be 'Collapsed'
        $gui.Controls.DetailAllowedLabel.Visibility | Should -Be 'Collapsed'
        $gui.Controls.DetailRecommendation.Visibility | Should -Be 'Collapsed'
    }

    It 'returns to the hint when the selection is cleared' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowResultDetail -Gui $Gui -Result $null }

        $gui.Controls.DetailTitle.Text | Should -Match 'Select a row'
        $gui.Controls.DetailResult.Visibility | Should -Be 'Collapsed'
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

Describe 'Invoke-WindowCheck' -Skip:(-not $isSta) {
    It 'does not start a second check while one is running' {
        $gui = New-TestWindow
        $gui.Worker = 'a check is already running'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }

        $gui.Worker | Should -Be 'a check is already running'
        $gui.Controls.RunButton.IsEnabled | Should -BeTrue
    }
}
