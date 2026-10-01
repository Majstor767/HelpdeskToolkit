<#
.SYNOPSIS
    Builds the files of a release: the installer, the portable ZIP and their checksums.
.DESCRIPTION
    Produces three files in the output folder (dist by default):

    - HelpdeskToolkit-Setup-<version>.exe  installer built with Inno Setup
    - HelpdeskToolkit-<version>.zip        portable copy: unzip and double-click
    - SHA256SUMS.txt                       checksums to verify a download

    The version is read from the module manifest, so it is defined in one place only.
    Both packages are built from the same staging folder and therefore always contain
    exactly the same files.

    The script is used locally and by the release workflow on GitHub.
.PARAMETER OutputPath
    Folder for the release files. It is created when needed. Defaults to the dist
    folder of the repository.
.PARAMETER ExpectedVersion
    Version the build must have, with or without a leading "v" (for example the git
    tag v1.0.0). The build stops when it differs from the version in the manifest,
    which prevents publishing a release under the wrong number.
.PARAMETER SkipInstaller
    Only build the ZIP. Use this on a computer without Inno Setup.
.EXAMPLE
    .\tools\Build-Release.ps1

    Builds the installer and the ZIP into the dist folder.
.EXAMPLE
    .\tools\Build-Release.ps1 -ExpectedVersion v1.0.0

    Builds the release and fails if the manifest does not say version 1.0.0.
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [string]$ExpectedVersion,

    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'

# The default is set here and not in the param block: Windows PowerShell 5.1 does not
# know $PSScriptRoot yet while it evaluates parameter defaults of a script run with -File.
$root = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $root -ChildPath 'dist'
}
$manifest = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1')
$version = $manifest.ModuleVersion

if ($ExpectedVersion -and ($ExpectedVersion -replace '^v', '') -ne $version) {
    throw "The release is tagged $ExpectedVersion but the module manifest says version $version. Update ModuleVersion in HelpdeskToolkit.psd1 before tagging."
}

$outputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (-not (Test-Path -LiteralPath $outputFolder)) {
    New-Item -Path $outputFolder -ItemType Directory -Force | Out-Null
}

# Staging folder: exactly the files a user receives.
$staging = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('HelpdeskToolkit-build-{0}' -f [guid]::NewGuid())
New-Item -Path $staging -ItemType Directory | Out-Null

try {
    Copy-Item -Path (Join-Path -Path $root -ChildPath 'HelpdeskToolkit') -Destination $staging -Recurse
    foreach ($file in 'Start-HelpdeskToolkit.cmd', 'Start-HelpdeskToolkit.ps1', 'LICENSE', 'README.md', 'README.hr.md') {
        $source = Join-Path -Path $root -ChildPath $file
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $staging
        }
    }

    # Portable ZIP
    $zipPath = Join-Path -Path $outputFolder -ChildPath ('HelpdeskToolkit-{0}.zip' -f $version)
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath
    }
    Compress-Archive -Path (Join-Path -Path $staging -ChildPath '*') -DestinationPath $zipPath
    $files = @($zipPath)
    Write-Output ('Built {0}' -f $zipPath)

    # Installer
    if (-not $SkipInstaller) {
        # Inno Setup can be on the PATH, installed for all users or only for this user.
        $candidates = @((Get-Command -Name 'ISCC.exe' -ErrorAction SilentlyContinue).Source)
        foreach ($folder in "$env:LOCALAPPDATA\Programs", ${env:ProgramFiles(x86)}, $env:ProgramFiles) {
            if ($folder) {
                $candidates += Join-Path -Path $folder -ChildPath 'Inno Setup 6\ISCC.exe'
            }
        }
        $compiler = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

        if (-not $compiler) {
            throw 'Inno Setup (ISCC.exe) was not found. Install it with "winget install JRSoftware.InnoSetup" or build only the ZIP with -SkipInstaller.'
        }

        $installerScript = Join-Path -Path $root -ChildPath 'installer\HelpdeskToolkit.iss'
        & $compiler "/DAppVersion=$version" "/DSourceDir=$staging" "/O$outputFolder" '/Q' $installerScript
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup failed with exit code $LASTEXITCODE."
        }

        $setupPath = Join-Path -Path $outputFolder -ChildPath ('HelpdeskToolkit-Setup-{0}.exe' -f $version)
        $files += $setupPath
        Write-Output ('Built {0}' -f $setupPath)
    }

    # Checksums, in the format the common sha256sum tools use: "<hash>  <file name>"
    $sums = foreach ($file in $files) {
        '{0}  {1}' -f (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLower(), (Split-Path -Path $file -Leaf)
    }
    $sumsPath = Join-Path -Path $outputFolder -ChildPath 'SHA256SUMS.txt'
    [System.IO.File]::WriteAllLines($sumsPath, [string[]]$sums)
    Write-Output ('Built {0}' -f $sumsPath)
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
