BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Compare-PCHealthReport' {
    BeforeAll {
        $before = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d'
            New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '20 programs'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Warning -Value '12 % free'
            New-TestResult -Category 'Hardware' -Check 'Disk (D:)' -Status Critical -Value '2 % free'
            New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status Critical -Value '97 %'
            New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
            New-TestResult -Category 'Network' -Check 'Wi-Fi: Cafe' -Status Warning -Value '20 % signal'
        )
        $after = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status Warning -Value '9 d' -Recommendation 'Restart the computer.'
            New-TestResult -Category 'System' -Check 'Startup programs' -Status OK -Value '8 programs'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '3 % free'
            New-TestResult -Category 'Hardware' -Check 'Disk (D:)' -Status Warning -Value '11 % free'
            New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status Critical -Value '98 %'
            # Info and OK both mean "no problem": not a change.
            New-TestResult -Category 'Network' -Check 'Proxy' -Status OK -Value 'Not configured'
            New-TestResult -Category 'Security' -Check 'Firewall' -Status Critical -Value 'Disabled'
        )
        $changes = @(Compare-PCHealthReport -Reference $before -Difference $after)
    }

    It 'returns objects of the change type' {
        $changes[0].PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.ReportChange'
    }

    It 'reports a check as "<Change>" when its status goes from <Before> to <After>' -ForEach @(
        @{ Check = 'Uptime'; Change = 'New problem'; Before = 'OK'; After = 'Warning' }
        @{ Check = 'Disk (C:)'; Change = 'Worse'; Before = 'Warning'; After = 'Critical' }
        @{ Check = 'Disk (D:)'; Change = 'Better'; Before = 'Critical'; After = 'Warning' }
        @{ Check = 'Startup programs'; Change = 'Resolved'; Before = 'Warning'; After = 'OK' }
    ) {
        $item = $changes | Where-Object Check -eq $Check
        $item.Change | Should -Be $Change
        $item.Before | Should -Be $Before
        $item.After | Should -Be $After
    }

    It 'reports a problem in a check that did not exist before as new' {
        $item = $changes | Where-Object Check -eq 'Firewall'
        $item.Change | Should -Be 'New problem'
        $item.Before | Should -Be 'Not checked'
    }

    It 'reports a problem whose check no longer exists as resolved' {
        $item = $changes | Where-Object Check -eq 'Wi-Fi: Cafe'
        $item.Change | Should -Be 'Resolved'
        $item.After | Should -Be 'Not checked'
    }

    It 'does not report a check whose status is as severe as before' {
        $changes.Check | Should -Not -Contain 'Memory usage'
        $changes.Check | Should -Not -Contain 'Proxy'
    }

    It 'carries the current value and the recommendation' {
        $item = $changes | Where-Object Check -eq 'Uptime'
        $item.Value | Should -Be '9 d'
        $item.Recommendation | Should -Be 'Restart the computer.'
        $item.Category | Should -Be 'System'
    }

    It 'lists new problems first and resolved ones last' {
        $changes.Change | Should -Be @('New problem', 'New problem', 'Worse', 'Better', 'Resolved', 'Resolved')
    }

    It 'returns nothing for two reports without a difference' {
        @(Compare-PCHealthReport -Reference $before -Difference $before).Count | Should -Be 0
    }

    It 'tells results with the same name apart by their position' {
        $two = New-TestReport -Result @(
            New-TestResult -Category 'Specifications' -Check 'Storage' -Status OK -Value 'Disk A'
            New-TestResult -Category 'Specifications' -Check 'Storage' -Status OK -Value 'Disk B'
        )
        $secondFails = New-TestReport -Result @(
            New-TestResult -Category 'Specifications' -Check 'Storage' -Status OK -Value 'Disk A'
            New-TestResult -Category 'Specifications' -Check 'Storage' -Status Warning -Value 'Disk B'
        )
        $changed = @(Compare-PCHealthReport -Reference $two -Difference $secondFails)

        $changed.Count | Should -Be 1
        $changed[0].Value | Should -Be 'Disk B'
    }

    It 'accepts the paths of two reports that were saved as JSON' {
        $first = Join-Path -Path $TestDrive -ChildPath 'before.json'
        $second = Join-Path -Path $TestDrive -ChildPath 'after.json'
        InModuleScope HelpdeskToolkit -Parameters @{ Before = $before; After = $after; First = $first; Second = $second } {
            Export-HealthReportJson -Report $Before -Path $First | Out-Null
            Export-HealthReportJson -Report $After -Path $Second | Out-Null
        }
        $fromFiles = @(Compare-PCHealthReport $first $second)

        $fromFiles.Count | Should -Be 6
        ($fromFiles | Where-Object Check -eq 'Disk (C:)').Change | Should -Be 'Worse'
    }

    It 'throws when a report file does not exist' {
        { Compare-PCHealthReport -Reference 'Q:\missing.json' -Difference $after } | Should -Throw '*not found*'
    }
}
