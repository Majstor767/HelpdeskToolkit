function Invoke-PCHealthCheck {
    <#
    .SYNOPSIS
        Runs all health checks on the local computer and saves a report.
    .DESCRIPTION
        Runs every check category (system, hardware, event log, Windows Update,
        security, network and services), prints a short colored summary to the
        console and saves the full result as a JSON file in the output folder.

        The command only reads information. The single thing it writes is the report
        file itself. It does not need administrator rights; checks that do are
        skipped and marked "Requires admin" in the report.
    .PARAMETER OutputPath
        Folder where the report is saved. It is created if it does not exist.
        Defaults to a HelpdeskToolkit folder inside the current user's Documents.
    .PARAMETER Days
        How many days of event log history to analyze. The default is 7.
    .PARAMETER SkipNetwork
        Skip the connectivity tests (ping, DNS, HTTPS). The adapter configuration is
        still reported. Use it on computers that are offline on purpose.
    .PARAMETER PassThru
        Also returns the check results as objects, so they can be filtered or
        processed further in the pipeline.
    .EXAMPLE
        Invoke-PCHealthCheck

        Runs all checks and saves the report to Documents\HelpdeskToolkit.
    .EXAMPLE
        Invoke-PCHealthCheck -OutputPath C:\Temp\Reports -Days 30

        Analyzes 30 days of event logs and saves the report to C:\Temp\Reports.
    .EXAMPLE
        Invoke-PCHealthCheck -SkipNetwork -PassThru | Where-Object Status -in 'Warning', 'Critical'

        Skips the connectivity tests and returns only the checks that need attention.
    .OUTPUTS
        None by default. HelpdeskToolkit.CheckResult objects when -PassThru is used.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'HelpdeskToolkit'),

        [ValidateRange(1, 365)]
        [int]$Days = 7,

        [switch]$SkipNetwork,

        [switch]$PassThru
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startedAt = Get-Date

    # Category name -> function that produces its results, with its parameters.
    $checks = [ordered]@{
        'System'         = @{ Command = 'Get-SystemHealth'; Parameters = @{} }
        'Hardware'       = @{ Command = 'Get-HardwareHealth'; Parameters = @{} }
        'Event Log'      = @{ Command = 'Get-EventLogHealth'; Parameters = @{ Days = $Days } }
        'Windows Update' = @{ Command = 'Get-WindowsUpdateHealth'; Parameters = @{} }
        'Security'       = @{ Command = 'Get-SecurityHealth'; Parameters = @{} }
        'Network'        = @{ Command = 'Get-NetworkHealth'; Parameters = @{ SkipConnectivity = $SkipNetwork.IsPresent } }
        'Services'       = @{ Command = 'Get-ServiceHealth'; Parameters = @{} }
    }

    $activity = 'PC Health Check'
    $completed = 0
    $results = foreach ($category in $checks.Keys) {
        Write-Progress -Activity $activity -Status $category -PercentComplete ($completed / $checks.Count * 100)
        $completed++

        $command = $checks[$category].Command
        $parameters = $checks[$category].Parameters
        try {
            & $command @parameters -ErrorAction Stop
        }
        catch {
            # One broken category must not take the whole report down with it.
            New-FailureResult -Category $category -Check 'Check execution' -ErrorRecord $_
        }
    }
    Write-Progress -Activity $activity -Completed
    $results = @($results)

    $stopwatch.Stop()

    $report = [PSCustomObject]@{
        ToolVersion     = $ExecutionContext.SessionState.Module.Version.ToString()
        ComputerName    = $env:COMPUTERNAME
        GeneratedAt     = $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
        DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        IsElevated      = Test-IsAdministrator
        EventLogDays    = $Days
        Summary         = Get-HealthSummary -Result $results
        Results         = $results
    }

    $outputFolder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
    if (-not (Test-Path -LiteralPath $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
    }

    $baseName = 'PCHealth_{0}_{1:yyyyMMdd-HHmmss}' -f $env:COMPUTERNAME, $startedAt
    $jsonPath = Export-HealthReportJson -Report $report -Path (Join-Path -Path $outputFolder -ChildPath "$baseName.json")

    Write-HealthSummary -Report $report -ReportPath $jsonPath

    if ($PassThru) {
        $results
    }
}
