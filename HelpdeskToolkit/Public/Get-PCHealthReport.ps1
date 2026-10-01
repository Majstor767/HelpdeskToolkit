function Get-PCHealthReport {
    <#
    .SYNOPSIS
        Runs all health checks and returns the complete report as an object.
    .DESCRIPTION
        Runs every check category (system, specifications, hardware, event log, Windows
        Update, security, network and services) and returns one report object with the
        run details, the count per status and all results.

        Nothing is printed, saved or opened. Use this command when the data is needed
        in a script; use Invoke-PCHealthCheck for the console summary and the saved
        report, and Show-PCHealthCheck for the window. Both of them call this command,
        so all three always show the same data.

        The command only reads information and does not need administrator rights;
        checks that do are skipped and marked "Requires admin".
    .PARAMETER Days
        How many days of event log history to analyze. The default is 7.
    .PARAMETER SkipNetwork
        Skip the connectivity tests (ping, DNS, HTTPS). The adapter configuration is
        still reported.
    .EXAMPLE
        $report = Get-PCHealthReport
        $report.Summary

        Runs the checks and shows how many results have each status.
    .EXAMPLE
        (Get-PCHealthReport -Days 30 -SkipNetwork).Results | Where-Object Status -eq 'Critical'

        Analyzes 30 days of event logs, skips the connectivity tests and returns only
        the critical results.
    .OUTPUTS
        HelpdeskToolkit.HealthReport
        An object with the properties ToolVersion, ComputerName, GeneratedAt,
        DurationSeconds, IsElevated, EventLogDays, Summary and Results.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.HealthReport')]
    param(
        [ValidateRange(1, 365)]
        [int]$Days = 7,

        [switch]$SkipNetwork
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startedAt = Get-Date

    # Category name -> function that produces its results, with its parameters.
    $checks = [ordered]@{
        'System'         = @{ Command = 'Get-SystemHealth'; Parameters = @{} }
        'Specifications' = @{ Command = 'Get-ComputerSpecification'; Parameters = @{} }
        'Hardware'       = @{ Command = 'Get-HardwareHealth'; Parameters = @{} }
        'Event Log'      = @{ Command = 'Get-EventLogHealth'; Parameters = @{ Days = $Days } }
        'Windows Update' = @{ Command = 'Get-WindowsUpdateHealth'; Parameters = @{} }
        'Security'       = @{ Command = 'Get-SecurityHealth'; Parameters = @{} }
        'Network'        = @{ Command = 'Get-NetworkHealth'; Parameters = @{ SkipConnectivity = $SkipNetwork.IsPresent } }
        'Services'       = @{ Command = 'Get-ServiceHealth'; Parameters = @{} }
    }

    $activity = $script:ProgressActivity
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

    [PSCustomObject]@{
        PSTypeName      = 'HelpdeskToolkit.HealthReport'
        ToolVersion     = $ExecutionContext.SessionState.Module.Version.ToString()
        ComputerName    = $env:COMPUTERNAME
        GeneratedAt     = $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
        DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        IsElevated      = Test-IsAdministrator
        EventLogDays    = $Days
        Summary         = Get-HealthSummary -Result $results
        Results         = $results
    }
}
