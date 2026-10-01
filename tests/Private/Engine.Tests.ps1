# Tests for the parts that work on a whole report: score, loading, CSV and PDF export,
# and running the checks on another computer.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $testResults = @(
        New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d' -Description 'Time since start.' -Allowed '0 - 7 days' -Typical '0 - 3 days'
        New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '10 programs and 2 more' -Details 'Extra One', 'Extra Two' -Recommendation 'Disable some.'
        New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free' -Recommendation 'Free up space.'
        New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
    )
}

Describe 'Get-HealthScore' {
    It 'is <Expected> with <Critical> critical results and <Warning> warnings' -ForEach @(
        @{ Critical = 0; Warning = 0; Expected = 100 }
        @{ Critical = 0; Warning = 3; Expected = 88 }
        @{ Critical = 1; Warning = 0; Expected = 85 }
        @{ Critical = 2; Warning = 5; Expected = 50 }
        @{ Critical = 9; Warning = 9; Expected = 0 }
    ) {
        $summary = @{ OK = 10; Info = 20; Critical = $Critical; Warning = $Warning }
        InModuleScope HelpdeskToolkit -Parameters @{ Summary = $summary } { Get-HealthScore -Summary $Summary } | Should -Be $Expected
    }

    It 'accepts the summary of a report that was read from JSON' {
        $summary = '{ "OK": 3, "Warning": 2, "Critical": 0, "Info": 1 }' | ConvertFrom-Json
        InModuleScope HelpdeskToolkit -Parameters @{ Summary = $summary } { Get-HealthScore -Summary $Summary } | Should -Be 92
    }
}

Describe 'Get-ToolVersion' {
    It 'returns the version of the module manifest' {
        $expected = (Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'HelpdeskToolkit.psd1')).ModuleVersion
        InModuleScope HelpdeskToolkit { Get-ToolVersion } | Should -Be $expected
    }

    It 'returns the version that was handed over when the functions run without the manifest' {
        try {
            InModuleScope HelpdeskToolkit { $script:ToolVersion = '7.7.7'; Get-ToolVersion } | Should -Be '7.7.7'
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:ToolVersion = $null }
        }
    }
}

Describe 'ConvertTo-HealthReport and Import-HealthReport' {
    BeforeAll {
        $report = New-TestReport -Result $testResults
        $path = Join-Path -Path $TestDrive -ChildPath 'saved.json'
        InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $path } { Export-HealthReportJson -Report $Report -Path $Path } | Out-Null
        $loaded = InModuleScope HelpdeskToolkit -Parameters @{ Path = $path } { Import-HealthReport -Path $Path }
    }

    It 'restores the run details' {
        $loaded.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.HealthReport'
        $loaded.ComputerName | Should -Be 'TEST-PC-01'
        $loaded.GeneratedAt | Should -Be '2026-01-15 10:30:00'
        $loaded.ToolVersion | Should -Be '9.9.9'
        $loaded.EventLogDays | Should -Be 7
        $loaded.IsElevated | Should -BeFalse
    }

    It 'restores every result with all its properties' {
        $loaded.Results.Check | Should -Be @('Uptime', 'Startup programs', 'Disk (C:)', 'Proxy')
        $loaded.Results[0].Allowed | Should -Be '0 - 7 days'
        $loaded.Results[0].Description | Should -Be 'Time since start.'
        $loaded.Results[2].Recommendation | Should -Be 'Free up space.'
    }

    It 'restores the details as a list, also when a result has none' {
        $loaded.Results[1].Details | Should -Be @('Extra One', 'Extra Two')
        , $loaded.Results[0].Details | Should -BeOfType [array]
        @($loaded.Results[0].Details).Count | Should -Be 0
    }

    It 'counts the summary again as a table that can be indexed by status' {
        $loaded.Summary['Critical'] | Should -Be 1
        $loaded.Summary['Warning'] | Should -Be 1
        $loaded.Summary['OK'] | Should -Be 1
        $loaded.Summary['Info'] | Should -Be 1
    }

    It 'calculates the score, also for a report of an older version that has none' {
        $old = '{ "ComputerName": "OLD-PC", "Results": [ { "Category": "System", "Check": "Uptime", "Status": "Warning", "Value": "9 d" } ] }' | ConvertFrom-Json
        $converted = InModuleScope HelpdeskToolkit -Parameters @{ Data = $old } { ConvertTo-HealthReport -InputObject $Data }

        $converted.Score | Should -Be 96
        $converted.Results[0].Recommendation | Should -Be ''
        $converted.GeneratedAt | Should -Be ''
    }

    It 'can be exported again after loading' {
        $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = $loaded } { ConvertTo-HealthReportHtml -Report $Report }
        $html | Should -Match 'Startup programs'
        $html | Should -Match 'Show 2 more'
    }

    It 'throws for a file that does not exist' {
        { InModuleScope HelpdeskToolkit { Import-HealthReport -Path 'Q:\missing\report.json' } } | Should -Throw '*not found*'
    }

    It 'throws for a JSON file that is not a report' {
        $other = Join-Path -Path $TestDrive -ChildPath 'other.json'
        Set-Content -LiteralPath $other -Value '{ "name": "something else" }'
        { InModuleScope HelpdeskToolkit -Parameters @{ Path = $other } { Import-HealthReport -Path $Path } } | Should -Throw '*not a HelpdeskToolkit report*'
    }
}

