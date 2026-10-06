# Tests for the packaging: the build script, the installer script, the launcher and
# the icon. The installer itself is not built here, because that needs Inno Setup;
# the release workflow builds it.

BeforeAll {
    $root = Split-Path -Path $PSScriptRoot -Parent
    $buildScript = Join-Path -Path $root -ChildPath 'tools\Build-Release.ps1'
    $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1')
    $version = $manifest.ModuleVersion
}

Describe 'Build-Release.ps1' {
    Context 'building the portable ZIP' {
        BeforeAll {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $output = Join-Path -Path $TestDrive -ChildPath 'dist'
            & $buildScript -OutputPath $output -SkipInstaller | Out-Null

            $zipPath = Join-Path -Path $output -ChildPath "HelpdeskToolkit-$version.zip"
            $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            $entries = $archive.Entries.FullName -replace '\\', '/'
            $archive.Dispose()
        }

        It 'names the ZIP after the version in the module manifest' {
            $zipPath | Should -Exist
        }

        It 'packs <_>' -ForEach @(
            'HelpdeskToolkit/HelpdeskToolkit.psd1'
            'HelpdeskToolkit/HelpdeskToolkit.psm1'
            'HelpdeskToolkit/Config/Thresholds.psd1'
            'HelpdeskToolkit/Assets/MainWindow.xaml'
            'HelpdeskToolkit/Assets/HelpdeskToolkit.ico'
            'HelpdeskToolkit/Public/Show-PCHealthCheck.ps1'
            'Start-HelpdeskToolkit.cmd'
            'Start-HelpdeskToolkit.ps1'
            'Invoke-HealthCheck.ps1'
            'LICENSE'
        ) {
            $entries | Should -Contain $_
        }

        It 'leaves out tests, tools and reports' {
            $entries | Where-Object { $_ -match '^(tests|tools|reports|docs|\.github)/' } | Should -BeNullOrEmpty
        }

        It 'writes a checksum that matches the ZIP' {
            $line = Get-Content -LiteralPath (Join-Path -Path $output -ChildPath 'SHA256SUMS.txt') | Where-Object { $_ -like '*.zip' }
            $expected = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
            $line | Should -Be "$expected  HelpdeskToolkit-$version.zip"
        }

        It 'does not build an installer with -SkipInstaller' {
            Get-ChildItem -Path $output -Filter '*.exe' | Should -BeNullOrEmpty
        }
    }

    Context 'the -ExpectedVersion check' {
        It 'accepts a tag that matches the manifest version' {
            { & $buildScript -OutputPath (Join-Path -Path $TestDrive -ChildPath 'match') -SkipInstaller -ExpectedVersion "v$version" } | Should -Not -Throw
        }

        It 'stops when the tag does not match the manifest version' {
            { & $buildScript -OutputPath (Join-Path -Path $TestDrive -ChildPath 'mismatch') -SkipInstaller -ExpectedVersion 'v99.99.99' } |
                Should -Throw '*manifest says version*'
        }
    }
}

Describe 'Installer script' {
    BeforeAll {
        $iss = Get-Content -LiteralPath (Join-Path -Path $root -ChildPath 'installer\HelpdeskToolkit.iss') -Raw
    }

    It 'keeps the AppId equal to the module GUID, so updates replace the installed version' {
        $iss | Should -Match ([regex]::Escape($manifest.GUID.ToUpper()))
    }

    It 'installs for the current user without administrator rights' {
        $iss | Should -Match 'PrivilegesRequired=lowest'
    }

    # Regression: after an update, script files that the new version had removed were
    # still in the installation folder and were loaded by the module.
    It 'removes the module folder of the previous version before copying the new files' {
        $iss | Should -Match '(?m)^\[InstallDelete\]\s*\r?\nType: filesandordirs; Name: "\{app\}\\HelpdeskToolkit"'
    }

    # Regression: an update that ran while the window was open could not replace the
    # files in use, stopped halfway and left an installation behind that did not start.
    It 'stops before it changes anything while the application is running' {
        $iss | Should -Match '(?m)^function PrepareToInstall\('
        $iss | Should -Match 'fmOpenReadWrite or fmShareExclusive'
        $iss | Should -Match '(?m)^function InitializeUninstall\('
        # The file it tries to open is the one the running application keeps open.
        $iss | Should -Match "ExpandConstant\('\{app\}\\\{#AppIcon\}'\)"
        Join-Path -Path $root -ChildPath 'HelpdeskToolkit\Assets\HelpdeskToolkit.ico' | Should -Exist
    }

    It 'starts the application through the launcher script that is shipped' {
        $iss | Should -Match 'Start-HelpdeskToolkit\.ps1'
        Join-Path -Path $root -ChildPath 'Start-HelpdeskToolkit.ps1' | Should -Exist
    }

    # Regression: started directly, PowerShell left an empty Windows Terminal window
    # open on Windows 11, and closing that window closed the application.
    It 'starts PowerShell through the headless console host, so no console window appears' {
        # Comment lines (starting with ";") explain the old behaviour and are ignored.
        $commands = ($iss -split "`r?`n" | Where-Object { $_ -notmatch '^\s*;' }) -join "`n"
        $commands | Should -Match '\{sys\}\\conhost\.exe'
        $commands | Should -Match '--headless'
        $commands | Should -Not -Match '-WindowStyle Hidden'
    }
}

