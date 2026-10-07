# Shared helpers for the test files. Dot-source this file in BeforeAll.

function Import-TestModule {
    <#
    .SYNOPSIS
        Imports a fresh copy of the module under test.
    #>
    # The functions are loaded file by file, so a failing test names the file and the
    # line, and the code coverage can be measured. (The application loads them as one
    # block, which is faster; Module.Tests.ps1 checks that both ways give the same.)
    $env:HELPDESKTOOLKIT_LOAD_FILES = '1'
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '..\HelpdeskToolkit\HelpdeskToolkit.psd1'
    Import-Module -Name $manifest -Force

    # The application keeps settings and a history of reports in a folder of the user.
    # The tests must never read or write the real one, so it is replaced with a folder
    # that Pester removes after the test file has run.
    $folder = Join-Path -Path $TestDrive -ChildPath 'AppData'
    InModuleScope HelpdeskToolkit -Parameters @{ Folder = $folder } {
        $script:AppDataRoot = $Folder
        # The categories of a check run one after the other in the session of the test:
        # run side by side in runspaces of their own, they would not see the mocks.
        $script:CheckThrottleLimit = 1
    }
}

function Set-TestThreshold {
    <#
    .SYNOPSIS
        Replaces the thresholds of the loaded module with fixed test values.
    .DESCRIPTION
        The tests must not break when somebody tunes Config\Thresholds.psd1, so they
        run against their own limits. Get-HealthThreshold caches the configuration in
        a module variable; setting that variable injects the test values without a mock.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test helper that changes a variable of the module under test only.')]
    param()

    InModuleScope HelpdeskToolkit {
        $script:Thresholds = @{
            # End-of-support dates relative to today, so the tests never go out of date:
            # release 90H1 ended, 90H2 ends soon, 91H1 is supported for a long time.
            WindowsSupport = @{
                Windows10End         = (Get-Date).AddDays(-100).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
                HomePro              = @{
                    '90H1' = (Get-Date).AddDays(-10).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
                    '90H2' = (Get-Date).AddDays(30).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
                    '91H1' = (Get-Date).AddDays(400).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
                }
                Enterprise           = @{
                    '90H1' = (Get-Date).AddDays(355).ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture)
                }
                WarningDaysBeforeEnd = 90
            }
            Stability     = @{ WarningIndex = 5; CriticalIndex = 3; Typical = 'typical stability' }
            Cleanup       = @{ TempWarningGb = 5; RecycleBinWarningGb = 10; SystemTempWarningGb = 5; TimeoutMs = 3000; ProfileTimeoutMs = 5000; LargestFolderBudgetMs = 3000; LargestFolderCacheMinutes = 30; ProgramSizeBudgetMs = 2000; UsageProgramCount = 3; UsageFolderCount = 2 }
            Boot          = @{ WarningSeconds = 120; Typical = 'typical boot'; StaleDays = 30; DelayWarningSeconds = 10 }
            DriveDetail   = @{ TemperatureWarning = 60; TemperatureCritical = 70; TypicalTemperature = '30 - 50'; WearWarningPercent = 80; WearCriticalPercent = 95 }
            SignIn        = @{ FailedWarningAbove = 20; TypicalFailed = 'typical failed sign-ins' }
            PageFile      = @{ WarningPercent = 80; Typical = 'typical page file' }
            Uptime        = @{ WarningDays = 7; Typical = 'typical uptime' }
            Startup       = @{ WarningProgramCount = 15; Typical = 'typical startup' }
            Cpu           = @{ WarningPercent = 85; CriticalPercent = 95; Typical = 'typical cpu' }
            Memory        = @{ WarningPercent = 85; CriticalPercent = 95; Typical = 'typical memory' }
            Disk          = @{ WarningFreePercent = 15; CriticalFreePercent = 5; Typical = 'typical disk' }
            Battery       = @{ WarningPercent = 20; CriticalPercent = 10; HealthWarningPercent = 60; HealthCriticalPercent = 40; TypicalHealth = 'typical battery health' }
            Drivers       = @{ OldYears = 5; Classes = @('DISPLAY', 'NET') }
            Ports         = @{ Risky = @{ 23 = 'Telnet' } }
            EventLog      = @{
                CriticalEventWarningAbove      = 0
                CriticalEventCriticalAbove     = 4
                TypicalCriticalEvents          = 'typical critical'
                ErrorEventWarningAbove         = 50
                TypicalErrorEvents             = 'typical errors'
                UnexpectedShutdownWarningAbove = 0
                TypicalUnexpectedShutdowns     = 'typical shutdowns'
                DiskErrorWarningAbove          = 0
                HardwareErrorWarningAbove      = 0
                BlueScreenWarningAbove         = 0
                TypicalBlueScreens             = 'typical blue screens'
            }
            Software      = @{ RecentDays = 30; CrashWarningAbove = 5; TypicalCrashes = 'typical crashes'; UpdateWarningAbove = 3; TypicalUpdates = 'typical updates'; UpdateTimeoutSeconds = 5 }
            Outlook       = @{ WarningGb = 25; CriticalGb = 45; Typical = 'typical mailbox' }
            Privacy       = @{ RecentDays = 30 }
            Bios          = @{ OldYears = 4 }
            Timeline      = @{ Days = 30 }
            WindowsUpdate = @{ WarningDaysSinceLastUpdate = 45; Typical = 'typical update'; FailedDays = 30 }
            Defender      = @{
                SignatureWarningDays  = 3
                SignatureCriticalDays = 7
                Typical               = 'typical definitions'
                ScanWarningDays       = 14
                TypicalScan           = 'typical scan'
            }
            Printers      = @{ StuckJobMinutes = 10 }
            Network       = @{
                PingTarget          = '192.0.2.1'
                DnsTestName         = 'test.example'
                HttpsTestUrl        = 'https://test.example'
                PingWarningMs       = 150
                TypicalGatewayPing  = 'typical gateway'
                TypicalInternetPing = 'typical internet'
                ClockWarningSeconds = 120
                TypicalClock        = 'typical clock'
                WifiSignalWarningPercent = 40
                TypicalWifiSignal   = 'typical wifi'
            }
            Score         = @{ CriticalPenalty = 15; WarningPenalty = 4 }
            Monitor       = @{
                CpuAlertPercent     = 90
                MemoryAlertPercent  = 90
                DiskAlertPercent    = 90
                AlertSamples        = 3
                GpuTemperatureAlert = 85
                # Status dots: the average of three measurements is judged; a rise is
                # looked for in six and projected six ahead.
                StatusSamples       = 3
                GpuWarningPercent   = 95
                NearMarginPercent   = 10
                GpuTemperatureNear  = 75
                TrendSamples        = 6
                TrendAheadSamples   = 6
                TrendMinimumPercent = 50
                DetailRefreshSeconds = 10
                LatencyTimeoutMs      = 1000
                LatencyWarningMs      = 150
                LatencyLossPercent    = 5
                LatencySamples        = 6
            }
            Services      = @('Spooler', 'Dhcp', 'BITS', 'Missing')
        }
    }
}

