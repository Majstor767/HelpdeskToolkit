# Tests for the line on the Overview that shows how the health score changed over the
# checks the application kept. The History folder is in the test drive (see
# Import-TestModule).

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $history = Join-Path -Path $TestDrive -ChildPath 'AppData\History'

    # A report of the given computer and time with the given number of warnings, which
    # decides the score: 100 minus 4 for each.
    function New-TestScoreReport {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Time, [int]$Warnings = 0, [string]$Computer = 'FIN-LT-014')

        $results = @(New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d')
        for ($number = 1; $number -le $Warnings; $number++) {
            $results += New-TestResult -Category 'Hardware' -Check "Disk ($number)" -Status Warning -Value '9 % free' -Recommendation 'Free up space.'
        }
        $report = New-TestReport -Result $results
        $report.ComputerName = $Computer
        $report.GeneratedAt = $Time
        $report
    }

    function Save-TestReport {
        param($Report)
        InModuleScope HelpdeskToolkit -Parameters @{ Report = $Report } { [void](Save-HealthReportHistory -Report $Report) }
    }

    # The scores the application kept for a computer.
    function Get-TestHistory {
        param([string]$Computer = 'FIN-LT-014', [int]$Maximum = 30)
        InModuleScope HelpdeskToolkit -Parameters @{ Computer = $Computer; Maximum = $Maximum } {
            Get-HealthScoreHistory -ComputerName $Computer -Maximum $Maximum
        }
    }

    function Clear-TestHistory {
        if (Test-Path -LiteralPath $history) {
            Get-ChildItem -LiteralPath $history -File | Remove-Item -Force
        }
    }

    function Get-TestWindow {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }
}

Describe 'Get-HealthScoreHistory' {
    BeforeEach {
        Clear-TestHistory
    }

    It 'returns nothing while no report was kept' {
        @(Get-TestHistory).Count | Should -Be 0
    }

    It 'returns time and score of the kept reports, oldest first' {
        Save-TestReport (New-TestScoreReport -Time '2026-03-02 08:00:00' -Warnings 5)
        Save-TestReport (New-TestScoreReport -Time '2026-03-01 08:00:00' -Warnings 2)
        Save-TestReport (New-TestScoreReport -Time '2026-03-03 16:45:10' -Warnings 0)

        $points = @(Get-TestHistory)
        $points.Count | Should -Be 3
        $points.Score | Should -Be @(92, 80, 100)
        $points[0].Time | Should -Be ([datetime]'2026-03-01 08:00:00')
        $points[2].Time | Should -Be ([datetime]'2026-03-03 16:45:10')
    }

    It 'leaves the reports of other computers out' {
        Save-TestReport (New-TestScoreReport -Time '2026-03-01 08:00:00' -Warnings 1)
        Save-TestReport (New-TestScoreReport -Time '2026-03-02 08:00:00' -Warnings 3 -Computer 'HR-PC-007')

        @(Get-TestHistory).Score | Should -Be @(96)
        @(Get-TestHistory -Computer 'HR-PC-007').Score | Should -Be @(88)
    }

    It 'returns only the newest ones when there are more than asked for' {
        foreach ($day in 1..5) {
            Save-TestReport (New-TestScoreReport -Time ('2026-03-0{0} 08:00:00' -f $day) -Warnings $day)
        }
        @(Get-TestHistory -Maximum 3).Score | Should -Be @(88, 84, 80)
    }

    It 'leaves out a file that does not start like a report' {
        Save-TestReport (New-TestScoreReport -Time '2026-03-01 08:00:00' -Warnings 1)
        Set-Content -LiteralPath (Join-Path -Path $history -ChildPath 'PCHealth_FIN-LT-014_20260302-080000.json') -Value 'not a report'
        Set-Content -LiteralPath (Join-Path -Path $history -ChildPath 'PCHealth_FIN-LT-014_20260303-080000.json') -Value ''

        @(Get-TestHistory).Score | Should -Be @(96)
    }

    It 'reads only the beginning of a file, however large the report is' {
        $report = New-TestScoreReport -Time '2026-03-01 08:00:00' -Warnings 2
        $report.Results[0].Value = 'x' * 300KB
        Save-TestReport $report

        @(Get-TestHistory).Score | Should -Be @(92)
    }
}

