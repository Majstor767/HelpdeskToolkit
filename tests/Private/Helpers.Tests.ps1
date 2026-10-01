BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
}

Describe 'Get-ThresholdStatus' {
    It 'returns <Expected> for value <Value> (higher is worse, warning 85, critical 95)' -ForEach @(
        @{ Value = 0; Expected = 'OK' }
        @{ Value = 85; Expected = 'OK' }
        @{ Value = 85.1; Expected = 'Warning' }
        @{ Value = 95; Expected = 'Warning' }
        @{ Value = 96; Expected = 'Critical' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters $_ {
            Get-ThresholdStatus -Value $Value -Warning 85 -Critical 95 | Should -Be $Expected
        }
    }

    It 'returns <Expected> for value <Value> (lower is worse, warning 15, critical 5)' -ForEach @(
        @{ Value = 50; Expected = 'OK' }
        @{ Value = 15; Expected = 'OK' }
        @{ Value = 14.9; Expected = 'Warning' }
        @{ Value = 5; Expected = 'Warning' }
        @{ Value = 4.9; Expected = 'Critical' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters $_ {
            Get-ThresholdStatus -Value $Value -Warning 15 -Critical 5 -LowerIsWorse | Should -Be $Expected
        }
    }

    It 'never returns Critical when no critical limit is given' {
        InModuleScope HelpdeskToolkit {
            Get-ThresholdStatus -Value 1000 -Warning 7 | Should -Be 'Warning'
            Get-ThresholdStatus -Value 7 -Warning 7 | Should -Be 'OK'
        }
    }

    It 'treats a warning limit of 0 as "any occurrence is a warning"' {
        InModuleScope HelpdeskToolkit {
            Get-ThresholdStatus -Value 0 -Warning 0 | Should -Be 'OK'
            Get-ThresholdStatus -Value 1 -Warning 0 | Should -Be 'Warning'
        }
    }
}

Describe 'Format-AllowedRange' {
    It 'formats a range with a critical limit' {
        InModuleScope HelpdeskToolkit {
            Format-AllowedRange -Warning 85 -Critical 95 -Unit '%' | Should -Be '0 - 85 % (critical above 95 %)'
        }
    }

    It 'formats a range without a critical limit' {
        InModuleScope HelpdeskToolkit {
            Format-AllowedRange -Warning 7 -Unit 'days' | Should -Be '0 - 7 days'
        }
    }

    It 'formats a range without a unit' {
        InModuleScope HelpdeskToolkit {
            Format-AllowedRange -Warning 15 | Should -Be '0 - 15'
        }
    }

    It 'shows a single 0 when nothing is allowed' {
        InModuleScope HelpdeskToolkit {
            Format-AllowedRange -Warning 0 -Critical 4 | Should -Be '0 (critical above 4)'
        }
    }

    It 'reverses the range when lower is worse' {
        InModuleScope HelpdeskToolkit {
            Format-AllowedRange -Warning 15 -Critical 5 -Unit '% free' -LowerIsWorse |
                Should -Be '15 - 100 % free (critical below 5 % free)'
        }
    }
}

Describe 'Format-Gigabyte' {
    It 'formats <Bytes> bytes as <Expected>' -ForEach @(
        @{ Bytes = 1GB; Expected = '1 GB' }
        @{ Bytes = 1.5GB; Expected = '1.5 GB' }
        @{ Bytes = 499581448192; Expected = '465.3 GB' }
        @{ Bytes = 0; Expected = '0 GB' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters $_ {
            Format-Gigabyte -Bytes $Bytes | Should -Be $Expected
        }
    }

    It 'uses a dot as decimal separator regardless of the regional settings' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]'hr-HR'
            InModuleScope HelpdeskToolkit { Format-Gigabyte -Bytes 1.5GB } | Should -Be '1.5 GB'
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
    }
}

Describe 'Format-DataRate' {
    It 'formats <Bytes> bytes per second as <Expected>' -ForEach @(
        @{ Bytes = 0; Expected = '0 KB/s' }
        @{ Bytes = 2048; Expected = '2 KB/s' }
        @{ Bytes = 1.5MB; Expected = '1.5 MB/s' }
        @{ Bytes = 2GB; Expected = '2 GB/s' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters $_ {
            Format-DataRate -BytesPerSecond $Bytes | Should -Be $Expected
        }
    }

    It 'formats <Bytes> bytes per second as <Expected> when bits are asked for' -ForEach @(
        @{ Bytes = 0; Expected = '0 Kbps' }
        @{ Bytes = 1250; Expected = '10 Kbps' }
        @{ Bytes = 1200000; Expected = '9.6 Mbps' }
        @{ Bytes = 312500000; Expected = '2.5 Gbps' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters $_ {
            Format-DataRate -BytesPerSecond $Bytes -AsBits | Should -Be $Expected
        }
    }

    It 'uses a dot as decimal separator regardless of the regional settings' {
        $previous = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [cultureinfo]'hr-HR'
            InModuleScope HelpdeskToolkit { Format-DataRate -BytesPerSecond 1.5MB } | Should -Be '1.5 MB/s'
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $previous
        }
    }
}

Describe 'ConvertTo-HtmlEncodedText' {
    It 'escapes characters that have a meaning in HTML' {
        InModuleScope HelpdeskToolkit {
            ConvertTo-HtmlEncodedText -Text '<b>"a" & b</b>' | Should -Be '&lt;b&gt;&quot;a&quot; &amp; b&lt;/b&gt;'
        }
    }

    It 'accepts an empty string' {
        InModuleScope HelpdeskToolkit {
            ConvertTo-HtmlEncodedText -Text '' | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-HealthSummary' {
    It 'counts results per status' {
        $results = @(
            New-TestResult -Status OK
            New-TestResult -Status OK
            New-TestResult -Status Warning
            New-TestResult -Status Info
        )
        $summary = InModuleScope HelpdeskToolkit -Parameters @{ Results = $results } { Get-HealthSummary -Result $Results }

        $summary.OK | Should -Be 2
        $summary.Warning | Should -Be 1
        $summary.Critical | Should -Be 0
        $summary.Info | Should -Be 1
    }

    It 'returns zeros for an empty result list' {
        $summary = InModuleScope HelpdeskToolkit { Get-HealthSummary -Result @() }
        ($summary.Values | Measure-Object -Sum).Sum | Should -Be 0
    }
}

Describe 'Get-HealthThreshold' {
    It 'loads the configuration file when nothing is cached' {
        Import-TestModule
        $thresholds = InModuleScope HelpdeskToolkit { Get-HealthThreshold }
        $thresholds.Cpu.WarningPercent | Should -BeOfType [int]
        $thresholds.Services | Should -Contain 'Spooler'
    }
}

Describe 'Test-IsAdministrator' {
    It 'returns a boolean' {
        InModuleScope HelpdeskToolkit { Test-IsAdministrator } | Should -BeOfType [bool]
    }
}
