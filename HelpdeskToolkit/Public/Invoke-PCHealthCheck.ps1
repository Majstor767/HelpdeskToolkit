function Invoke-PCHealthCheck {
    <#
    .SYNOPSIS
        Runs all health checks on the local computer and saves a report.
    .DESCRIPTION
        Runs every check category (system, specifications, hardware, event log, Windows
        Update, security, network and services), prints a short colored summary to the
        console, saves the full result as an HTML and/or JSON report and opens the
        HTML report in the default browser.

        The command only reads information. The single thing it writes is the report
        file itself. It does not need administrator rights; checks that do are
        skipped and marked "Requires admin" in the report.
    .PARAMETER OutputPath
        Folder where the report is saved. It is created if it does not exist.
        Defaults to a HelpdeskToolkit folder inside the current user's Documents.
    .PARAMETER Days
        How many days of event log history to analyze. The default is 7.
    .PARAMETER Format
        Report format: Html (default), Json or Both. The HTML report is a single
        self-contained file meant for people; JSON is meant for further processing.
    .PARAMETER SkipNetwork
        Skip the connectivity tests (ping, DNS, HTTPS). The adapter configuration is
        still reported. Use it on computers that are offline on purpose.
    .PARAMETER NoOpen
        Do not open the HTML report in the browser after it is saved.
    .PARAMETER PassThru
        Also returns the check results as objects, so they can be filtered or
        processed further in the pipeline.
    .EXAMPLE
        Invoke-PCHealthCheck

        Runs all checks, saves an HTML report to Documents\HelpdeskToolkit and opens it.
    .EXAMPLE
        Invoke-PCHealthCheck -OutputPath C:\Temp\Reports -Days 30 -Format Both

        Analyzes 30 days of event logs and saves an HTML and a JSON report to
        C:\Temp\Reports.
    .EXAMPLE
        Invoke-PCHealthCheck -Format Json -SkipNetwork

        Saves only a JSON report and skips the connectivity tests.
    .EXAMPLE
        Invoke-PCHealthCheck -NoOpen -PassThru | Where-Object Status -in 'Warning', 'Critical'

        Does not open the browser and returns only the checks that need attention.
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

        [ValidateSet('Html', 'Json', 'Both')]
        [string]$Format = 'Html',

        [switch]$SkipNetwork,

        [switch]$NoOpen,

        [switch]$PassThru
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

    $basePath = Join-Path -Path $outputFolder -ChildPath ('PCHealth_{0}_{1:yyyyMMdd-HHmmss}' -f $env:COMPUTERNAME, $startedAt)
    $reportPaths = @()
    $htmlPath = $null

    if ($Format -in 'Html', 'Both') {
        $htmlPath = Export-HealthReportHtml -Report $report -Path "$basePath.html"
        $reportPaths += $htmlPath
    }
    if ($Format -in 'Json', 'Both') {
        $reportPaths += Export-HealthReportJson -Report $report -Path "$basePath.json"
    }

    Write-HealthSummary -Report $report -ReportPath $reportPaths

    if ($htmlPath -and -not $NoOpen) {
        try {
            # Opens the report with the default application for .html files (the browser).
            Invoke-Item -LiteralPath $htmlPath -ErrorAction Stop
        }
        catch {
            Write-Warning "The report was saved but could not be opened automatically: $($_.Exception.Message)"
        }
    }

    if ($PassThru) {
        $results
    }
}
