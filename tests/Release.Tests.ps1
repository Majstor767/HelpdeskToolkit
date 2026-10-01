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
