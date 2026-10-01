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
        Mock -ModuleName HelpdeskToolkit Get-PendingUpdate { }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }

        # An event of Windows Update: 19 = installed (the title comes first),
        # 20 = failed (the error code comes first, then the title).
        function New-TestUpdateEvent {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([string]$Title, [int]$DaysAgo, [switch]$Failed, [int]$Code = -2145116147)

            $values = if ($Failed) { @($Code, $Title) } else { @($Title) }
            [PSCustomObject]@{
                Id          = if ($Failed) { 20 } else { 19 }
                TimeCreated = (Get-Date).AddDays(-$DaysAgo)
                Properties  = @($values | ForEach-Object { [PSCustomObject]@{ Value = $_ } })
            }
        }
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

        It 'reports that no update is waiting and none has failed' {
            ($results | Where-Object Check -eq 'Pending updates').Status | Should -Be 'OK'
            ($results | Where-Object Check -eq 'Pending updates').Value | Should -Be 'None'
            ($results | Where-Object Check -eq 'Failed updates').Status | Should -Be 'OK'
            ($results | Where-Object Check -eq 'Failed updates').Value | Should -Be 'None in the last 30 days'
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

    Context 'updates that are waiting to be installed' {
        It 'lists them as information with the advice to install them' {
            Mock -ModuleName HelpdeskToolkit Get-PendingUpdate { '2026-09 Security Update (KB5000010)' }
            $pending = Get-WindowsUpdateHealth | Where-Object Check -eq 'Pending updates'

            $pending.Status | Should -Be 'Info'
            $pending.Value | Should -Be '1 update: 2026-09 Security Update (KB5000010)'
            $pending.Recommendation | Should -Match 'Windows Update'
        }

        It 'shows the first three and keeps the rest as details' {
            Mock -ModuleName HelpdeskToolkit Get-PendingUpdate { 1..5 | ForEach-Object { "Update $_" } }
            $pending = Get-WindowsUpdateHealth | Where-Object Check -eq 'Pending updates'

            $pending.Value | Should -Be '5 updates: Update 1, Update 2, Update 3 and 2 more'
            $pending.Details | Should -Be @('Update 4', 'Update 5')
        }

        It 'reports them as unavailable when Windows Update cannot be asked' {
            Mock -ModuleName HelpdeskToolkit Get-PendingUpdate { throw 'The service is disabled' }
            $results = Get-WindowsUpdateHealth
            ($results | Where-Object Check -eq 'Pending updates').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Failed updates').Status | Should -Be 'OK'
        }
    }

    Context 'updates that failed to install' {
        It 'is a Warning that names the update and its error code' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent {
                New-TestUpdateEvent -Title '2026-09 Security Update (KB5000010) (26100.1)' -DaysAgo 2 -Failed
            }
            $failed = Get-WindowsUpdateHealth | Where-Object Check -eq 'Failed updates'

            $failed.Status | Should -Be 'Warning'
            $failed.Value | Should -Be '1 update: 2026-09 Security Update (KB5000010) (26100.1) (error 0x8024200D)'
            $failed.Recommendation | Should -Match 'error code'
        }

        It 'does not count an update that was installed on a later attempt' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent {
                # Newest first, the order in which Windows returns events.
                New-TestUpdateEvent -Title '2026-09 Security Update (KB5000010)' -DaysAgo 1
                New-TestUpdateEvent -Title '2026-09 Security Update (KB5000010)' -DaysAgo 2 -Failed
            }
            (Get-WindowsUpdateHealth | Where-Object Check -eq 'Failed updates').Status | Should -Be 'OK'
        }

        It 'counts an update whose last attempt failed, even if an earlier one worked' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent {
                New-TestUpdateEvent -Title 'Contoso Driver Update' -DaysAgo 1 -Failed
                New-TestUpdateEvent -Title 'Contoso Driver Update' -DaysAgo 5
            }
            (Get-WindowsUpdateHealth | Where-Object Check -eq 'Failed updates').Status | Should -Be 'Warning'
        }

        It 'does not count an update that was replaced by a newer release of the same kind' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent {
                New-TestUpdateEvent -Title '2026-09 Security Update (KB5000010) (26100.2)' -DaysAgo 1
                New-TestUpdateEvent -Title '2026-08 Security Update (KB5000009) (26100.1)' -DaysAgo 20 -Failed
                New-TestUpdateEvent -Title 'Security Intelligence Update for Contoso Antivirus - KB1 (Version 1.2.4.0)' -DaysAgo 2
                New-TestUpdateEvent -Title 'Security Intelligence Update for Contoso Antivirus - KB1 (Version 1.2.3.0)' -DaysAgo 3 -Failed
            }
            (Get-WindowsUpdateHealth | Where-Object Check -eq 'Failed updates').Status | Should -Be 'OK'
        }

        It 'only looks at the configured number of days and at the two events of Windows Update' {
            Get-WindowsUpdateHealth | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter {
                $FilterHashtable.LogName -eq 'System' -and
                $FilterHashtable.ProviderName -eq 'Microsoft-Windows-WindowsUpdateClient' -and
                ($FilterHashtable.Id -join ',') -eq '19,20' -and
                $FilterHashtable.StartTime -lt (Get-Date).AddDays(-29) -and $FilterHashtable.StartTime -gt (Get-Date).AddDays(-31)
            }
        }

        It 'reports the failed updates as unavailable when the event log cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent { throw 'The event log service is not running' }
            (Get-WindowsUpdateHealth | Where-Object Check -eq 'Failed updates').Value | Should -Be 'Unavailable'
        }
    }
}
