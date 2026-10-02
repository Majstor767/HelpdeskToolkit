BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    # A record as Win32_ReliabilityRecords returns it.
    function New-TestRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Source, [int]$Id, [datetime]$Time, [string]$Product)

        [PSCustomObject]@{ SourceName = $Source; EventIdentifier = $Id; TimeGenerated = $Time; ProductName = $Product; Message = '' }
    }
}

Describe 'Get-ChangeTimeline' {
    BeforeAll {
        $day = (Get-Date).Date.AddDays(-2)
        Mock -ModuleName HelpdeskToolkit Get-ReliabilityRecord {
            New-TestRecord -Source 'Application Error' -Id 1000 -Time $day.AddHours(14) -Product 'editor.exe'
            New-TestRecord -Source 'Application Error' -Id 1000 -Time $day.AddHours(11) -Product 'editor.exe'
            New-TestRecord -Source 'Application Hang' -Id 1002 -Time $day.AddHours(10) -Product 'browser.exe'
            New-TestRecord -Source 'MsiInstaller' -Id 1033 -Time $day.AddHours(9) -Product 'Contoso Edit'
            New-TestRecord -Source 'MsiInstaller' -Id 1035 -Time $day.AddHours(9) -Product 'Contoso Edit'
            New-TestRecord -Source 'Microsoft-Windows-WindowsUpdateClient' -Id 19 -Time $day.AddHours(8) -Product 'Security Intelligence Update for Microsoft Defender Antivirus - KB2267602 (Version 1.401.1.0)'
            New-TestRecord -Source 'Microsoft-Windows-WindowsUpdateClient' -Id 19 -Time $day.AddHours(3) -Product 'Security Intelligence Update for Microsoft Defender Antivirus - KB2267602 (Version 1.400.9.0)'
            New-TestRecord -Source 'Microsoft-Windows-WindowsUpdateClient' -Id 19 -Time $day.AddHours(2) -Product '9PMMSR1CGPWG-Contoso.ImageExtension'
            New-TestRecord -Source 'Microsoft-Windows-WindowsUpdateClient' -Id 19 -Time $day.AddHours(1) -Product '9NBLGGH4QGHW-Contoso.Notes'
            New-TestRecord -Source 'Microsoft-Windows-WindowsUpdateClient' -Id 20 -Time $day.AddHours(1) -Product '9WZDNCRFJBMP-Contoso.Store'
            New-TestRecord -Source 'Microsoft-Windows-WindowsUpdateClient' -Id 20 -Time $day.AddDays(-1).AddHours(20) -Product '2026-01 Cumulative Update for Windows 11 (KB5000001)'
            New-TestRecord -Source 'EventLog' -Id 6008 -Time $day.AddDays(-1).AddHours(7) -Product ''
            New-TestRecord -Source 'Microsoft-Windows-WER-SystemErrorReporting' -Id 1001 -Time $day.AddDays(-1).AddHours(7) -Product ''
            New-TestRecord -Source 'Microsoft-Windows-UserPnp' -Id 20001 -Time $day.AddDays(-3) -Product 'Contoso Graphics 770'
            New-TestRecord -Source 'Some Other Source' -Id 42 -Time $day.AddDays(-3) -Product 'Whatever'
        }
        $timeline = @(Get-ChangeTimeline)
    }

    It 'returns objects of the timeline type, newest first' {
        $timeline[0].PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.TimelineEvent'
        $times = @($timeline.Time)
        $times | Should -Be ($times | Sort-Object -Descending)
    }

    It 'calls a <Kind> a <Level>' -ForEach @(
        @{ Kind = 'Program crashed'; Level = 'Problem' }
        @{ Kind = 'Program stopped responding'; Level = 'Problem' }
        @{ Kind = 'Update failed'; Level = 'Problem' }
        @{ Kind = 'Unexpected shutdown'; Level = 'Problem' }
        @{ Kind = 'Windows crashed (blue screen)'; Level = 'Problem' }
        @{ Kind = 'Program installed'; Level = 'Change' }
        @{ Kind = 'Update installed'; Level = 'Change' }
        @{ Kind = 'Driver installed'; Level = 'Change' }
    ) {
        $entries = @($timeline | Where-Object Kind -eq $Kind)
        $entries.Count | Should -BeGreaterThan 0
        $entries.Level | Sort-Object -Unique | Should -Be $Level
    }

    It 'shows the same thing on the same day once, with its number and its newest time' {
        $crash = $timeline | Where-Object Kind -eq 'Program crashed'
        @($crash).Count | Should -Be 1
        $crash.Title | Should -Be 'editor.exe'
        $crash.Count | Should -Be 2
        $crash.Time | Should -Be $day.AddHours(14)
    }

    It 'gathers the definition updates of the antivirus, whatever their version' {
        $definitions = $timeline | Where-Object Title -eq 'Antivirus definitions'
        @($definitions).Count | Should -Be 1
        $definitions.Count | Should -Be 2
    }

    It 'gathers the updates of the Store apps of a day into one entry' {
        $apps = $timeline | Where-Object Title -eq 'Microsoft Store apps'
        @($apps).Count | Should -Be 1
        $apps.Count | Should -Be 2
        $timeline.Title | Should -Not -Contain 'Contoso.ImageExtension'
    }

    It 'keeps the name of a Store app whose update failed, without its Store identifier' {
        $failed = $timeline | Where-Object Title -eq 'Contoso.Store'
        $failed.Kind | Should -Be 'Update failed'
        $failed.Level | Should -Be 'Problem'
    }

    It 'leaves out what tells a technician nothing' {
        # "Windows Installer reconfigured the product" and sources that are not known
        $timeline.Count | Should -Be 10
        $timeline.Title | Should -Not -Contain 'Whatever'
    }

    It 'looks back 30 days by default and as far as -Days says' {
        Should -Invoke -ModuleName HelpdeskToolkit Get-ReliabilityRecord -Scope Describe -ParameterFilter {
            [math]::Abs(($Since - (Get-Date).AddDays(-30)).TotalMinutes) -lt 5
        }
        Get-ChangeTimeline -Days 7 | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Get-ReliabilityRecord -ParameterFilter {
            [math]::Abs(($Since - (Get-Date).AddDays(-7)).TotalMinutes) -lt 5
        }
    }

    It 'returns nothing when Windows has nothing on record' {
        Mock -ModuleName HelpdeskToolkit Get-ReliabilityRecord { }
        Get-ChangeTimeline | Should -BeNullOrEmpty
    }

    It 'rejects -Days outside 1 - 365' {
        { Get-ChangeTimeline -Days 0 } | Should -Throw
    }
}

