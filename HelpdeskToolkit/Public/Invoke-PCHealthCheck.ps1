function Invoke-PCHealthCheck {
    <#
    .SYNOPSIS
        Runs all health checks on the local computer and saves a report.
    .DESCRIPTION
        Runs every check category, prints a short colored summary to the console and
        saves the full result as a JSON file in the output folder.

        The command only reads information. The single thing it writes is the report
        file itself. It does not need administrator rights.
    .PARAMETER OutputPath
        Folder where the report is saved. It is created if it does not exist.
        Defaults to a HelpdeskToolkit folder inside the current user's Documents.
    .PARAMETER PassThru
        Also returns the check results as objects, so they can be filtered or
        processed further in the pipeline.
    .EXAMPLE
        Invoke-PCHealthCheck

        Runs all checks and saves the report to Documents\HelpdeskToolkit.
    .EXAMPLE
        Invoke-PCHealthCheck -OutputPath C:\Temp\Reports

        Saves the report to C:\Temp\Reports instead.
    .EXAMPLE
        Invoke-PCHealthCheck -PassThru | Where-Object Status -in 'Warning', 'Critical'

        Returns only the checks that need attention.
    .OUTPUTS
        None by default. HelpdeskToolkit.CheckResult objects when -PassThru is used.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'HelpdeskToolkit'),

        [switch]$PassThru
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $startedAt = Get-Date

    # Category name -> function that produces its results.
    $checks = [ordered]@{
        System = 'Get-SystemHealth'
    }

    $results = foreach ($category in $checks.Keys) {
        Write-Verbose "Running checks: $category"
        try {
            & $checks[$category] -ErrorAction Stop
        }
        catch {
            # One broken category must not take the whole report down with it.
            New-CheckResult -Category $category -Check 'Check execution' -Status Warning -Value 'Failed' `
                -Recommendation "The check could not be completed: $($_.Exception.Message)"
        }
    }
    $results = @($results)

    $stopwatch.Stop()

    $report = [PSCustomObject]@{
        ToolVersion     = $ExecutionContext.SessionState.Module.Version.ToString()
        ComputerName    = $env:COMPUTERNAME
        GeneratedAt     = $startedAt.ToString('yyyy-MM-dd HH:mm:ss')
        DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
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
