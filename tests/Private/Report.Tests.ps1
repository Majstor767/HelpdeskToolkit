BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
}

Describe 'ConvertTo-HealthReportHtml' {
    BeforeAll {
        $results = @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d 2 h' -Description 'Time since start.' -Allowed '0 - 7 days' -Typical '0 - 3 days'
            New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '10 programs and 2 more' -Details 'Extra One', 'Extra Two' -Recommendation 'Disable some.'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free' -Recommendation 'Free up space.'
            New-TestResult -Category 'Event Log' -Check 'Top <sources>' -Status Info -Value 'A & B "quoted"'
        )
        $report = New-TestReport -Result $results
        $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthReportHtml -Report $Report }
    }

    It 'produces a complete HTML document' {
        $html | Should -Match '^<!DOCTYPE html>'
        $html | Should -Match '<meta charset="utf-8">'
        $html | Should -Match '</html>$'
    }

    It 'is self-contained: styles are embedded and nothing is loaded from elsewhere' {
        $html | Should -Match '<style>'
        $html | Should -Not -Match '<link'
        $html | Should -Not -Match '<script'
        $html | Should -Not -Match '(src|href)\s*=\s*"https?:'
    }

    It 'shows the computer name, date, duration and elevation' {
        $html | Should -Match 'TEST-PC-01'
        $html | Should -Match '2026-01-15 10:30:00'
        $html | Should -Match '<dd>1\.5 s</dd>'
        $html | Should -Match '<dt>Administrator rights</dt><dd>No</dd>'
    }

    It 'shows the count of every status in the summary' {
        $html | Should -Match '<div class="tile critical"><span class="count">1</span>'
        $html | Should -Match '<div class="tile warning"><span class="count">1</span>'
        $html | Should -Match '<div class="tile ok"><span class="count">1</span>'
        $html | Should -Match '<div class="tile info"><span class="count">1</span>'
    }

    It 'creates one card per category' {
        $html | Should -Match '<section class="card" id="cat-system">'
        $html | Should -Match '<section class="card" id="cat-hardware">'
        $html | Should -Match '<section class="card" id="cat-event-log">'
    }

    It 'lists problems first, critical before warning' {
        $html | Should -Match 'Problems and recommendations'
        $problems = $html.Substring($html.IndexOf('id="problems"'), $html.IndexOf('id="cat-system"') - $html.IndexOf('id="problems"'))
        $problems.IndexOf('Disk (C:)') | Should -BeLessThan $problems.IndexOf('Startup programs')
        $problems | Should -Not -Match 'Uptime'
    }

    It 'escapes values that come from the computer' {
        $html | Should -Match 'Top &lt;sources&gt;'
        $html | Should -Match 'A &amp; B &quot;quoted&quot;'
        $html | Should -Not -Match 'Top <sources>'
    }

    It 'shows the description, allowed range and typical value' {
        $html | Should -Match '<div class="description">Time since start\.</div>'
        $html | Should -Match '<b>Allowed:</b> 0 - 7 days'
        $html | Should -Match '<b>Typical:</b> 0 - 3 days'
    }

    It 'puts details into an expandable list' {
        $html | Should -Match '<details><summary>Show 2 more</summary><ul><li>Extra One</li><li>Extra Two</li></ul></details>'
    }

    It 'shows recommendations' {
        $html | Should -Match '<div class="recommendation">Free up space\.</div>'
    }

    It 'says "Action required" when there is a critical result' {
        $html | Should -Match 'class="verdict critical"'
        $html | Should -Match '1 critical problem and 1 warning found'
    }

    It 'says "Attention recommended" when there are only warnings' {
        $warningReport = New-TestReport -Result @(New-TestResult -Status Warning; New-TestResult -Status Warning)
        $text = InModuleScope HelpdeskToolkit -Parameters @{ Report = $warningReport } { ConvertTo-HealthReportHtml -Report $Report }
        $text | Should -Match 'class="verdict warning"'
        $text | Should -Match '2 warnings found'
    }

    It 'says "No problems found" and omits the problem list when everything is fine' {
        $okReport = New-TestReport -Result @(New-TestResult -Status OK; New-TestResult -Status Info)
        $text = InModuleScope HelpdeskToolkit -Parameters @{ Report = $okReport } { ConvertTo-HealthReportHtml -Report $Report }
        $text | Should -Match 'class="verdict ok"'
        $text | Should -Not -Match 'Problems and recommendations'
    }

    It 'mentions skipped checks only when the run was not elevated' {
        $html | Should -Match 'ran without administrator rights'

        $elevated = New-TestReport -Result @(New-TestResult) -IsElevated $true
        $text = InModuleScope HelpdeskToolkit -Parameters @{ Report = $elevated } { ConvertTo-HealthReportHtml -Report $Report }
        $text | Should -Not -Match 'ran without administrator rights'
        $text | Should -Match '<dt>Administrator rights</dt><dd>Yes</dd>'
    }
}