Describe 'Launcher' {
    It 'Start-HelpdeskToolkit.cmd calls the launcher script next to it' {
        Get-Content -LiteralPath (Join-Path -Path $root -ChildPath 'Start-HelpdeskToolkit.cmd') -Raw |
            Should -Match '%~dp0Start-HelpdeskToolkit\.ps1'
    }

    It 'Start-HelpdeskToolkit.cmd starts PowerShell through the headless console host' {
        $text = Get-Content -LiteralPath (Join-Path -Path $root -ChildPath 'Start-HelpdeskToolkit.cmd') -Raw
        $text | Should -Match 'conhost\.exe" --headless'
        ($text -split "`r?`n" | Where-Object { $_ -notmatch '^\s*rem' }) -join "`n" | Should -Not -Match '-WindowStyle Hidden'
    }

    It 'Start-HelpdeskToolkit.cmd uses Windows line endings' {
        $text = [System.IO.File]::ReadAllText((Join-Path -Path $root -ChildPath 'Start-HelpdeskToolkit.cmd'))
        $text -replace "`r`n", '' | Should -Not -Match "`n"
    }

    It 'Start-HelpdeskToolkit.ps1 passes on how the window is to start' {
        $text = Get-Content -LiteralPath (Join-Path -Path $root -ChildPath 'Start-HelpdeskToolkit.ps1') -Raw
        $text | Should -Match '\[switch\]\$RunCheck'
        $text | Should -Match '\[switch\]\$NoQuestion'
        $text | Should -Match 'Show-PCHealthCheck -RunCheck:\$RunCheck -NoQuestion:\$NoQuestion'
    }

    It 'Start-HelpdeskToolkit.ps1 loads the module from its own folder' {
        Get-Content -LiteralPath (Join-Path -Path $root -ChildPath 'Start-HelpdeskToolkit.ps1') -Raw |
            Should -Match '\$PSScriptRoot'
    }
}

Describe 'Application icon' {
    It 'is a valid .ico file with several sizes' {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path -Path $root -ChildPath 'HelpdeskToolkit\Assets\HelpdeskToolkit.ico'))
        # Header: reserved 0, type 1 (icon), then the number of images.
        [System.BitConverter]::ToUInt16($bytes, 0) | Should -Be 0
        [System.BitConverter]::ToUInt16($bytes, 2) | Should -Be 1
        [System.BitConverter]::ToUInt16($bytes, 4) | Should -BeGreaterThan 3
    }
}

