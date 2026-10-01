<#
.SYNOPSIS
    Runs the health check from a script or a scheduled job and reports the result as an exit code.
.DESCRIPTION
    A wrapper around Invoke-PCHealthCheck for automation: monitoring systems, logon
    scripts, deployment tools and scheduled tasks decide by the exit code of a program
    what to do next.

    Exit code   Meaning
    0           no problems (every result is OK or Info)
    1           at least one Warning, no Critical
    2           at least one Critical
    3           the check itself could not run

    The report is saved like Invoke-PCHealthCheck saves it. The browser is not opened
    unless -Open is given, because an automated run has nobody to look at it.
.PARAMETER OutputPath
    Folder where the report is saved. Defaults to Documents\HelpdeskToolkit.
.PARAMETER Days
    How many days of event log history to analyze. The default is 7.
.PARAMETER Format
    Report format: Html (default), Json, Csv, Pdf, Both (HTML and JSON) or All.
.PARAMETER SkipNetwork
    Skip the connectivity tests (ping, DNS, HTTPS).
.PARAMETER ComputerName
    Name of another computer to check through PowerShell remoting.
.PARAMETER Quiet
    Do not print the summary; only the exit code tells the result.
.PARAMETER Open
    Open the HTML report in the browser when the check is done.
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Invoke-HealthCheck.ps1 -Format Json -Quiet

    Runs the check without output and saves a JSON report. The calling program reads
    the exit code.
.EXAMPLE
    .\Invoke-HealthCheck.ps1 -SkipNetwork; if ($LASTEXITCODE -ge 2) { 'This computer needs attention.' }

    Uses the exit code in a PowerShell script.
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [ValidateRange(1, 365)]
    [int]$Days = 7,

    [ValidateSet('Html', 'Json', 'Csv', 'Pdf', 'Both', 'All')]
    [string]$Format = 'Html',

    [switch]$SkipNetwork,

    [string]$ComputerName,

    [switch]$Quiet,

    [switch]$Open
)

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force -ErrorAction Stop

    $parameters = @{
        Days        = $Days
        Format      = $Format
        SkipNetwork = $SkipNetwork
        NoOpen      = -not $Open
        PassThru    = $true
        ErrorAction = 'Stop'
    }
    if ($OutputPath) {
        $parameters.OutputPath = $OutputPath
    }
    if ($ComputerName) {
        $parameters.ComputerName = $ComputerName
    }

    # The summary is written to the "information" stream; 6> $null silences it.
    $results = if ($Quiet) { @(Invoke-PCHealthCheck @parameters 6> $null) } else { @(Invoke-PCHealthCheck @parameters) }
}
catch {
    [Console]::Error.WriteLine('The health check could not run: {0}' -f $_.Exception.Message)
    exit 3
}

$statuses = @($results | ForEach-Object { $_.Status })
if ($statuses -contains 'Critical') {
    exit 2
}
if ($statuses -contains 'Warning') {
    exit 1
}
exit 0