Describe 'Export-HealthReportHtml and Export-HealthReportJson' {
    BeforeAll {
        $report = New-TestReport -Result @(
            New-TestResult -Check 'One' -Status OK
            New-TestResult -Check 'Two' -Status Warning -Details 'a', 'b'
        )
        $htmlPath = Join-Path -Path $TestDrive -ChildPath 'report.html'
        $jsonPath = Join-Path -Path $TestDrive -ChildPath 'report.json'
        $returnedHtml = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $htmlPath } { Export-HealthReportHtml -Report $Report -Path $Path }
        $returnedJson = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $jsonPath } { Export-HealthReportJson -Report $Report -Path $Path }
    }

    It 'creates the files and returns their paths' {
        $returnedHtml | Should -Be $htmlPath
        $returnedJson | Should -Be $jsonPath
        $htmlPath | Should -Exist
        $jsonPath | Should -Exist
    }

    It 'writes UTF-8 without a byte order mark' {
        [System.IO.File]::ReadAllBytes($htmlPath)[0] | Should -Be 60    # "<"
        [System.IO.File]::ReadAllBytes($jsonPath)[0] | Should -Be 123   # "{"
    }

    It 'writes JSON that can be read back with all the data' {
        $data = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        $data.ComputerName | Should -Be 'TEST-PC-01'
        $data.Summary.Warning | Should -Be 1
        @($data.Results).Count | Should -Be 2
        $data.Results[1].Check | Should -Be 'Two'
        $data.Results[1].Details | Should -Be @('a', 'b')
    }
}

Describe 'Open-HealthReport' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        Mock -ModuleName HelpdeskToolkit Invoke-Item { }
        Mock -ModuleName HelpdeskToolkit Write-Warning { }
    }

    It 'opens the report with the default browser, passing a file URI' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowserPath { 'C:\Contoso\browser.exe' }
        InModuleScope HelpdeskToolkit { Open-HealthReport -Path 'C:\Reports\My Report.html' }

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\Contoso\browser.exe' -and $ArgumentList -match 'file:///C:/Reports/My%20Report\.html'
        }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-Item -Times 0 -Exactly
    }

    It 'falls back to the file association when no default browser is found' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowserPath { }
        InModuleScope HelpdeskToolkit { Open-HealthReport -Path 'C:\Reports\report.html' }

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-Item -Times 1 -Exactly
    }

    It 'falls back to the file association when the browser cannot be started' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowserPath { 'C:\Contoso\browser.exe' }
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'Cannot start' }
        InModuleScope HelpdeskToolkit { Open-HealthReport -Path 'C:\Reports\report.html' }

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-Item -Times 1 -Exactly
    }

    It 'warns with the file path instead of failing when nothing can open the report' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowserPath { }
        Mock -ModuleName HelpdeskToolkit Invoke-Item { throw 'Application not found' }

        { InModuleScope HelpdeskToolkit { Open-HealthReport -Path 'C:\Reports\report.html' } } | Should -Not -Throw
        Should -Invoke -ModuleName HelpdeskToolkit Write-Warning -Times 1 -Exactly -ParameterFilter { $Message -match 'C:\\Reports\\report\.html' }
    }
}

Describe 'Write-HealthSummary' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Write-Host { }
        $report = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status Warning -Value '9 d' -Allowed '0 - 7 days' -Typical '0 - 3 days' -Recommendation 'Restart.'
            New-TestResult -Category 'Hardware' -Check 'CPU load' -Status OK -Value '10 %'
        )
        # The summary is printed once here; the tests below inspect the recorded Write-Host calls.
        InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { Write-HealthSummary -Report $Report -ReportPath 'C:\Reports\r.html' }
    }

    It 'prints every category and check' {
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -eq 'System' }
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -eq 'Hardware' }
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -eq 'Uptime: 9 d' }
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -eq 'CPU load: 10 %' }
    }

    It 'colors the status label by status' {
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -match '\[WARNING\]' -and $ForegroundColor -eq 'Yellow' }
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -match '\[OK\]' -and $ForegroundColor -eq 'Green' }
    }

    It 'prints the reference values and the recommendation' {
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -match 'allowed: 0 - 7 days \| typical: 0 - 3 days' }
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -match '-> Restart\.' }
    }

    It 'prints where the report was saved' {
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -Scope Describe -ParameterFilter { $Object -match 'C:\\Reports\\r\.html' }
    }
}
