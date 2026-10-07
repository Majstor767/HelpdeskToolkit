BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    # The test configuration knows three made-up releases with dates relative to today:
    # 90H1 ended 10 days ago, 90H2 ends in 30 days, 91H1 ends in 400 days (Home/Pro).
    # For Enterprise, 90H1 still has 355 days. Windows 10 ended 100 days ago.
    Set-TestThreshold
}

Describe 'Get-WindowsSupportInfo' {
    It 'is OK while the release is supported for a long time' {
        $info = InModuleScope HelpdeskToolkit { Get-WindowsSupportInfo -Caption 'Microsoft Windows 11 Pro' -BuildNumber 26100 -DisplayVersion '91H1' }
        $info.Status | Should -Be 'OK'
        $info.Value | Should -Be ([string]::Format([cultureinfo]::InvariantCulture, 'Supported until {0:yyyy-MM-dd}', @((Get-Date).AddDays(400))))
        $info.Recommendation | Should -Be ''
    }

    It 'is a Warning when support ends within the configured number of days' {
        $info = InModuleScope HelpdeskToolkit { Get-WindowsSupportInfo -Caption 'Microsoft Windows 11 Home' -BuildNumber 26100 -DisplayVersion '90H2' }
        $info.Status | Should -Be 'Warning'
        $info.Value | Should -Be ([string]::Format([cultureinfo]::InvariantCulture, 'Supported until {0:yyyy-MM-dd} (30 days left)', @((Get-Date).AddDays(30))))
        $info.Recommendation | Should -Match 'feature update'
    }

    It 'is Critical when the release is out of support' {
        $info = InModuleScope HelpdeskToolkit { Get-WindowsSupportInfo -Caption 'Microsoft Windows 11 Pro' -BuildNumber 22631 -DisplayVersion '90H1' }
        $info.Status | Should -Be 'Critical'
        $info.Value | Should -Be ([string]::Format([cultureinfo]::InvariantCulture, 'Out of support since {0:yyyy-MM-dd}', @((Get-Date).AddDays(-10))))
        $info.Recommendation | Should -Match 'no longer receives security updates'
    }

    It 'uses the longer Enterprise dates for the <Edition> edition' -ForEach @(
        @{ Edition = 'Microsoft Windows 11 Enterprise' }
        @{ Edition = 'Microsoft Windows 11 Education' }
    ) {
        $info = InModuleScope HelpdeskToolkit -Parameters $_ { Get-WindowsSupportInfo -Caption $Edition -BuildNumber 22631 -DisplayVersion '90H1' }
        $info.Status | Should -Be 'OK'
    }

    It 'treats Pro Education as a Pro edition, like the Microsoft lifecycle does' {
        $info = InModuleScope HelpdeskToolkit { Get-WindowsSupportInfo -Caption 'Microsoft Windows 11 Pro Education' -BuildNumber 22631 -DisplayVersion '90H1' }
        $info.Status | Should -Be 'Critical'
    }

    It 'reports Windows 10 (build below 22000) by its single end date' {
        $info = InModuleScope HelpdeskToolkit { Get-WindowsSupportInfo -Caption 'Microsoft Windows 10 Pro' -BuildNumber 19045 -DisplayVersion '22H2' }
        $info.Status | Should -Be 'Critical'
        $info.Recommendation | Should -Match 'Windows 11'
    }

    It 'does not judge a release it has no date for' {
        $info = InModuleScope HelpdeskToolkit { Get-WindowsSupportInfo -Caption 'Microsoft Windows 11 Pro' -BuildNumber 29000 -DisplayVersion '99H9' }
        $info.Status | Should -Be 'Info'
        $info.Value | Should -Be 'No end date known for version 99H9'
    }

    It 'does not judge <Caption>' -ForEach @(
        @{ Caption = 'Microsoft Windows 11 IoT Enterprise LTSC'; ProductType = 1; Expected = 'Long-term servicing' }
        @{ Caption = 'Microsoft Windows Server 2025 Standard'; ProductType = 3; Expected = 'Server edition' }
    ) {
        $info = InModuleScope HelpdeskToolkit -Parameters $_ {
            Get-WindowsSupportInfo -Caption $Caption -BuildNumber 26100 -DisplayVersion '90H1' -ProductType $ProductType
        }
        $info.Status | Should -Be 'Info'
        $info.Value | Should -Match $Expected
    }
}

Describe 'Windows support dates in the configuration' {
    BeforeAll {
        $root = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
        $support = (Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'Config\Thresholds.psd1')).WindowsSupport
    }

    It 'are all valid dates' {
        $dates = @($support.Windows10End) + @($support.HomePro.Values) + @($support.Enterprise.Values)
        foreach ($date in $dates) {
            { [datetime]::ParseExact($date, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture) } | Should -Not -Throw
        }
    }

    It 'list the same releases for both edition groups' {
        ($support.HomePro.Keys | Sort-Object) | Should -Be ($support.Enterprise.Keys | Sort-Object)
    }

    It 'give Enterprise and Education a later end date than Home and Pro' {
        foreach ($release in $support.HomePro.Keys) {
            [datetime]$support.Enterprise[$release] | Should -BeGreaterThan ([datetime]$support.HomePro[$release])
        }
    }
}