Describe 'Invoke-HealthCheck.ps1' {
    BeforeAll {
        # The script is copied next to a stand-in module whose Invoke-PCHealthCheck
        # returns the statuses named in an environment variable, so the real checks do
        # not run. The script is started as a program, because its result is an exit code.
        $folder = Join-Path -Path $TestDrive -ChildPath 'automation'
        $moduleFolder = Join-Path -Path $folder -ChildPath 'HelpdeskToolkit'
        New-Item -Path $moduleFolder -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path -Path $root -ChildPath 'Invoke-HealthCheck.ps1') -Destination $folder

        Set-Content -LiteralPath (Join-Path -Path $moduleFolder -ChildPath 'HelpdeskToolkit.psd1') -Value "@{ RootModule = 'HelpdeskToolkit.psm1'; ModuleVersion = '0.0.1'; FunctionsToExport = @('Invoke-PCHealthCheck') }"
        Set-Content -LiteralPath (Join-Path -Path $moduleFolder -ChildPath 'HelpdeskToolkit.psm1') -Value @"
function Invoke-PCHealthCheck {
    [CmdletBinding()]
    param(`$OutputPath, `$Days, `$Format, [switch]`$SkipNetwork, [switch]`$NoOpen, [switch]`$PassThru, `$ComputerName)
    if (`$env:HELPDESKTOOLKIT_TEST_STATUS -eq 'throw') { throw 'The checks are broken' }
    Write-Host ("summary; NoOpen={0}; Format={1}" -f `$NoOpen.IsPresent, `$Format)
    foreach (`$status in (`$env:HELPDESKTOOLKIT_TEST_STATUS -split ',')) { [PSCustomObject]@{ Status = `$status } }
}
"@
        $script = Join-Path -Path $folder -ChildPath 'Invoke-HealthCheck.ps1'

        function Invoke-TestScript {
            param([string]$Status, [string[]]$Argument = @())

            $env:HELPDESKTOOLKIT_TEST_STATUS = $Status
            try {
                $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script @Argument 2>&1
                [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String) }
            }
            finally {
                Remove-Item -Path Env:\HELPDESKTOOLKIT_TEST_STATUS -ErrorAction SilentlyContinue
            }
        }
    }

    It 'ends with exit code <Code> when the results are <Status>' -ForEach @(
        @{ Status = 'OK,Info,OK'; Code = 0 }
        @{ Status = 'OK,Warning,Info'; Code = 1 }
        @{ Status = 'Warning,Critical,OK'; Code = 2 }
    ) {
        (Invoke-TestScript -Status $Status).ExitCode | Should -Be $Code
    }

    It 'ends with exit code 3 and says why when the check itself fails' {
        $run = Invoke-TestScript -Status 'throw'
        $run.ExitCode | Should -Be 3
        $run.Output | Should -Match 'could not run: The checks are broken'
    }

    It 'prints the summary, does not open the browser and passes the format on' {
        $run = Invoke-TestScript -Status 'OK' -Argument '-Format', 'Json'
        $run.Output | Should -Match 'summary; NoOpen=True; Format=Json'
    }

    It 'opens the browser only with -Open' {
        (Invoke-TestScript -Status 'OK' -Argument '-Open').Output | Should -Match 'NoOpen=False'
    }

    It 'prints nothing with -Quiet and still returns the exit code' {
        $run = Invoke-TestScript -Status 'Critical' -Argument '-Quiet'
        $run.Output.Trim() | Should -Be ''
        $run.ExitCode | Should -Be 2
    }
}

Describe 'Package for a tester' {
    BeforeAll {
        $script = Join-Path -Path $root -ChildPath 'tools\New-TestPackage.ps1'
        $readme = Join-Path -Path $root -ChildPath 'docs\tester\README.txt'
    }

    It 'has a script that puts the package together, with help' {
        $script | Should -Exist
        (Get-Help -Name $script).Synopsis | Should -Match 'folder'
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'builds on the release files, so the tester gets exactly what a release contains' {
        $text = Get-Content -LiteralPath $script -Raw
        $text | Should -Match 'Build-Release\.ps1'
        $text | Should -Match "HelpdeskToolkit-Setup-\{0\}\.exe"
        $text | Should -Match 'Expand-Archive'
    }

    It 'does not delete an old package while a copy started from it is still running' {
        $text = Get-Content -LiteralPath $script -Raw
        $text | Should -Match 'is still running'
        # The test for the open file comes before anything is removed.
        $text.IndexOf('[System.IO.FileShare]::None') | Should -BeLessThan $text.IndexOf('-Recurse -Force')
    }

    It 'has instructions in English, as a file Notepad reads on every Windows version' {
        [System.IO.File]::ReadAllText($readme, [System.Text.Encoding]::UTF8) | Should -Match '^\uFEFF?HelpdeskToolkit - test version'
        Join-Path -Path $root -ChildPath 'docs\tester\PROCITAJ-ME.txt' | Should -Not -Exist
        $bytes = [System.IO.File]::ReadAllBytes($readme)
        $bytes[0], $bytes[1], $bytes[2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'tells the tester how to start it, what Windows will warn about and what the tool does not do' {
        $text = [System.IO.File]::ReadAllText($readme, [System.Text.Encoding]::UTF8)
        $text | Should -Match 'Start-HelpdeskToolkit\.cmd'
        $text | Should -Match 'Windows protected your PC'
        $text | Should -Match 'Run anyway'
        $text | Should -Match 'ONLY READ'
        $text | Should -Match 'Privacy:'
        $text | Should -Match 'No warranty:'
        # The folder the instructions send the tester to is the one the script creates.
        $text | Should -Match 'Open the folder "Portable"'
        Get-Content -LiteralPath $script -Raw | Should -Match "-ChildPath 'Portable'"
    }
}