Describe 'The health score in the report' {
    BeforeAll {
        $report = New-TestReport -Result $testResults
    }

    It 'is shown in the header of the HTML report' {
        $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthReportHtml -Report $Report }
        $html | Should -Match '<dt>Health score</dt><dd>81 of 100</dd>'
    }

    It 'is left out of the HTML report when the report has no score' {
        $old = $report | Select-Object -Property * -ExcludeProperty Score
        $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = $old } { ConvertTo-HealthReportHtml -Report $Report }
        $html | Should -Not -Match 'Health score'
    }

    It 'is printed in the console summary' {
        Mock -ModuleName HelpdeskToolkit Write-Host { }
        InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { Write-HealthSummary -Report $Report }
        Should -Invoke -ModuleName HelpdeskToolkit Write-Host -ParameterFilter { $Object -eq 'Health score: 81 of 100' }
    }
}

Describe 'Export-HealthReportCsv' {
    BeforeAll {
        $report = New-TestReport -Result $testResults
        $path = Join-Path -Path $TestDrive -ChildPath 'report.csv'
        $returned = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $path } { Export-HealthReportCsv -Report $Report -Path $Path -Delimiter ';' }
        $rows = @(Import-Csv -LiteralPath $path -Delimiter ';')
    }

    It 'returns the path of the file it wrote' {
        $returned | Should -Be $path
        $path | Should -Exist
    }

    It 'writes one line per check with all columns' {
        $rows.Count | Should -Be 4
        $rows[0].PSObject.Properties.Name | Should -Be @('Category', 'Check', 'Status', 'Value', 'Details', 'Allowed', 'Typical', 'Recommendation', 'Description')
        $rows[2].Check | Should -Be 'Disk (C:)'
        $rows[2].Status | Should -Be 'Critical'
        $rows[2].Recommendation | Should -Be 'Free up space.'
    }

    It 'joins the items of a long list into one cell' {
        $rows[1].Details | Should -Be 'Extra One; Extra Two'
        $rows[0].Details | Should -Be ''
    }

    It 'starts with a byte order mark, so Excel reads the file as UTF-8' {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0], $bytes[1], $bytes[2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'uses the list separator of the regional settings unless another one is given' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        $regional = Join-Path -Path $TestDrive -ChildPath 'regional.csv'
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]'hr-HR'
            InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $regional } { Export-HealthReportCsv -Report $Report -Path $Path } | Out-Null
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
        (Get-Content -LiteralPath $regional -TotalCount 1) | Should -Match '^"Category";"Check";"Status"'
    }
}

Describe 'Get-PdfBrowserPath' {
    It 'prefers Microsoft Edge' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
        InModuleScope HelpdeskToolkit { Get-PdfBrowserPath } | Should -BeLike '*\Microsoft\Edge\Application\msedge.exe'
    }

    It 'falls back to Google Chrome' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $LiteralPath -like '*chrome.exe' }
        InModuleScope HelpdeskToolkit { Get-PdfBrowserPath } | Should -BeLike '*\Google\Chrome\Application\chrome.exe'
    }

    It 'returns nothing when neither browser is installed' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        InModuleScope HelpdeskToolkit { Get-PdfBrowserPath } | Should -BeNullOrEmpty
    }
}

