# Tests for the private functions behind the administrator-only checks. The Security
# log, the performance log and WMI are replaced with mocks, so the tests need no
# administrator rights and give the same result on every computer.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule

    # Builds a fake Security log entry whose values are in the given positions.
    function New-TestSecurityEvent {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string[]]$Value)

        [PSCustomObject]@{ Properties = @($Value | ForEach-Object { [PSCustomObject]@{ Value = $_ } }) }
    }
}

Describe 'Get-SignInEvent' {
    It 'returns the account name of every failed sign-in (event 4625, sixth value)' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            New-TestSecurityEvent -Value 'S-1-0-0', '-', '-', '0x0', 'S-1-0-0', 'm.horvat', 'CONTOSO'
            New-TestSecurityEvent -Value 'S-1-0-0', '-', '-', '0x0', 'S-1-0-0', 'administrator', 'CONTOSO'
        }
        $names = InModuleScope HelpdeskToolkit { Get-SignInEvent -Kind FailedSignIn -Since (Get-Date).AddDays(-7) }

        $names | Should -Be @('m.horvat', 'administrator')
        Should -Invoke -ModuleName HelpdeskToolkit Get-WinEvent -Times 1 -Exactly -ParameterFilter {
            $FilterHashtable[0].LogName -eq 'Security' -and $FilterHashtable[0].Id -eq 4625
        }
    }

    It 'returns the account name of every lockout (event 4740, first value)' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { New-TestSecurityEvent -Value 'm.horvat', 'FIN-LT-014' }
        InModuleScope HelpdeskToolkit { Get-SignInEvent -Kind Lockout -Since (Get-Date).AddDays(-7) } | Should -Be 'm.horvat'
        Should -Invoke -ModuleName HelpdeskToolkit Get-WinEvent -Times 1 -Exactly -ParameterFilter { $FilterHashtable[0].Id -eq 4740 }
    }

    It 'returns nothing when the log has no such events' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }
        @(InModuleScope HelpdeskToolkit { Get-SignInEvent -Kind FailedSignIn -Since (Get-Date).AddDays(-7) }).Count | Should -Be 0
    }

    It 'passes other errors on, so the check can report them' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { throw 'The event log service is not running' }
        { InModuleScope HelpdeskToolkit { Get-SignInEvent -Kind FailedSignIn -Since (Get-Date).AddDays(-7) } } |
            Should -Throw '*event log service*'
    }

    It 'returns "unknown" for an event that does not carry the account name' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { New-TestSecurityEvent -Value 'only', 'two' }
        InModuleScope HelpdeskToolkit { Get-SignInEvent -Kind FailedSignIn -Since (Get-Date).AddDays(-7) } | Should -Be 'unknown'
    }
}

Describe 'Get-LastBootDuration' {
    It 'reads the startup time in seconds and when it was measured' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            $entry = [PSCustomObject]@{ TimeCreated = [datetime]'2026-01-10 08:15:00' }
            $entry | Add-Member -MemberType ScriptMethod -Name ToXml -Value {
                '<Event><EventData><Data Name="BootEndTime">x</Data><Data Name="BootTime">61500</Data><Data Name="MainPathBootTime">15000</Data></EventData></Event>'
            }
            $entry
        }
        $boot = InModuleScope HelpdeskToolkit { Get-LastBootDuration }

        $boot.Seconds | Should -Be 62
        $boot.MeasuredAt | Should -Be ([datetime]'2026-01-10 08:15:00')
    }

    It 'returns nothing when Windows has not recorded a startup' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }
        InModuleScope HelpdeskToolkit { Get-LastBootDuration } | Should -BeNullOrEmpty
    }

    It 'returns nothing when the event does not contain the startup time' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            $entry = [PSCustomObject]@{ TimeCreated = Get-Date }
            $entry | Add-Member -MemberType ScriptMethod -Name ToXml -Value { '<Event><EventData><Data Name="Other">1</Data></EventData></Event>' }
            $entry
        }
        InModuleScope HelpdeskToolkit { Get-LastBootDuration } | Should -BeNullOrEmpty
    }
}

Describe 'Get-AdministratorGroupMember' {
    BeforeAll {
        # An in-memory WMI object; the group is called differently on non-English Windows.
        $group = New-CimInstance -ClassName Win32_Group -ClientOnly -Property @{ Name = 'Administratoren'; SID = 'S-1-5-32-544' }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { $group }
    }

    It 'finds the group by its SID, not by its translated name' {
        Mock -ModuleName HelpdeskToolkit Get-CimAssociatedInstance { }
        InModuleScope HelpdeskToolkit { Get-AdministratorGroupMember } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -Times 1 -Exactly -ParameterFilter {
            $ClassName -eq 'Win32_Group' -and $Filter -match 'S-1-5-32-544'
        }
    }

    It 'returns the user accounts and the groups that are members' {
        Mock -ModuleName HelpdeskToolkit Get-CimAssociatedInstance -ParameterFilter { $ResultClassName -eq 'Win32_UserAccount' } {
            [PSCustomObject]@{ Name = 'Administrator' }
            [PSCustomObject]@{ Name = 'support' }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimAssociatedInstance -ParameterFilter { $ResultClassName -eq 'Win32_Group' } {
            [PSCustomObject]@{ Name = 'Domain Admins' }
        }
        InModuleScope HelpdeskToolkit { Get-AdministratorGroupMember } | Should -Be @('Administrator', 'support', 'Domain Admins')
    }

    It 'returns nothing when the group cannot be found' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { }
        @(InModuleScope HelpdeskToolkit { Get-AdministratorGroupMember }).Count | Should -Be 0
    }
}
