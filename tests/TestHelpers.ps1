# Shared helpers for the test files. Dot-source this file in BeforeAll.

function Import-TestModule {
    <#
    .SYNOPSIS
        Imports a fresh copy of the module under test.
    #>
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '..\HelpdeskToolkit\HelpdeskToolkit.psd1'
    Import-Module -Name $manifest -Force
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
            Uptime        = @{ WarningDays = 7; Typical = 'typical uptime' }
            Startup       = @{ WarningProgramCount = 15; Typical = 'typical startup' }
            Cpu           = @{ WarningPercent = 85; CriticalPercent = 95; Typical = 'typical cpu' }
            Memory        = @{ WarningPercent = 85; CriticalPercent = 95; Typical = 'typical memory' }
            Disk          = @{ WarningFreePercent = 15; CriticalFreePercent = 5; Typical = 'typical disk' }
            Battery       = @{ WarningPercent = 20; CriticalPercent = 10 }
            EventLog      = @{
                CriticalEventWarningAbove      = 0
                CriticalEventCriticalAbove     = 4
                TypicalCriticalEvents          = 'typical critical'
                ErrorEventWarningAbove         = 50
                TypicalErrorEvents             = 'typical errors'
                UnexpectedShutdownWarningAbove = 0
                TypicalUnexpectedShutdowns     = 'typical shutdowns'
            }
            WindowsUpdate = @{ WarningDaysSinceLastUpdate = 45; Typical = 'typical update' }
            Defender      = @{ SignatureWarningDays = 3; SignatureCriticalDays = 7; Typical = 'typical definitions' }
            Network       = @{
                PingTarget          = '192.0.2.1'
                DnsTestName         = 'test.example'
                HttpsTestUrl        = 'https://test.example'
                PingWarningMs       = 150
                TypicalGatewayPing  = 'typical gateway'
                TypicalInternetPing = 'typical internet'
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

        [int]$Count = 1
    )

    1..$Count | ForEach-Object { [PSCustomObject]@{ Level = $Level; ProviderName = $Source } }
}