Describe 'Export-HealthReportPdf' {
    BeforeAll {
        $report = New-TestReport -Result $testResults
        Mock -ModuleName HelpdeskToolkit Get-PdfBrowserPath { 'C:\Contoso\browser.exe' }
    }

    It 'lets the browser print the HTML report to the PDF file, without a window' {
        $path = Join-Path -Path $TestDrive -ChildPath 'report.pdf'
        # Stands in for the browser: creates the file named in the --print-to-pdf argument.
        Mock -ModuleName HelpdeskToolkit Start-Process {
            $target = ($ArgumentList | Where-Object { $_ -like '--print-to-pdf=*' }) -replace '^--print-to-pdf="?', '' -replace '"$', ''
            [System.IO.File]::WriteAllText($target, '%PDF-test')
        }
        $returned = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $path } { Export-HealthReportPdf -Report $Report -Path $Path -TimeoutSeconds 5 }

        $returned | Should -Be $path
        $path | Should -Exist
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq 'C:\Contoso\browser.exe' -and
            $ArgumentList -contains '--headless=new' -and
            $ArgumentList -contains '--no-pdf-header-footer' -and
            ($ArgumentList -join ' ') -match 'file:///.+HelpdeskToolkit-.+\.html'
        }
    }

    It 'removes the temporary HTML file afterwards' {
        $path = Join-Path -Path $TestDrive -ChildPath 'cleanup.pdf'
        $script:temporaryFile = $null
        Mock -ModuleName HelpdeskToolkit Start-Process {
            $script:temporaryFile = ([System.Uri](($ArgumentList | Select-Object -Last 1).Trim('"'))).LocalPath
            [System.IO.File]::WriteAllText((Join-Path -Path $TestDrive -ChildPath 'cleanup.pdf'), '%PDF-test')
        }
        InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $path } { Export-HealthReportPdf -Report $Report -Path $Path -TimeoutSeconds 5 } | Out-Null

        $temporaryFile | Should -Not -BeNullOrEmpty
        $temporaryFile | Should -Not -Exist
    }

    It 'throws when the browser produces no file in time' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        $path = Join-Path -Path $TestDrive -ChildPath 'never.pdf'
        { InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $path } { Export-HealthReportPdf -Report $Report -Path $Path -TimeoutSeconds 5 } } |
            Should -Throw '*did not create the PDF*'
    }

    It 'throws with an explanation when no suitable browser is installed' {
        Mock -ModuleName HelpdeskToolkit Get-PdfBrowserPath { }
        { InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { Export-HealthReportPdf -Report $Report -Path 'C:\unused.pdf' } } |
            Should -Throw '*Microsoft Edge or Google Chrome*'
    }
}

Describe 'ConvertFrom-DataFileText' {
    It 'returns the table a data file describes, with nested tables and lists' {
        $data = InModuleScope HelpdeskToolkit { ConvertFrom-DataFileText -Text "@{ Disk = @{ WarningFreePercent = 15 }; Services = @('A', 'B'); Ports = @{ 23 = 'Telnet' } }" }
        $data.Disk.WarningFreePercent | Should -Be 15
        $data.Services | Should -Be @('A', 'B')
        $data.Ports[23] | Should -Be 'Telnet'
    }

    It 'reads the real configuration files exactly like Import-PowerShellDataFile' {
        foreach ($file in 'Thresholds.psd1', 'Descriptions.psd1') {
            $path = Join-Path -Path $moduleRoot -ChildPath "Config\$file"
            $fromText = InModuleScope HelpdeskToolkit -Parameters @{ Text = [System.IO.File]::ReadAllText($path) } { ConvertFrom-DataFileText -Text $Text }
            $fromFile = Import-PowerShellDataFile -Path $path
            ($fromText.Keys | Sort-Object) | Should -Be ($fromFile.Keys | Sort-Object)
        }
    }

    It 'refuses text that contains code instead of plain data' {
        { InModuleScope HelpdeskToolkit { ConvertFrom-DataFileText -Text '@{ Now = (Get-Date) }' } } | Should -Throw
    }

    It 'throws for text that is not a table' {
        { InModuleScope HelpdeskToolkit { ConvertFrom-DataFileText -Text '"just a text"' } } | Should -Throw '*does not contain a table*'
    }
}