Describe 'Show-WindowTrend' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = Get-TestWindow
    }

    It 'stays hidden with fewer than two points' {
        $gui.ScoreHistory = @()
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTrend -Gui $Gui }
        $gui.Controls.TrendBorder.Visibility | Should -Be 'Collapsed'

        $gui.ScoreHistory = @([PSCustomObject]@{ Time = [datetime]'2026-03-01 08:00:00'; Score = 80 })
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTrend -Gui $Gui }
        $gui.Controls.TrendBorder.Visibility | Should -Be 'Collapsed'
    }

    It 'draws one point per check over the whole width, 100 at the top and 0 at the bottom' {
        $gui.ScoreHistory = @(
            [PSCustomObject]@{ Time = [datetime]'2026-03-01 08:00:00'; Score = 100 }
            [PSCustomObject]@{ Time = [datetime]'2026-03-02 08:00:00'; Score = 50 }
            [PSCustomObject]@{ Time = [datetime]'2026-03-05 08:00:00'; Score = 0 }
        )
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTrend -Gui $Gui }

        $gui.Controls.TrendBorder.Visibility | Should -Be 'Visible'
        # The area has no size before the window is shown: 600 by 88 is assumed.
        $line = @($gui.Controls.TrendLine.Points)
        $line.Count | Should -Be 3
        $line[0].X | Should -Be 0
        $line[0].Y | Should -Be 0
        $line[1].X | Should -Be 300
        $line[1].Y | Should -Be 44
        $line[2].X | Should -Be 600
        $line[2].Y | Should -Be 88
        # The filled area is the line, closed along the bottom edge.
        @($gui.Controls.TrendArea.Points).Count | Should -Be 5
    }

    It 'says how many checks the line shows, since when, and where the score went' {
        $gui.Controls.TrendText.Text | Should -Be '3 checks since 2026-03-01: from 100 to 0'
        $gui.Controls.TrendCaption.Text | Should -Be 'oldest check on the left, newest on the right, 0 - 100'
    }
}

Describe 'The score history of the report on the screen' -Skip:(-not $isSta) {
    BeforeEach {
        Clear-TestHistory
        $gui = Get-TestWindow
        Save-TestReport (New-TestScoreReport -Time '2026-03-01 08:00:00' -Warnings 5)
        Save-TestReport (New-TestScoreReport -Time '2026-03-02 08:00:00' -Warnings 3)
    }

    It 'is the kept reports when the report on the screen is one of them' {
        $report = New-TestScoreReport -Time '2026-03-02 08:00:00' -Warnings 3
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report }

        $gui.ScoreHistory.Score | Should -Be @(80, 88)
        $gui.Controls.TrendBorder.Visibility | Should -Be 'Visible'
        $gui.Controls.TrendText.Text | Should -Be '2 checks since 2026-03-01: from 80 to 88'
    }

    It 'ends with a report that was not kept, as after a check the application repeated by itself' {
        $report = New-TestScoreReport -Time '2026-03-02 08:05:00' -Warnings 1
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report }

        $gui.ScoreHistory.Score | Should -Be @(80, 88, 96)
    }

    It 'puts an older report that was opened from a file where it belongs in time' {
        $report = New-TestScoreReport -Time '2026-03-01 12:00:00' -Warnings 0
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report }

        $gui.ScoreHistory.Score | Should -Be @(80, 100, 88)
    }

    It 'shows no line for a computer with a single check' {
        $report = New-TestScoreReport -Time '2026-03-02 08:00:00' -Warnings 3 -Computer 'HR-PC-007'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report }

        @($gui.ScoreHistory).Count | Should -Be 1
        $gui.Controls.TrendBorder.Visibility | Should -Be 'Collapsed'
    }
}
