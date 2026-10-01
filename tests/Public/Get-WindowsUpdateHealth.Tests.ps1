BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold
}

Describe 'Get-WindowsUpdateHealth' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-HotFix {
            [PSCustomObject]@{ HotFixID = 'KB5000001'; InstalledOn = (Get-Date).Date.AddDays(-40) }
            [PSCustomObject]@{ HotFixID = 'KB5000002'; InstalledOn = (Get-Date).Date.AddDays(-10) }
            # Some updates report no install date at all.
            [PSCustomObject]@{ HotFixID = 'KB5000003'; InstalledOn = $null }
        }
        Mock -ModuleName HelpdeskToolkit Get-PendingRebootReason { }
        # No pause date in the registry: updates are not paused.
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { }
    }

    Context 'on an up-to-date computer' {
        BeforeAll {
            $results = Get-WindowsUpdateHealth
        }

        It 'reports the newest update that has an install date' {
            $update = $results | Where-Object Check -eq 'Last installed update'
            $update.Status | Should -Be 'OK'
            $update.Value | Should -Be ('KB5000002 on {0:yyyy-MM-dd} (10 days ago)' -f (Get-Date).Date.AddDays(-10))
            $update.Allowed | Should -Be '0 - 45 days'
            $update.Typical | Should -Be 'typical update'
        }

        It 'reports that no restart is pending' {
            $restart = $results | Where-Object Check -eq 'Pending restart'
            $restart.Status | Should -Be 'OK'
            $restart.Value | Should -Be 'No'
        }
    }

    Context 'when no update was installed for a long time' {
        It 'is a Warning and points to Windows Update' {
            Mock -ModuleName HelpdeskToolkit Get-HotFix {
                [PSCustomObject]@{ HotFixID = 'KB5000001'; InstalledOn = (Get-Date).Date.AddDays(-60) }
            }
            $update = Get-WindowsUpdateHealth | Where-Object Check -eq 'Last installed update'
            $update.Status | Should -Be 'Warning'
            $update.Recommendation | Should -Match 'Windows Update'
        }
    }

    Context 'when there is no update history' {
        It 'reports that as information' {
            Mock -ModuleName HelpdeskToolkit Get-HotFix { }
            $update = Get-WindowsUpdateHealth | Where-Object Check -eq 'Last installed update'
            $update.Status | Should -Be 'Info'
            $update.Value | Should -Be 'No update history found'
        }
    }

    Context 'when a restart is pending' {
        It 'is a Warning that lists the reasons' {
            Mock -ModuleName HelpdeskToolkit Get-PendingRebootReason { 'Windows Update'; 'Component servicing' }
            $restart = Get-WindowsUpdateHealth | Where-Object Check -eq 'Pending restart'
            $restart.Status | Should -Be 'Warning'
            $restart.Value | Should -Be 'Yes (Windows Update, Component servicing)'
            $restart.Recommendation | Should -Match 'Restart'
        }
    }

    Context 'paused updates' {
        It 'reports that updates are not paused when no pause date is stored' {
            $paused = Get-WindowsUpdateHealth | Where-Object Check -eq 'Updates paused'
            $paused.Status | Should -Be 'OK'
            $paused.Value | Should -Be 'No'
        }

        It 'is a Warning while the pause date is in the future' {
            $until = (Get-Date).AddDays(10)
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue { $until.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
            $paused = Get-WindowsUpdateHealth | Where-Object Check -eq 'Updates paused'
            $paused.Status | Should -Be 'Warning'
            $paused.Value | Should -Be ('Yes, until {0:yyyy-MM-dd}' -f $until)
            $paused.Recommendation | Should -Match 'Resume updates'
        }

        It 'ignores a pause that has already ended' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue { '2020-01-01T00:00:00Z' }
            (Get-WindowsUpdateHealth | Where-Object Check -eq 'Updates paused').Status | Should -Be 'OK'
        }

        It 'ignores a value that is not a date' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue { 'not a date' }
            (Get-WindowsUpdateHealth | Where-Object Check -eq 'Updates paused').Status | Should -Be 'OK'
        }
    }

    Context 'when the update history cannot be read' {
        It 'reports it as unavailable and still checks the pending restart' {
            Mock -ModuleName HelpdeskToolkit Get-HotFix { throw 'Query failed' }
            $results = Get-WindowsUpdateHealth
            ($results | Where-Object Check -eq 'Last installed update').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Pending restart').Status | Should -Be 'OK'
        }
    }
}