Describe 'Get-ReliabilityRecord' {
    It 'returns the records after the given time, newest first' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance {
            New-TestRecord -Source 'A' -Id 1 -Time ([datetime]'2026-01-10 08:00') -Product 'old'
            New-TestRecord -Source 'A' -Id 1 -Time ([datetime]'2026-01-14 08:00') -Product 'newest'
            New-TestRecord -Source 'A' -Id 1 -Time ([datetime]'2026-01-12 08:00') -Product 'middle'
        }
        $records = @(InModuleScope HelpdeskToolkit { Get-ReliabilityRecord -Since ([datetime]'2026-01-11') })
        $records.ProductName | Should -Be @('newest', 'middle')
        Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ReliabilityRecords' }
    }
}

Describe 'The timeline in the report' {
    BeforeAll {
        $result = New-TestResult -Category 'System' -Check 'Uptime' -Status OK
        foreach ($command in 'Get-SystemHealth', 'Get-ComputerSpecification', 'Get-HardwareHealth', 'Get-SoftwareHealth', 'Get-EventLogHealth',
            'Get-WindowsUpdateHealth', 'Get-SecurityHealth', 'Get-NetworkHealth', 'Get-PrinterHealth', 'Get-ServiceHealth') {
            Mock -ModuleName HelpdeskToolkit $command { $result }.GetNewClosure()
        }
        Mock -ModuleName HelpdeskToolkit Write-Progress { }
    }

    It 'is part of the report, with the time as text' {
        Mock -ModuleName HelpdeskToolkit Get-ChangeTimeline {
            [PSCustomObject]@{ Time = [datetime]'2026-01-14 09:05:30'; Level = 'Problem'; Kind = 'Program crashed'; Title = 'editor.exe'; Count = 3 }
            [PSCustomObject]@{ Time = [datetime]'2026-01-13 16:40:00'; Level = 'Change'; Kind = 'Program installed'; Title = 'Contoso Edit'; Count = 1 }
        }
        $report = Get-PCHealthReport

        @($report.Timeline).Count | Should -Be 2
        $report.Timeline[0].Time | Should -Be '2026-01-14 09:05'
        $report.Timeline[0].Kind | Should -Be 'Program crashed'
        $report.Timeline[0].Count | Should -Be 3
        $report.Timeline[1].Level | Should -Be 'Change'
        # 30 days is the reach of the test configuration.
        Should -Invoke -ModuleName HelpdeskToolkit Get-ChangeTimeline -Times 1 -Exactly -ParameterFilter { $Days -eq 30 }
    }

    It 'is empty, and the report still complete, when the time line cannot be read' {
        Mock -ModuleName HelpdeskToolkit Get-ChangeTimeline { throw 'WMI is not working' }
        $report = Get-PCHealthReport

        @($report.Timeline).Count | Should -Be 0
        @($report.Results).Count | Should -Be 10
    }

    It 'survives saving as JSON and loading again' {
        $saved = [PSCustomObject]@{
            ToolVersion = '9.9.9'; ComputerName = 'TEST-PC-01'; GeneratedAt = '2026-01-15 10:30:00'; DurationSeconds = 1.5; IsElevated = $false; EventLogDays = 7
            Results     = @(New-TestResult)
            Timeline    = @([PSCustomObject]@{ Time = '2026-01-14 09:05'; Level = 'Problem'; Kind = 'Program crashed'; Title = 'editor.exe'; Count = 3 })
        }
        $loaded = InModuleScope HelpdeskToolkit -Parameters @{ Json = ($saved | ConvertTo-Json -Depth 6) } {
            ConvertTo-HealthReport -InputObject ($Json | ConvertFrom-Json)
        }

        @($loaded.Timeline).Count | Should -Be 1
        $loaded.Timeline[0].Time | Should -Be '2026-01-14 09:05'
        $loaded.Timeline[0].Title | Should -Be 'editor.exe'
        $loaded.Timeline[0].Count | Should -Be 3
        $loaded.Timeline[0].Count | Should -BeOfType [int]
    }

    It 'is empty for a report that an older version saved without one' {
        $old = [PSCustomObject]@{ ToolVersion = '0.0.1'; ComputerName = 'TEST-PC-01'; GeneratedAt = '2026-01-15 10:30:00'; Results = @(New-TestResult) }
        $loaded = InModuleScope HelpdeskToolkit -Parameters @{ Old = $old } { ConvertTo-HealthReport -InputObject $Old }
        @($loaded.Timeline).Count | Should -Be 0
    }
}

