BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-PCHealthReport' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-SystemHealth { New-TestResult -Category 'System' -Check 'Uptime' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-ComputerSpecification { New-TestResult -Category 'Specifications' -Check 'Processor' -Status Info }
        Mock -ModuleName HelpdeskToolkit Get-HardwareHealth { New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical }
        Mock -ModuleName HelpdeskToolkit Get-SoftwareHealth { New-TestResult -Category 'Software' -Check 'Installed programs' -Status Info }
        Mock -ModuleName HelpdeskToolkit Get-EventLogHealth { New-TestResult -Category 'Event Log' -Check 'System log - errors' -Status Warning }
        Mock -ModuleName HelpdeskToolkit Get-WindowsUpdateHealth { New-TestResult -Category 'Windows Update' -Check 'Pending restart' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-SecurityHealth { New-TestResult -Category 'Security' -Check 'Secure Boot' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-NetworkHealth { New-TestResult -Category 'Network' -Check 'Proxy' -Status Info }
        Mock -ModuleName HelpdeskToolkit Get-PrinterHealth { New-TestResult -Category 'Printers' -Check 'Print queue' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-ServiceHealth { New-TestResult -Category 'Services' -Check 'Spooler' -Status OK }
        Mock -ModuleName HelpdeskToolkit Write-Progress { }
    }

    Context 'the report object' {
        BeforeAll {
            $report = Get-PCHealthReport
        }

        It 'is a single object of the report type' {
            @($report).Count | Should -Be 1
            $report.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.HealthReport'
        }

        It 'contains the run details' {
            $report.ComputerName | Should -Be $env:COMPUTERNAME
            $report.EventLogDays | Should -Be 7
            $report.ToolVersion | Should -Match '^\d+\.\d+\.\d+$'
            $report.GeneratedAt | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
            $report.IsElevated | Should -BeOfType [bool]
            $report.DurationSeconds | Should -BeGreaterOrEqual 0
        }

        It 'contains the results of every category in the order they ran' {
            $report.Results.Category | Should -Be @('System', 'Specifications', 'Hardware', 'Software', 'Event Log', 'Windows Update', 'Security', 'Network', 'Printers', 'Services')
        }

        It 'counts the results per status' {
            $report.Summary.OK | Should -Be 5
            $report.Summary.Warning | Should -Be 1
            $report.Summary.Critical | Should -Be 1
            $report.Summary.Info | Should -Be 3
        }

        It 'reports progress under one activity name, which the window relies on' {
            Should -Invoke -ModuleName HelpdeskToolkit Write-Progress -Scope Context -ParameterFilter {
                $Activity -eq 'PC Health Check' -and $Status -eq 'Network'
            }
        }
    }

    Context 'parameters' {
        It 'passes -Days to the event log, software and security checks' {
            Get-PCHealthReport -Days 30 | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-EventLogHealth -Times 1 -Exactly -ParameterFilter { $Days -eq 30 }
            Should -Invoke -ModuleName HelpdeskToolkit Get-SoftwareHealth -Times 1 -Exactly -ParameterFilter { $Days -eq 30 }
            Should -Invoke -ModuleName HelpdeskToolkit Get-SecurityHealth -Times 1 -Exactly -ParameterFilter { $Days -eq 30 }
        }

        It 'passes -SkipNetwork to the network check' {
            Get-PCHealthReport -SkipNetwork | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-NetworkHealth -Times 1 -Exactly -ParameterFilter { $SkipConnectivity }
        }

        It 'rejects -Days outside 1 - 365' {
            { Get-PCHealthReport -Days 0 } | Should -Throw
        }
    }

    Context 'when one check category fails completely' {
        It 'reports that category as a Warning and keeps the others' {
            Mock -ModuleName HelpdeskToolkit Get-HardwareHealth { throw 'Unexpected failure in the hardware check' }
            $report = Get-PCHealthReport

            @($report.Results).Count | Should -Be 10
            $failed = $report.Results | Where-Object Category -eq 'Hardware'
            $failed.Check | Should -Be 'Check execution'
            $failed.Status | Should -Be 'Warning'
            $failed.Recommendation | Should -Match 'Unexpected failure in the hardware check'
        }
    }
}

Describe 'Get-ReportFileName' {
    It 'builds the name from the computer name and the time of the run' {
        $report = New-TestReport -Result @(New-TestResult)
        InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { Get-ReportFileName -Report $Report } |
            Should -Be 'PCHealth_TEST-PC-01_20260115-103000'
    }
}
