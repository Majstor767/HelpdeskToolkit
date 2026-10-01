function Get-PCHealthReport {
    <#
    .SYNOPSIS
        Runs all health checks and returns the complete report as an object.
    .DESCRIPTION
        Runs every check category (system, specifications, hardware, software, event
        log, Windows Update, security, network, printers and services) and returns one
        report object with the run details, the count per status and all results.

        Nothing is printed, saved or opened. Use this command when the data is needed
        in a script; use Invoke-PCHealthCheck for the console summary and the saved
        report, and Show-PCHealthCheck for the window. Both of them call this command,
        so all three always show the same data.

        The command only reads information and does not need administrator rights;
        checks that do are skipped and marked "Requires admin".

        With -ComputerName the checks run on another computer through PowerShell
        remoting (WinRM) and its report is returned. Remoting must be enabled there
        and the account must be an administrator on it; nothing is installed on it.
    .PARAMETER ComputerName
        Name of another computer to check instead of this one.
    .PARAMETER Credential
        Account to use on the other computer. Without it the current account is used.
    .PARAMETER Days
        How many days of event log and crash history to analyze. The default is 7.
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
    .EXAMPLE
        Get-PCHealthReport -ComputerName PC-014 -Credential (Get-Credential)

        Runs the checks on the computer PC-014 with another account and returns its report.
    .OUTPUTS
        HelpdeskToolkit.HealthReport
        An object with the properties ToolVersion, ComputerName, GeneratedAt,
        DurationSeconds, IsElevated, EventLogDays, Score, Summary and Results.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.HealthReport')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [ValidateRange(1, 365)]
        [int]$Days = 7,

        [switch]$SkipNetwork
    )

    if ($ComputerName) {
        return Get-RemoteHealthReport -ComputerName $ComputerName -Credential $Credential -Days $Days -SkipNetwork:$SkipNetwork
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startedAt = Get-Date

    # Category name -> function that produces its results, with its parameters.
    $checks = [ordered]@{
        'System'         = @{ Command = 'Get-SystemHealth'; Parameters = @{} }
        'Specifications' = @{ Command = 'Get-ComputerSpecification'; Parameters = @{} }
        'Hardware'       = @{ Command = 'Get-HardwareHealth'; Parameters = @{} }
        'Software'       = @{ Command = 'Get-SoftwareHealth'; Parameters = @{ Days = $Days } }
        'Event Log'      = @{ Command = 'Get-EventLogHealth'; Parameters = @{ Days = $Days } }
        'Windows Update' = @{ Command = 'Get-WindowsUpdateHealth'; Parameters = @{} }
        'Security'       = @{ Command = 'Get-SecurityHealth'; Parameters = @{ Days = $Days } }
        'Network'        = @{ Command = 'Get-NetworkHealth'; Parameters = @{ SkipConnectivity = $SkipNetwork.IsPresent } }
        'Printers'       = @{ Command = 'Get-PrinterHealth'; Parameters = @{} }
        'Services'       = @{ Command = 'Get-ServiceHealth'; Parameters = @{} }
    }

    $activity = $script:ProgressActivity
    $completed = 0
    $results = foreach ($category in $checks.Keys) {
        $completed++
        # The percentage counts the category that is running as done once it finishes;
        # the step text ("step 3 of 10") is what the window shows next to the name.
        Write-Progress -Activity $activity -Status $category -CurrentOperation ('step {0} of {1}' -f $completed, $checks.Count) `
            -PercentComplete (($completed - 1) / $checks.Count * 100)

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
    $summary = Get-HealthSummary -Result $results

    [PSCustomObject]@{
        PSTypeName      = 'HelpdeskToolkit.HealthReport'
        ToolVersion     = Get-ToolVersion
        ComputerName    = $env:COMPUTERNAME
        GeneratedAt     = $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
        DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        IsElevated      = Test-IsAdministrator
        EventLogDays    = $Days
        Score           = Get-HealthScore -Summary $summary
        Summary         = $summary
        Results         = $results
    }
}
