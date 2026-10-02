<#
.SYNOPSIS
    Puts together a folder that can be handed to somebody who is to try the application out.
.DESCRIPTION
    Builds the release (tools\Build-Release.ps1) and arranges it for a tester:

        dist\HelpdeskToolkit-test-<version>\
            PROCITAJ-ME.txt                      what it is, how to start it, what to try,
                                                 what feedback is wanted (docs\tester)
            HelpdeskToolkit-Setup-<version>.exe  the installer
            Bez-instalacije\                     the portable copy, already unpacked:
                                                 double-click Start-HelpdeskToolkit.cmd
            SHA256SUMS.txt                       checksums of the two release files

    The folder is also packed into dist\HelpdeskToolkit-test-<version>.zip, which is
    easier to send. The instructions get a line with the version, the date and the
    commit the package was built from, so feedback can be matched to the code.

    The dist folder is not part of the repository.
.PARAMETER OutputPath
    Folder for the package. Defaults to the dist folder of the repository.
.PARAMETER SkipBuild
    Use the release files that are in the output folder already instead of building them.
.EXAMPLE
    .\tools\New-TestPackage.ps1

    Builds the release and writes dist\HelpdeskToolkit-test-<version> and its ZIP.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Build script that writes generated files.')]
[CmdletBinding()]
param(
    [string]$OutputPath,

    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

# The default is set here and not in the param block: Windows PowerShell 5.1 does not
# know $PSScriptRoot yet while it evaluates parameter defaults of a script run with -File.
$root = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $root -ChildPath 'dist'
}
$outputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

if (-not $SkipBuild) {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Build-Release.ps1') -OutputPath $outputFolder | Out-Null
}

$version = (Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1')).ModuleVersion
$installer = Join-Path -Path $outputFolder -ChildPath ('HelpdeskToolkit-Setup-{0}.exe' -f $version)
$portable = Join-Path -Path $outputFolder -ChildPath ('HelpdeskToolkit-{0}.zip' -f $version)
$checksums = Join-Path -Path $outputFolder -ChildPath 'SHA256SUMS.txt'
foreach ($file in $installer, $portable, $checksums) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "The release file $file is missing. Run the script without -SkipBuild."
    }
}

$name = 'HelpdeskToolkit-test-{0}' -f $version
$package = Join-Path -Path $outputFolder -ChildPath $name
$packageZip = '{0}.zip' -f $package

# A package of an earlier run is replaced as a whole.
foreach ($old in $package, $packageZip) {
    if (Test-Path -LiteralPath $old) {
        Remove-Item -LiteralPath $old -Recurse -Force
    }
}
New-Item -Path $package -ItemType Directory | Out-Null

Copy-Item -LiteralPath $installer -Destination $package
Copy-Item -LiteralPath $checksums -Destination $package
Expand-Archive -LiteralPath $portable -DestinationPath (Join-Path -Path $package -ChildPath 'Bez-instalacije')

# The instructions, with a line that says exactly which build this is. They are
# written as UTF-8 with a byte order mark, so Notepad shows the Croatian letters on
# every Windows version.
$readme = [System.IO.File]::ReadAllText((Join-Path -Path $root -ChildPath 'docs\tester\PROCITAJ-ME.txt'), [System.Text.Encoding]::UTF8)
$commit = ''
try {
    $commit = (& git -C $root rev-parse --short HEAD 2>$null)
}
catch {
    Write-Verbose "The commit could not be read: $($_.Exception.Message)"
}
$build = 'Verzija {0}, slozeno {1:yyyy-MM-dd}' -f $version, (Get-Date)
if ($commit) {
    $build = '{0}, commit {1}' -f $build, $commit
}
$readme = $readme.TrimEnd() + "`r`n`r`n`r`n" + $build + "`r`n"
$readme = $readme -replace "`r?`n", "`r`n"
[System.IO.File]::WriteAllText((Join-Path -Path $package -ChildPath 'PROCITAJ-ME.txt'), $readme, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true))

Compress-Archive -Path $package -DestinationPath $packageZip

Write-Output $package
Write-Output $packageZip
