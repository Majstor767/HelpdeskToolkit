function Get-PCHealthReport {
    <#
    .SYNOPSIS
        Runs all health checks and returns the complete report as an object.
    .DESCRIPTION
        Runs every check category (system, specifications, hardware, software, event
        log, Windows Update, security, network, printers and services) and returns one
        report object with the run details, the count per status, all results and
        the time line of recent changes and failures.

        Nothing is printed, saved or opened. Use this command when the data is needed
        in a script; use Invoke-PCHealthCheck for the console summary and the saved
        report, and Show-PCHealthCheck for the window. Both of them call this command,
        so all three always show the same data.

        The categories do not depend on each other, so they are checked side by side,
        each in a runspace of its own; the check then takes about as long as its
        slowest category. Processor load and memory are measured before that starts,
        so the report shows the load of the computer and not the one of the check.

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
    .PARAMETER ThrottleLimit
        How many check categories run at the same time. The default, 0, lets the
        command choose: as many as the computer has logical processors, but at least
        two. With 1 the categories run one after the other, which takes about three
        times as long and keeps the load of the check itself as low as possible.
    .PARAMETER AllowCached
        Use what was measured earlier in this process for the things that take long
        and change slowly (the largest folders of a drive that is running full).
        The window uses this for the checks it repeats by itself, so they do not walk
        through the whole drive every few minutes.
    .PARAMETER SkipNetwork
        Skip everything that asks the internet: the connectivity tests (ping, DNS,
        HTTPS) and the search for newer versions of the installed programs. The
        adapter configuration is still reported.
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
        DurationSeconds, IsElevated, EventLogDays, Score, Summary, Results and
        Timeline (what happened on the computer lately, see Get-ChangeTimeline).
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

        [switch]$SkipNetwork,

        [ValidateRange(0, 64)]
        [int]$ThrottleLimit = 0,

        [switch]$AllowCached
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
        'Hardware'       = @{ Command = 'Get-HardwareHealth'; Parameters = @{ AllowCached = $AllowCached.IsPresent } }
        'Software'       = @{ Command = 'Get-SoftwareHealth'; Parameters = @{ Days = $Days; SkipUpdateCheck = $SkipNetwork.IsPresent } }
        'Event Log'      = @{ Command = 'Get-EventLogHealth'; Parameters = @{ Days = $Days } }
        'Windows Update' = @{ Command = 'Get-WindowsUpdateHealth'; Parameters = @{} }
        'Security'       = @{ Command = 'Get-SecurityHealth'; Parameters = @{ Days = $Days } }
        'Network'        = @{ Command = 'Get-NetworkHealth'; Parameters = @{ SkipConnectivity = $SkipNetwork.IsPresent } }
        'Printers'       = @{ Command = 'Get-PrinterHealth'; Parameters = @{} }
        'Services'       = @{ Command = 'Get-ServiceHealth'; Parameters = @{} }
    }

    # How many categories run at the same time. Side by side needs the module as files
    # on this computer, because every runspace loads it; a copy that only exists in
    # memory (see Get-RemoteHealthReport) runs them one after the other.
    $limit = $ThrottleLimit
    if ($limit -eq 0) {
        $limit = if ($script:CheckThrottleLimit) { [int]$script:CheckThrottleLimit } else { [math]::Min($checks.Count, [math]::Max(2, [Environment]::ProcessorCount)) }
    }
    $manifest = if ($script:ModuleRoot) { Join-Path -Path $script:ModuleRoot -ChildPath 'HelpdeskToolkit.psd1' } else { '' }
    $sideBySide = $limit -gt 1 -and $manifest -and (Test-Path -LiteralPath $manifest)

    $activity = $script:ProgressActivity
    $completed = 0
    $results = if ($sideBySide) {
        # Processor load and memory are measured first, while nothing else runs:
        # afterwards they would show the work of the check itself.
        Write-Progress -Activity $activity -Status 'Hardware' -CurrentOperation ('0 of {0} done' -f $checks.Count) -PercentComplete 0
        $checks['Hardware'].Parameters.LoadSample = Get-LoadSample

        $outcome = Invoke-ParallelCommand -Job $checks -ManifestPath $manifest -ThrottleLimit $limit -OnProgress {
            param($Done, $Total, $Open)
            # The names of the categories that are still running, and how many are done.
            if ($Done -lt $Total) {
                Write-Progress -Activity $activity -Status ($Open -join ', ') -CurrentOperation ('{0} of {1} done' -f $Done, $Total) `
                    -PercentComplete ([int]($Done / $Total * 100))
            }
        }

        foreach ($category in $checks.Keys) {
            $entry = $outcome[$category]
            # What a category found before it failed is part of the report.
            $entry.Output
            if ($entry.Error) {
                # One broken category must not take the whole report down with it.
                New-FailureResult -Category $category -Check 'Check execution' -ErrorRecord $entry.Error
            }
        }
    }
    else {
        foreach ($category in $checks.Keys) {
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
    }
    Write-Progress -Activity $activity -Completed
    $results = @($results)

    # What happened on the computer lately. It is no check with a verdict, so it is
    # kept next to the results; a time line that cannot be read must not fail the report.
    $timeline = @()
    try {
        $timeline = @(Get-ChangeTimeline -Days (Get-HealthThreshold).Timeline.Days | ForEach-Object {
                [PSCustomObject]@{
                    # As text, like GeneratedAt: it survives saving as JSON on every PowerShell version.
                    Time  = $_.Time.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture)
                    Level = $_.Level
                    Kind  = $_.Kind
                    Title = $_.Title
                    Count = $_.Count
                    # The error code of a problem; what it is looked up by.
                    Code  = if ($_.PSObject.Properties['Code']) { [string]$_.Code } else { '' }
                }
            })
    }
    catch {
        Write-Verbose "The time line could not be read: $($_.Exception.Message)"
    }

    $stopwatch.Stop()
    $summary = Get-HealthSummary -Result $results

    [PSCustomObject]@{
        PSTypeName      = 'HelpdeskToolkit.HealthReport'
        ToolVersion     = Get-ToolVersion
        ComputerName    = $env:COMPUTERNAME
        GeneratedAt     = $startedAt.ToString('yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        IsElevated      = Test-IsAdministrator
        EventLogDays    = $Days
        Score           = Get-HealthScore -Summary $summary
        Summary         = $summary
        Results         = $results
        Timeline        = $timeline
    }
}
