BeforeDiscovery {
    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\HelpdeskToolkit'
    $publicFunctions = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' |
        ForEach-Object { @{ Name = $_.BaseName } }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule
    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\HelpdeskToolkit'
}

Describe 'Module manifest' {
    It 'is a valid manifest' {
        { Test-ModuleManifest -Path (Join-Path -Path $moduleRoot -ChildPath 'HelpdeskToolkit.psd1') -ErrorAction Stop } | Should -Not -Throw
    }

    It 'supports Windows PowerShell 5.1 and PowerShell 7' {
        $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'HelpdeskToolkit.psd1')
        $manifest.PowerShellVersion | Should -Be '5.1'
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
        $manifest.CompatiblePSEditions | Should -Contain 'Core'
    }

    It 'exports exactly the functions in the Public folder' {
        $expected = (Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1').BaseName | Sort-Object
        $exported = (Get-Command -Module HelpdeskToolkit -CommandType Function).Name | Sort-Object
        $exported | Should -Be $expected
    }

    It 'does not export private helpers' {
        Get-Command -Module HelpdeskToolkit -Name 'New-CheckResult' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}

Describe 'Comment-based help of <Name>' -ForEach $publicFunctions {
    BeforeAll {
        $help = Get-Help -Name $Name -Full
    }

    It 'has a synopsis' {
        $help.Synopsis | Should -Not -BeNullOrEmpty
        # Without written help PowerShell shows the syntax as the synopsis.
        $help.Synopsis | Should -Not -Match "^\s*$Name"
    }

    It 'has a description' {
        ($help.Description | Out-String).Trim() | Should -Not -BeNullOrEmpty
    }

    It 'has at least one example' {
        @($help.Examples.Example).Count | Should -BeGreaterThan 0
    }

    It 'documents every parameter' {
        $common = [System.Management.Automation.PSCmdlet]::CommonParameters
        $parameters = (Get-Command -Name $Name).Parameters.Keys | Where-Object { $_ -notin $common }
        foreach ($parameter in $parameters) {
            $text = ($help.Parameters.Parameter | Where-Object { $_.Name -eq $parameter }).Description | Out-String
            $text.Trim() | Should -Not -BeNullOrEmpty -Because "parameter -$parameter of $Name needs a description"
        }
    }
}

Describe 'Source files' {
    It 'contain only ASCII characters, so Windows PowerShell 5.1 reads them correctly without a BOM' {
        # Text files only; the icon is binary. The translations in the Lang folder need
        # other letters; they carry a byte order mark and are read as UTF-8 explicitly.
        $files = Get-ChildItem -Path $moduleRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.xaml', '*.css' |
            Where-Object { $_.Directory.Name -ne 'Lang' }
        foreach ($file in $files) {
            $nonAscii = [System.IO.File]::ReadAllBytes($file.FullName) | Where-Object { $_ -gt 127 }
            @($nonAscii).Count | Should -Be 0 -Because "$($file.Name) must be plain ASCII"
        }
    }

    It 'define one function per file, named like the file' {
        $files = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public'), (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1'
        foreach ($file in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $functions = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
            @($functions).Count | Should -Be 1 -Because "$($file.Name) should define exactly one function"
            $functions[0].Name | Should -Be $file.BaseName
        }
    }
}

Describe 'Recommendations' {
    # Every problem the tool reports must tell the reader what to do about it. This test
    # reads the source code of the checks instead of running them, so it also covers
    # results that only appear on a computer with that particular problem.
    It 'every result that can be a Warning or Critical is created with a recommendation' {
        $files = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public'), (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1'
        $checked = 0

        foreach ($file in $files) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $calls = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-CheckResult'
                }, $true)

            foreach ($call in $calls) {
                $elements = @($call.CommandElements)
                $parameters = @($elements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] })
                $statusParameter = $parameters | Where-Object { $_.ParameterName -eq 'Status' }
                if (-not $statusParameter) {
                    continue
                }

                # The value follows the -Status parameter: a fixed word or a variable.
                $statusValue = $elements[[array]::IndexOf($elements, $statusParameter) + 1]
                $isVariable = $statusValue -is [System.Management.Automation.Language.VariableExpressionAst]
                $text = $statusValue.Extent.Text.Trim("'", '"')

                if ($isVariable -or $text -in 'Warning', 'Critical') {
                    $checked++
                    @($parameters | Where-Object { $_.ParameterName -eq 'Recommendation' }).Count |
                        Should -Be 1 -Because "the result created in $($file.Name) on line $($call.Extent.StartLineNumber) can be a problem and needs a recommendation"
                }
            }
        }

        # Guards the test itself: if the search stopped finding calls it would pass for the wrong reason.
        $checked | Should -BeGreaterThan 30
    }
}

Describe 'Configuration files' {
    BeforeAll {
        $thresholds = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Thresholds.psd1')
        $descriptions = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Descriptions.psd1')
    }

    It 'Thresholds.psd1 has a section for every check that uses limits' {
        foreach ($section in 'Uptime', 'Startup', 'Cpu', 'Memory', 'Disk', 'Battery', 'EventLog', 'WindowsUpdate', 'Defender', 'Network', 'Services') {
            $thresholds.ContainsKey($section) | Should -BeTrue -Because "section $section is required"
        }
    }

    It 'keeps the warning limit before the critical limit' {
        $thresholds.Cpu.WarningPercent | Should -BeLessThan $thresholds.Cpu.CriticalPercent
        $thresholds.Memory.WarningPercent | Should -BeLessThan $thresholds.Memory.CriticalPercent
        $thresholds.Disk.WarningFreePercent | Should -BeGreaterThan $thresholds.Disk.CriticalFreePercent
        $thresholds.Battery.WarningPercent | Should -BeGreaterThan $thresholds.Battery.CriticalPercent
        $thresholds.Defender.SignatureWarningDays | Should -BeLessThan $thresholds.Defender.SignatureCriticalDays
    }

    It 'Descriptions.psd1 describes every monitored service' {
        foreach ($service in $thresholds.Services) {
            $descriptions["Service:$service"] | Should -Not -BeNullOrEmpty -Because "service $service needs a description"
        }
    }

    It 'has no empty description' {
        foreach ($key in $descriptions.Keys) {
            $descriptions[$key] | Should -Not -BeNullOrEmpty -Because "description '$key' is empty"
        }
    }
}