Describe 'Get-RemoteModuleScript' {
    BeforeAll {
        $source = InModuleScope HelpdeskToolkit { Get-RemoteModuleScript }

        # Loads the script the way the other computer does: in a fresh PowerShell
        # session that knows nothing about this module, and asks it a few questions.
        $worker = [powershell]::Create()
        [void]$worker.AddScript({
                param($Source, $ThresholdText, $DescriptionText)
                $module = New-Module -Name HelpdeskToolkitRemote -ScriptBlock ([scriptblock]::Create($Source)) -ArgumentList $ThresholdText, $DescriptionText, '4.5.6'
                & $module {
                    [PSCustomObject]@{
                        Version     = Get-ToolVersion
                        Limit       = (Get-HealthThreshold).Disk.WarningFreePercent
                        Description = (New-CheckResult -Category 'System' -Check 'Uptime' -Status OK).Description
                        Commands    = @(Get-Command -Module HelpdeskToolkitRemote -Name 'Get-PCHealthReport', 'Get-HardwareHealth', 'New-CheckResult' -ErrorAction SilentlyContinue).Count
                    }
                }
            }.ToString()).AddArgument($source).AddArgument("@{ Disk = @{ WarningFreePercent = 42 } }").AddArgument("@{ 'Uptime' = 'Sent along.' }")
        $answer = $worker.Invoke() | Select-Object -First 1
        $workerErrors = @($worker.Streams.Error)
        $worker.Dispose()
    }

    It 'loads in a session that does not have the module, without errors' {
        $workerErrors | Should -BeNullOrEmpty
        $answer | Should -Not -BeNullOrEmpty
    }

    It 'defines the functions of the module there' {
        $answer.Commands | Should -Be 3
    }

    It 'uses the configuration that was sent along instead of files' {
        $answer.Limit | Should -Be 42
        $answer.Description | Should -Be 'Sent along.'
    }

    It 'reports the version that was sent along' {
        $answer.Version | Should -Be '4.5.6'
    }

    It 'contains every variable the module file defines' {
        $moduleFile = Get-Content -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'HelpdeskToolkit.psm1')
        $variables = @($moduleFile | Where-Object { $_ -match '^\$script:(\w+)\s*=' } | ForEach-Object { $Matches[1] })
        $variables.Count | Should -BeGreaterThan 5
        foreach ($variable in $variables) {
            $source | Should -Match ([regex]::Escape("`$script:$variable =")) -Because "the variable $variable must exist on the other computer too"
        }
    }
}

Describe 'Get-RemoteHealthReport' {
    BeforeAll {
        $remoteJson = '{ "ToolVersion": "9.9.9", "ComputerName": "PC-014", "GeneratedAt": "2026-01-15 10:30:00", "DurationSeconds": 12.5, "IsElevated": true, "EventLogDays": 30, "Results": [ { "Category": "System", "Check": "Uptime", "Status": "Warning", "Value": "9 d", "Details": [], "Allowed": "", "Typical": "", "Recommendation": "Restart.", "Description": "" } ] }'
        Mock -ModuleName HelpdeskToolkit Invoke-Command { $remoteJson }
    }

    It 'returns the report of the other computer as a report object' {
        $report = InModuleScope HelpdeskToolkit { $computer = 'PC-014'; Get-RemoteHealthReport -ComputerName $computer -Days 30 }

        $report.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.HealthReport'
        $report.ComputerName | Should -Be 'PC-014'
        $report.IsElevated | Should -BeTrue
        $report.Results[0].Recommendation | Should -Be 'Restart.'
        $report.Summary['Warning'] | Should -Be 1
        $report.Score | Should -Be 96
    }

    It 'sends the functions, the configuration, the version and the parameters to that computer' {
        InModuleScope HelpdeskToolkit { $computer = 'PC-014'; Get-RemoteHealthReport -ComputerName $computer -Days 30 -SkipNetwork } | Out-Null

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-Command -Times 1 -Exactly -ParameterFilter {
            $ComputerName -eq 'PC-014' -and
            $ArgumentList.Count -eq 6 -and
            $ArgumentList[0] -match 'function Get-PCHealthReport' -and
            $ArgumentList[1] -match 'WarningFreePercent' -and
            $ArgumentList[2] -match 'Uptime' -and
            $ArgumentList[3] -match '^\d+\.\d+\.\d+$' -and
            $ArgumentList[4] -eq 30 -and
            $ArgumentList[5] -eq $true
        }
    }

    It 'uses the current account unless a credential is given' {
        InModuleScope HelpdeskToolkit { $computer = 'PC-014'; Get-RemoteHealthReport -ComputerName $computer } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-Command -Times 1 -Exactly -ParameterFilter { -not $PSBoundParameters.ContainsKey('Credential') }
    }

    It 'passes a credential on' {
        $password = New-Object -TypeName System.Security.SecureString
        $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'CONTOSO\admin', $password
        InModuleScope HelpdeskToolkit -Parameters @{ Credential = $credential } { $computer = 'PC-014'; Get-RemoteHealthReport -ComputerName $computer -Credential $Credential } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-Command -Times 1 -Exactly -ParameterFilter { $Credential.UserName -eq 'CONTOSO\admin' }
    }

    It 'explains what is needed when the other computer cannot be reached' {
        Mock -ModuleName HelpdeskToolkit Invoke-Command { throw 'WinRM cannot complete the operation.' }
        { InModuleScope HelpdeskToolkit { $computer = 'PC-014'; Get-RemoteHealthReport -ComputerName $computer } } |
            Should -Throw '*could not be run on PC-014*WinRM cannot complete the operation*remoting must be enabled*'
    }
}
