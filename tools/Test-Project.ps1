<#
.SYNOPSIS
    Runs the quality checks of the project: PSScriptAnalyzer and the Pester tests.
.DESCRIPTION
    The same script is used on a developer machine and by the GitHub Actions workflow,
    so "it passes locally" and "it passes in CI" mean the same thing.

    1. PSScriptAnalyzer checks the module and the tools with all default rules; any
       finding fails the run.
    2. Pester runs every test in the tests folder. The tests use mocks, so the result
       does not depend on the state of the computer they run on.

    The script ends with exit code 1 when either step fails.
.PARAMETER SkipAnalyzer
    Only run the tests.
.PARAMETER Coverage
    Also measure how much of the module code the tests execute and print the
    percentage. The detailed result is written to reports\coverage.xml.
.EXAMPLE
    .\tools\Test-Project.ps1

    Runs PSScriptAnalyzer and all tests.
.EXAMPLE
    .\tools\Test-Project.ps1 -Coverage

    Additionally reports the code coverage.
#>
[CmdletBinding()]
param(
    [switch]$SkipAnalyzer,

    [switch]$Coverage
)

$root = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path -Path $root -ChildPath 'HelpdeskToolkit'
$toolsPath = Join-Path -Path $root -ChildPath 'tools'
$testsPath = Join-Path -Path $root -ChildPath 'tests'
$failed = $false

if (-not $SkipAnalyzer) {
    Write-Output 'Running PSScriptAnalyzer ...'

    $findings = @(Invoke-ScriptAnalyzer -Path $modulePath -Recurse)
    $findings += @(Invoke-ScriptAnalyzer -Path $toolsPath -Recurse)

    # Scripts in the repository root, such as the launcher.
    foreach ($script in Get-ChildItem -Path $root -Filter '*.ps1' -File) {
        $findings += @(Invoke-ScriptAnalyzer -Path $script.FullName)
    }

    # Pester runs BeforeAll and It blocks in separate scopes that the analyzer cannot
    # follow, so every variable that is set in BeforeAll and used in a test is reported
    # as "assigned but never used". That one rule is switched off for the tests only.
    $findings += @(Invoke-ScriptAnalyzer -Path $testsPath -Recurse -ExcludeRule PSUseDeclaredVarsMoreThanAssignments)

    if ($findings.Count -gt 0) {
        $findings | Format-Table -Property Severity, RuleName, ScriptName, Line, Message -AutoSize -Wrap | Out-String -Width 200 | Write-Output
        Write-Output ('PSScriptAnalyzer: {0} finding(s).' -f $findings.Count)
        $failed = $true
    }
    else {
        Write-Output 'PSScriptAnalyzer: no findings.'
    }
}

Write-Output 'Running Pester ...'

$configuration = New-PesterConfiguration
$configuration.Run.Path = $testsPath
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Normal'

if ($Coverage) {
    $reportFolder = Join-Path -Path $root -ChildPath 'reports'
    if (-not (Test-Path -LiteralPath $reportFolder)) {
        New-Item -Path $reportFolder -ItemType Directory | Out-Null
    }
    $configuration.CodeCoverage.Enabled = $true
    $configuration.CodeCoverage.Path = $modulePath
    $configuration.CodeCoverage.OutputPath = Join-Path -Path $reportFolder -ChildPath 'coverage.xml'
}

$result = Invoke-Pester -Configuration $configuration

if ($Coverage) {
    Write-Output ('Code coverage: {0:N1} %' -f $result.CodeCoverage.CoveragePercent)
}

if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') {
    $failed = $true
}

if ($failed) {
    Write-Output 'Quality checks FAILED.'
    exit 1
}

Write-Output 'Quality checks passed.'