Describe 'The timeline and the score in the HTML report' {
    BeforeAll {
        $report = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status Warning -Value '9 d'
            New-TestResult -Category 'Security' -Check 'Firewall' -Status Critical -Value 'Disabled'
            New-TestResult -Category 'Security' -Check 'SmartScreen' -Status Warning -Value 'Disabled'
            New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
        )
        $report | Add-Member -NotePropertyName Timeline -NotePropertyValue @(
            [PSCustomObject]@{ Time = '2026-01-14 09:05'; Level = 'Problem'; Kind = 'Program crashed'; Title = 'editor <beta>.exe'; Count = 3 }
            [PSCustomObject]@{ Time = '2026-01-13 16:40'; Level = 'Change'; Kind = 'Program installed'; Title = 'Contoso Edit'; Count = 1 }
        )
        $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthReportHtml -Report $Report }
    }

    It 'says which categories cost how many points, the most expensive first' {
        $html | Should -Match 'Health score 77 of 100\. Points lost: <span><b>Security</b> &minus;19 \(1 critical, 1 warning\)</span><span><b>System</b> &minus;4 \(1 warning\)</span>'
    }

    It 'has a timeline section with the number of problems and changes' {
        $html | Should -Match '<section class="card" id="timeline">'
        $html | Should -Match '1 problems &middot; 1 changes'
        $html | Should -Match 'Show the 2 entries'
    }

    It 'writes one row per entry, marks the problems and shows how often something happened' {
        $html | Should -Match '<tr class="problem"><td class="col-time">2026-01-14 09:05</td><td class="col-kind"><span class="dot critical"></span>Program crashed</td>'
        $html | Should -Match '&times; 3'
        $html | Should -Match '<tr class="change"><td class="col-time">2026-01-13 16:40</td><td class="col-kind"><span class="dot info"></span>Program installed</td><td>Contoso Edit</td></tr>'
    }

    It 'encodes the names, like everything else in the report' {
        $html | Should -Match 'editor &lt;beta&gt;\.exe'
        $html | Should -Not -Match 'editor <beta>'
    }

    It 'leaves both out where there is nothing to say' {
        $healthy = New-TestReport -Result @(New-TestResult -Status OK)
        $plain = InModuleScope HelpdeskToolkit -Parameters @{ Report = $healthy } { ConvertTo-HealthReportHtml -Report $Report }
        $plain | Should -Not -Match 'id="timeline"'
        $plain | Should -Not -Match 'Points lost'
    }
}
