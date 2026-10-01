BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Invoke-PCHealthCheck' {
    BeforeAll {
        # Every check category is replaced, so these tests only cover the orchestration:
        # which checks run, what is saved, what is opened and what is returned.
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

        Mock -ModuleName HelpdeskToolkit Write-HealthSummary { }
        Mock -ModuleName HelpdeskToolkit Open-HealthReport { }
        Mock -ModuleName HelpdeskToolkit Write-Progress { }
    }

    Context 'by default' {
        BeforeAll {
            $folder = Join-Path -Path $TestDrive -ChildPath 'default'
            $output = Invoke-PCHealthCheck -OutputPath $folder
        }

        It 'runs every check category once' {
            foreach ($command in 'Get-SystemHealth', 'Get-ComputerSpecification', 'Get-HardwareHealth', 'Get-SoftwareHealth', 'Get-EventLogHealth',
                'Get-WindowsUpdateHealth', 'Get-SecurityHealth', 'Get-NetworkHealth', 'Get-PrinterHealth', 'Get-ServiceHealth') {
                Should -Invoke -ModuleName HelpdeskToolkit $command -Times 1 -Exactly -Scope Context
            }
        }

        It 'creates the output folder and saves only an HTML report' {
            $files = @(Get-ChildItem -Path $folder)
            $files.Count | Should -Be 1
            $files[0].Name | Should -Match '^PCHealth_.+_\d{8}-\d{6}\.html$'
        }

        It 'opens the HTML report' {
            Should -Invoke -ModuleName HelpdeskToolkit Open-HealthReport -Times 1 -Exactly -Scope Context
        }

        It 'prints the console summary' {
            Should -Invoke -ModuleName HelpdeskToolkit Write-HealthSummary -Times 1 -Exactly -Scope Context
        }

        It 'returns nothing to the pipeline' {
            $output | Should -BeNullOrEmpty
        }

        It 'analyzes 7 days of event logs and runs the connectivity tests' {
            Should -Invoke -ModuleName HelpdeskToolkit Get-EventLogHealth -Scope Context -ParameterFilter { $Days -eq 7 }
            Should -Invoke -ModuleName HelpdeskToolkit Get-NetworkHealth -Scope Context -ParameterFilter { -not $SkipConnectivity }
        }
    }

    Context 'the -Format parameter' {
        It 'saves <Extensions> for -Format <Format>' -ForEach @(
            @{ Format = 'Html'; Extensions = '.html' }
            @{ Format = 'Json'; Extensions = '.json' }
            @{ Format = 'Both'; Extensions = '.html .json' }
        ) {
            $folder = Join-Path -Path $TestDrive -ChildPath "format-$Format"
            Invoke-PCHealthCheck -OutputPath $folder -Format $Format -NoOpen
            ((Get-ChildItem -Path $folder).Extension | Sort-Object) -join ' ' | Should -Be $Extensions
        }

        It 'does not try to open a browser when only JSON is requested' {
            Invoke-PCHealthCheck -OutputPath (Join-Path -Path $TestDrive -ChildPath 'json-only') -Format Json
            Should -Invoke -ModuleName HelpdeskToolkit Open-HealthReport -Times 0 -Exactly
        }

        It 'rejects an unknown format' {
            { Invoke-PCHealthCheck -OutputPath $TestDrive -Format Pdf } | Should -Throw
        }
    }

    Context 'the saved JSON report' {
        BeforeAll {
            $folder = Join-Path -Path $TestDrive -ChildPath 'json'
            Invoke-PCHealthCheck -OutputPath $folder -Format Json -Days 14
            $data = Get-Content -LiteralPath (Get-ChildItem -Path $folder -Filter '*.json').FullName -Raw | ConvertFrom-Json
        }

        It 'contains the run details' {
            $data.ComputerName | Should -Be $env:COMPUTERNAME
            $data.EventLogDays | Should -Be 14
            $data.ToolVersion | Should -Match '^\d+\.\d+\.\d+$'
            $data.GeneratedAt | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$'
            $data.IsElevated | Should -BeOfType [bool]
        }

        It 'contains the summary and all results in category order' {
            $data.Summary.OK | Should -Be 5
            $data.Summary.Warning | Should -Be 1
            $data.Summary.Critical | Should -Be 1
            $data.Summary.Info | Should -Be 3
            $data.Results.Category | Should -Be @('System', 'Specifications', 'Hardware', 'Software', 'Event Log', 'Windows Update', 'Security', 'Network', 'Printers', 'Services')
        }
    }

    Context 'the remaining parameters' {
        It 'passes -Days to the event log check' {
            Invoke-PCHealthCheck -OutputPath $TestDrive -NoOpen -Days 30
            Should -Invoke -ModuleName HelpdeskToolkit Get-EventLogHealth -Times 1 -Exactly -ParameterFilter { $Days -eq 30 }
        }

        It 'passes -SkipNetwork to the network check' {
            Invoke-PCHealthCheck -OutputPath $TestDrive -NoOpen -SkipNetwork
            Should -Invoke -ModuleName HelpdeskToolkit Get-NetworkHealth -Times 1 -Exactly -ParameterFilter { $SkipConnectivity }
        }

        It 'does not open the report with -NoOpen' {
            Invoke-PCHealthCheck -OutputPath $TestDrive -NoOpen
            Should -Invoke -ModuleName HelpdeskToolkit Open-HealthReport -Times 0 -Exactly
        }

        It 'returns the results with -PassThru' {
            $results = Invoke-PCHealthCheck -OutputPath $TestDrive -NoOpen -PassThru
            @($results).Count | Should -Be 10
            $results[0].PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.CheckResult'
        }
    }

    Context 'when one check category fails completely' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-SecurityHealth { throw 'Unexpected failure in the security check' }
            $results = Invoke-PCHealthCheck -OutputPath (Join-Path -Path $TestDrive -ChildPath 'failure') -NoOpen -PassThru
        }

        It 'still produces the report with the other categories' {
            @($results).Count | Should -Be 10
            Get-ChildItem -Path (Join-Path -Path $TestDrive -ChildPath 'failure') -Filter '*.html' | Should -Not -BeNullOrEmpty
        }

        It 'reports the failed category as a Warning that carries the error' {
            $failed = $results | Where-Object Category -eq 'Security'
            $failed.Check | Should -Be 'Check execution'
            $failed.Status | Should -Be 'Warning'
            $failed.Recommendation | Should -Match 'Unexpected failure in the security check'
        }
    }
}
