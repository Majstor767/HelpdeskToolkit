BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-EventLogHealth' {
    BeforeAll {
        # Four queries are made: unexpected shutdowns (event 6008), blue screens (event
        # 1001), then critical/error events of the System and of the Application log.
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { throw "Unexpected event log query" }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].Id -eq 1001 } {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].Id -eq 6008 } {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter {
            $FilterHashtable[0].LogName -eq 'System' -and -not $FilterHashtable[0].ContainsKey('Id')
        } {
            New-TestEvent -Level 2 -Source 'Service Control Manager' -Count 3
            New-TestEvent -Level 2 -Source 'Disk' -Count 1
        }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].LogName -eq 'Application' } {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }
    }

    Context 'with a few errors and no critical events' {
        BeforeAll {
            $results = Get-EventLogHealth
        }

        It 'returns eight results in the Event Log category' {
            @($results).Count | Should -Be 8
            $results.Category | Sort-Object -Unique | Should -Be 'Event Log'
        }

        It 'reports <Check> as <Status> with value "<Value>"' -ForEach @(
            @{ Check = 'Unexpected shutdowns'; Status = 'OK'; Value = '0 in the last 7 days' }
            @{ Check = 'Blue screens'; Status = 'OK'; Value = '0 in the last 7 days' }
            @{ Check = 'System log - critical events'; Status = 'OK'; Value = '0 in the last 7 days' }
            @{ Check = 'System log - errors'; Status = 'OK'; Value = '4 in the last 7 days' }
            @{ Check = 'System log - top sources'; Status = 'Info'; Value = 'Service Control Manager (3), Disk (1)' }
            @{ Check = 'Application log - critical events'; Status = 'OK'; Value = '0 in the last 7 days' }
            @{ Check = 'Application log - errors'; Status = 'OK'; Value = '0 in the last 7 days' }
            @{ Check = 'Application log - top sources'; Status = 'Info'; Value = 'None' }
        ) {
            $result = $results | Where-Object Check -eq $Check
            $result.Status | Should -Be $Status
            $result.Value | Should -Be $Value
        }

        It 'treats "no matching events" as a clean log, not as an error' {
            $results | Where-Object Value -eq 'Unavailable' | Should -BeNullOrEmpty
        }

        It 'adds the allowed range to the counts' {
            ($results | Where-Object Check -eq 'System log - errors').Allowed | Should -Be '0 - 50'
            ($results | Where-Object Check -eq 'System log - critical events').Allowed | Should -Be '0 (critical above 4)'
        }
    }

    Context 'the -Days parameter' {
        It 'looks back the requested number of days' {
            Get-EventLogHealth -Days 30 | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter {
                $FilterHashtable[0].LogName -eq 'Application' -and
                [math]::Abs(($FilterHashtable[0].StartTime - (Get-Date).AddDays(-30)).TotalMinutes) -lt 5
            }
        }

        It 'mentions the period in the value' {
            (Get-EventLogHealth -Days 30 | Where-Object Check -eq 'System log - errors').Value | Should -Be '4 in the last 30 days'
            (Get-EventLogHealth -Days 1 | Where-Object Check -eq 'System log - errors').Value | Should -Be '4 in the last day'
        }

        It 'rejects values outside 1 - 365' {
            { Get-EventLogHealth -Days 0 } | Should -Throw
            { Get-EventLogHealth -Days 366 } | Should -Throw
        }
    }

    Context 'with critical events' {
        It 'is <Status> for <Count> critical event(s)' -ForEach @(
            @{ Count = 1; Status = 'Warning' }
            @{ Count = 4; Status = 'Warning' }
            @{ Count = 5; Status = 'Critical' }
        ) {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter {
                $FilterHashtable[0].LogName -eq 'System' -and -not $FilterHashtable[0].ContainsKey('Id')
            } {
                New-TestEvent -Level 1 -Source 'Microsoft-Windows-Kernel-Power' -Count $Count
            }
            $critical = Get-EventLogHealth | Where-Object Check -eq 'System log - critical events'
            $critical.Status | Should -Be $Status
            $critical.Recommendation | Should -Match 'Event Viewer'
        }
    }

    Context 'with many errors from many sources' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter {
                $FilterHashtable[0].LogName -eq 'System' -and -not $FilterHashtable[0].ContainsKey('Id')
            } {
                New-TestEvent -Level 2 -Source 'SourceA' -Count 30
                New-TestEvent -Level 2 -Source 'SourceB' -Count 12
                New-TestEvent -Level 2 -Source 'SourceC' -Count 6
                New-TestEvent -Level 2 -Source 'SourceD' -Count 4
                New-TestEvent -Level 2 -Source 'SourceE' -Count 3
                New-TestEvent -Level 2 -Source 'SourceF' -Count 2
                New-TestEvent -Level 2 -Source 'SourceG' -Count 1
            }
            $results = Get-EventLogHealth
        }

        It 'is a Warning above 50 errors' {
            $errors = $results | Where-Object Check -eq 'System log - errors'
            $errors.Status | Should -Be 'Warning'
            $errors.Value | Should -Be '58 in the last 7 days'
        }

        It 'shows the five busiest sources and keeps the rest as details' {
            $sources = $results | Where-Object Check -eq 'System log - top sources'
            $sources.Value | Should -Be 'SourceA (30), SourceB (12), SourceC (6), SourceD (4), SourceE (3) and 2 more'
            $sources.Details | Should -Be @('SourceF (2)', 'SourceG (1)')
        }
    }

    Context 'with unexpected shutdowns' {
        It 'is a Warning and explains the possible causes' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].Id -eq 6008 } {
                New-TestEvent -Level 2 -Source 'EventLog' -Count 2
            }
            $shutdowns = Get-EventLogHealth | Where-Object Check -eq 'Unexpected shutdowns'
            $shutdowns.Status | Should -Be 'Warning'
            $shutdowns.Value | Should -Be '2 in the last 7 days'
            $shutdowns.Recommendation | Should -Match 'power'
        }
    }

    Context 'with blue screens' {
        It 'is a Warning that points to drivers, memory and overheating' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].Id -eq 1001 } {
                New-TestEvent -Level 2 -Source 'Microsoft-Windows-WER-SystemErrorReporting' -Count 3
            }
            $blueScreens = Get-EventLogHealth | Where-Object Check -eq 'Blue screens'
            $blueScreens.Status | Should -Be 'Warning'
            $blueScreens.Value | Should -Be '3 in the last 7 days'
            $blueScreens.Recommendation | Should -Match 'driver'
        }

        It 'is reported as unavailable when the query fails' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].Id -eq 1001 } { throw 'Query failed' }
            (Get-EventLogHealth | Where-Object Check -eq 'Blue screens').Value | Should -Be 'Unavailable'
        }
    }

    Context 'when a log cannot be read' {
        It 'marks a permission problem as "Requires admin" and still reports the other log' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].LogName -eq 'Application' } {
                throw (New-Object -TypeName System.UnauthorizedAccessException -ArgumentList 'Access denied')
            }
            $results = Get-EventLogHealth
            ($results | Where-Object Check -eq 'Application log').Value | Should -Be 'Requires admin'
            ($results | Where-Object Check -eq 'System log - errors').Status | Should -Be 'OK'
        }

        It 'reports any other failure as unavailable' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].Id -eq 6008 } {
                throw 'The event log service is not running'
            }
            $shutdowns = Get-EventLogHealth | Where-Object Check -eq 'Unexpected shutdowns'
            $shutdowns.Status | Should -Be 'Warning'
            $shutdowns.Value | Should -Be 'Unavailable'
        }
    }
}