function New-TestResult {
    <#
    .SYNOPSIS
        Builds a check result object without calling the module (for use in mock bodies).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test helper that only builds objects in memory.')]
    param(
        [string]$Category = 'System',
        [string]$Check = 'Test check',
        [string]$Status = 'OK',
        [string]$Value = 'value',
        [string]$Description = '',
        [string[]]$Details = @(),
        [string]$Allowed = '',
        [string]$Typical = '',
        [string]$Recommendation = ''
    )

    [PSCustomObject]@{
        PSTypeName     = 'HelpdeskToolkit.CheckResult'
        Category       = $Category
        Check          = $Check
        Description    = $Description
        Status         = $Status
        Value          = $Value
        Details        = @($Details | Where-Object { $_ })
        Allowed        = $Allowed
        Typical        = $Typical
        Recommendation = $Recommendation
    }
}

function New-TestReport {
    <#
    .SYNOPSIS
        Builds a report object like the one Invoke-PCHealthCheck creates.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test helper that only builds objects in memory.')]
    param(
        [Parameter(Mandatory)]
        [object[]]$Result,

        [bool]$IsElevated = $false
    )

    $summary = [ordered]@{ OK = 0; Warning = 0; Critical = 0; Info = 0 }
    foreach ($item in $Result) {
        $summary[$item.Status]++
    }

    [PSCustomObject]@{
        ToolVersion     = '9.9.9'
        ComputerName    = 'TEST-PC-01'
        GeneratedAt     = '2026-01-15 10:30:00'
        DurationSeconds = 1.5
        IsElevated      = $IsElevated
        EventLogDays    = 7
        Score           = [math]::Max(0, 100 - 15 * $summary.Critical - 4 * $summary.Warning)
        Summary         = $summary
        Results         = @($Result)
    }
}

function New-TestErrorRecord {
    <#
    .SYNOPSIS
        Builds an ErrorRecord with a chosen error id, like the ones cmdlets throw.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test helper that only builds objects in memory.')]
    param(
        [string]$Message = 'Test error',
        [string]$ErrorId = 'TestError',
        [System.Exception]$Exception
    )

    if (-not $Exception) {
        $Exception = New-Object -TypeName System.Exception -ArgumentList $Message
    }

    New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $Exception, $ErrorId,
        ([System.Management.Automation.ErrorCategory]::NotSpecified), $null
}

function New-TestEvent {
    <#
    .SYNOPSIS
        Builds fake event log entries, for example: New-TestEvent -Level 2 -Source 'Disk' -Count 3
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Test helper that only builds objects in memory.')]
    param(
        # 1 = Critical, 2 = Error
        [int]$Level = 2,

        [string]$Source = 'TestSource',

        [int]$Count = 1,

        # For crash events: the name of the program that crashed (first event property).
        [string]$Program = '',

        # The number of the event.
        [int]$Id = 1000
    )

    1..$Count | ForEach-Object {
        [PSCustomObject]@{
            Level        = $Level
            ProviderName = $Source
            Id           = $Id
            Properties   = @([PSCustomObject]@{ Value = $Program })
        }
    }
}
