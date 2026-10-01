BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
}

Describe 'New-CheckResult' {
    It 'returns an object with the standard properties in a fixed order' {
        $result = InModuleScope HelpdeskToolkit {
            New-CheckResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d'
        }
        $result.PSObject.Properties.Name |
            Should -Be @('Category', 'Check', 'Description', 'Status', 'Value', 'Details', 'Allowed', 'Typical', 'Recommendation')
        $result.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.CheckResult'
    }

    It 'rejects a status outside OK, Warning, Critical and Info' {
        { InModuleScope HelpdeskToolkit { New-CheckResult -Category 'a' -Check 'b' -Status 'Broken' } } | Should -Throw
    }

    It 'defaults the optional text properties to empty strings' {
        $result = InModuleScope HelpdeskToolkit { New-CheckResult -Category 'a' -Check 'Unknown check' -Status Info }
        $result.Value | Should -Be ''
        $result.Allowed | Should -Be ''
        $result.Typical | Should -Be ''
        $result.Recommendation | Should -Be ''
    }

    It 'looks the description up by check name' {
        $result = InModuleScope HelpdeskToolkit { New-CheckResult -Category 'System' -Check 'Uptime' -Status OK }
        $result.Description | Should -Match 'time since Windows was last started'
    }

    It 'prefers a description that is passed explicitly' {
        $result = InModuleScope HelpdeskToolkit { New-CheckResult -Category 'System' -Check 'Uptime' -Status OK -Description 'Custom text' }
        $result.Description | Should -Be 'Custom text'
    }

    It 'always returns Details as an array without empty entries' {
        $none = InModuleScope HelpdeskToolkit { New-CheckResult -Category 'a' -Check 'b' -Status Info }
        $fromNull = InModuleScope HelpdeskToolkit { New-CheckResult -Category 'a' -Check 'b' -Status Info -Details $null }
        $two = InModuleScope HelpdeskToolkit { New-CheckResult -Category 'a' -Check 'b' -Status Info -Details 'x', '', 'y' }

        @($none.Details).Count | Should -Be 0
        @($fromNull.Details).Count | Should -Be 0
        $two.Details | Should -Be @('x', 'y')
    }
}

Describe 'Get-CheckDescription' {
    It 'returns the text stored under the exact key' {
        InModuleScope HelpdeskToolkit { Get-CheckDescription -Key 'Service:Spooler' } | Should -Match 'print jobs'
    }

    It 'falls back to the name before a parenthesis or colon: <Key>' -ForEach @(
        @{ Key = 'Disk (C:)'; Pattern = 'drive letter' }
        @{ Key = 'Drive: Contoso SSD'; Pattern = 'physical SSD' }
        @{ Key = 'Adapter: Contoso Wi-Fi'; Pattern = 'network card' }
        @{ Key = 'BitLocker (C:)'; Pattern = 'encryption' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters $_ { Get-CheckDescription -Key $Key | Should -Match $Pattern }
    }

    It 'returns an empty string for an unknown key' {
        InModuleScope HelpdeskToolkit { Get-CheckDescription -Key 'No such check' } | Should -Be ''
    }
}

Describe 'New-AdminRequiredResult' {
    It 'creates an Info result marked "Requires admin"' {
        $result = InModuleScope HelpdeskToolkit { New-AdminRequiredResult -Category 'Security' -Check 'TPM' }
        $result.Status | Should -Be 'Info'
        $result.Value | Should -Be 'Requires admin'
        $result.Recommendation | Should -Match 'administrator'
    }
}

Describe 'Test-AccessDenied' {
    It 'recognizes UnauthorizedAccessException' {
        $record = New-TestErrorRecord -Exception (New-Object -TypeName System.UnauthorizedAccessException -ArgumentList 'denied')
        InModuleScope HelpdeskToolkit -Parameters @{ Record = $record } { Test-AccessDenied -ErrorRecord $Record } | Should -BeTrue
    }

    It 'recognizes the E_ACCESSDENIED HRESULT' {
        $exception = New-Object -TypeName System.Runtime.InteropServices.COMException -ArgumentList 'denied', -2147024891
        $record = New-TestErrorRecord -Exception $exception
        InModuleScope HelpdeskToolkit -Parameters @{ Record = $record } { Test-AccessDenied -ErrorRecord $Record } | Should -BeTrue
    }

    It 'returns false for other errors' {
        $record = New-TestErrorRecord -Message 'Something else'
        InModuleScope HelpdeskToolkit -Parameters @{ Record = $record } { Test-AccessDenied -ErrorRecord $Record } | Should -BeFalse
    }
}

Describe 'New-FailureResult' {
    It 'turns a permission error into "Requires admin"' {
        $record = New-TestErrorRecord -Exception (New-Object -TypeName System.UnauthorizedAccessException -ArgumentList 'denied')
        $result = InModuleScope HelpdeskToolkit -Parameters @{ Record = $record } {
            New-FailureResult -Category 'Security' -Check 'TPM' -ErrorRecord $Record
        }
        $result.Status | Should -Be 'Info'
        $result.Value | Should -Be 'Requires admin'
    }

    It 'turns any other error into a Warning that carries the message' {
        $record = New-TestErrorRecord -Message '  RPC server unavailable  '
        $result = InModuleScope HelpdeskToolkit -Parameters @{ Record = $record } {
            New-FailureResult -Category 'System' -Check 'System information' -ErrorRecord $Record
        }
        $result.Status | Should -Be 'Warning'
        $result.Value | Should -Be 'Unavailable'
        $result.Recommendation | Should -Be 'The information could not be read: RPC server unavailable'
    }
}
