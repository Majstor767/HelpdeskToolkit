function Invoke-PCHealthCheck {
    <#
    .SYNOPSIS
        Runs all health checks on the local computer and saves a report.
    .DESCRIPTION
        Runs every check category (system, specifications, hardware, software, event log,
        Windows Update, security, network, printers and services), prints a short colored summary to the
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

    $report = Get-PCHealthReport -Days $Days -SkipNetwork:$SkipNetwork
    $results = @($report.Results)

    $outputFolder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $basePath = Join-Path -Path $outputFolder -ChildPath (Get-ReportFileName -Report $report)
    if (-not (Test-Path -LiteralPath $outputFolder)) {
        New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
    }

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
        Open-HealthReport -Path $htmlPath
    }

    if ($PassThru) {
        foreach ($result in $results) {
            $result
        }
    }
}
