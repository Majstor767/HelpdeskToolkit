BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    # The test configuration lists programs installed in the last 30 days as recent
    # and warns above 5 application crashes.
    Set-TestThreshold
}

Describe 'Get-SoftwareHealth' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
            [PSCustomObject]@{ Name = 'Contoso Office'; Version = '16.0'; InstallDate = (Get-Date).Date.AddDays(-400) }
            [PSCustomObject]@{ Name = 'Archive Tool'; Version = '24.1'; InstallDate = (Get-Date).Date.AddDays(-5) }
            [PSCustomObject]@{ Name = 'Driver Pack'; Version = ''; InstallDate = $null }
        }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowserPath { 'C:\Contoso\browser.exe' }
        Mock -ModuleName HelpdeskToolkit Get-FileProductName { 'Contoso Browser' }
        Mock -ModuleName HelpdeskToolkit Get-BrowserExtension { }
        # winget finds nothing to update; no Microsoft Office and no Outlook on this computer.
        Mock -ModuleName HelpdeskToolkit Get-ProgramUpdate { [PSCustomObject]@{ Updates = @() } }
        Mock -ModuleName HelpdeskToolkit Get-OfficeInstallation { }
        Mock -ModuleName HelpdeskToolkit Get-OutlookDataFile { }
    }

    Context 'on a typical computer' {
        BeforeAll {
            $results = Get-SoftwareHealth
        }

        It 'returns seven results in the Software category' {
            @($results).Count | Should -Be 7
            $results.Category | Sort-Object -Unique | Should -Be 'Software'
        }

        It 'lists the installed programs by name, with versions' {
            $programs = $results | Where-Object Check -eq 'Installed programs'
            $programs.Status | Should -Be 'Info'
            $programs.Value | Should -Be '3 programs: Archive Tool 24.1, Contoso Office 16.0, Driver Pack'
        }

        It 'lists only programs installed within the configured number of days as recent' {
            $recent = $results | Where-Object Check -eq 'Recently installed'
            $recent.Value | Should -Be ('1 in the last 30 days: Archive Tool ({0:yyyy-MM-dd})' -f (Get-Date).Date.AddDays(-5))
        }

        It 'reports no crashes as OK' {
            $crashes = $results | Where-Object Check -eq 'Application crashes'
            $crashes.Status | Should -Be 'OK'
            $crashes.Value | Should -Be '0 in the last 7 days'
            $crashes.Allowed | Should -Be '0 - 5'
            $crashes.Typical | Should -Be 'typical crashes'
        }

        It 'reports the default browser by its product name' {
            ($results | Where-Object Check -eq 'Default browser').Value | Should -Be 'Contoso Browser'
        }

        It 'says so when no browser extension is installed' {
            ($results | Where-Object Check -eq 'Browser extensions').Value | Should -Be 'None found'
        }
    }

    Context 'with many installed programs' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
                1..12 | ForEach-Object { [PSCustomObject]@{ Name = 'Program{0:00}' -f $_; Version = '1.0'; InstallDate = (Get-Date).Date.AddDays(-$_) } }
            }
            $results = Get-SoftwareHealth
        }

        It 'shows the first eight programs and keeps the rest as details' {
            $programs = $results | Where-Object Check -eq 'Installed programs'
            $programs.Value | Should -Match '^12 programs: Program01 1\.0, .* and 4 more$'
            $programs.Details | Should -Be @('Program09 1.0', 'Program10 1.0', 'Program11 1.0', 'Program12 1.0')
        }

        It 'lists recent installations newest first' {
            $recent = $results | Where-Object Check -eq 'Recently installed'
            $recent.Value | Should -Match '^12 in the last 30 days: Program01 '
            $recent.Details.Count | Should -Be 4
        }
    }

    Context 'when nothing was installed recently' {
        It 'says so' {
            Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
                [PSCustomObject]@{ Name = 'Old Program'; Version = '1.0'; InstallDate = (Get-Date).Date.AddDays(-200) }
            }
            (Get-SoftwareHealth | Where-Object Check -eq 'Recently installed').Value | Should -Be 'None in the last 30 days'
        }
    }

    Context 'application crashes' {
        It 'groups the crashes by program, most frequent first' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent {
                New-TestEvent -Source 'Application Error' -Program 'editor.exe' -Count 1
                New-TestEvent -Source 'Application Error' -Program 'browser.exe' -Count 3
            }
            $crashes = Get-SoftwareHealth | Where-Object Check -eq 'Application crashes'
            $crashes.Status | Should -Be 'OK'
            $crashes.Value | Should -Be '4 in the last 7 days: browser.exe (3), editor.exe (1)'
        }

        It 'is a Warning above the limit and advises to update or reinstall' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent {
                New-TestEvent -Source 'Application Error' -Program 'browser.exe' -Count 6
            }
            $crashes = Get-SoftwareHealth | Where-Object Check -eq 'Application crashes'
            $crashes.Status | Should -Be 'Warning'
            $crashes.Recommendation | Should -Match 'reinstall'
        }

        It 'looks back the requested number of days' {
            Get-SoftwareHealth -Days 30 | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter {
                $FilterHashtable[0].Id -eq 1000 -and
                [math]::Abs(($FilterHashtable[0].StartTime - (Get-Date).AddDays(-30)).TotalMinutes) -lt 5
            }
            (Get-SoftwareHealth -Days 30 | Where-Object Check -eq 'Application crashes').Value | Should -Be '0 in the last 30 days'
        }

        It 'is reported as unavailable when the event log cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-WinEvent { throw 'The event log service is not running' }
            (Get-SoftwareHealth | Where-Object Check -eq 'Application crashes').Value | Should -Be 'Unavailable'
        }
    }

    Context 'when no default browser is registered' {
        It 'reports that none is set' {
            Mock -ModuleName HelpdeskToolkit Get-DefaultBrowserPath { }
            (Get-SoftwareHealth | Where-Object Check -eq 'Default browser').Value | Should -Be 'Not set'
        }
    }

    Context 'browser extensions' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-BrowserExtension {
                [PSCustomObject]@{ Browser = 'Edge'; Name = 'Password Manager'; Version = '3.1' }
                [PSCustomObject]@{ Browser = 'Chrome'; Name = 'Shopping Helper'; Version = '1.0.2' }
                [PSCustomObject]@{ Browser = 'Chrome'; Name = 'Ad Blocker'; Version = '' }
            }
            $extensions = Get-SoftwareHealth | Where-Object Check -eq 'Browser extensions'
        }

        It 'counts the extensions per browser' {
            $extensions.Status | Should -Be 'Info'
            $extensions.Value | Should -Be '3 extensions: Chrome (2), Edge (1)'
        }

        It 'lists every extension with its browser and version as details' {
            $extensions.Details | Should -Be @('Chrome: Ad Blocker', 'Chrome: Shopping Helper 1.0.2', 'Edge: Password Manager 3.1')
        }

        It 'reports the extensions as unavailable when they cannot be read' {
            Mock -ModuleName HelpdeskToolkit Get-BrowserExtension { throw 'Profile is locked' }
            $results = Get-SoftwareHealth
            ($results | Where-Object Check -eq 'Browser extensions').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Default browser').Value | Should -Be 'Contoso Browser'
        }
    }

    Context 'programs without support' {
        It 'is OK when none is installed' {
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Unsupported programs'
            $result.Status | Should -Be 'OK'
            $result.Value | Should -Be 'None found'
        }

        It 'is a Warning for a program that opens content from the internet, listed first' {
            Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
                [PSCustomObject]@{ Name = 'Python 3.8.10 (64-bit)'; Version = '3.8.10150.0'; InstallDate = $null }
                [PSCustomObject]@{ Name = 'Adobe Flash Player 32 NPAPI'; Version = '32.0.0.465'; InstallDate = $null }
                [PSCustomObject]@{ Name = 'Contoso Office'; Version = '16.0'; InstallDate = $null }
            }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Unsupported programs'
            $result.Status | Should -Be 'Warning'
            $result.Value | Should -Be '2 programs without security updates: Adobe Flash Player 32 NPAPI 32.0.0.465 (support ended 2020-12-31), Python 3.8.10 (64-bit) (support ended 2024-10-07)'
            $result.Recommendation | Should -Match 'Installed apps'
        }

        It 'is only information when nothing but runtimes is out of support' {
            Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
                [PSCustomObject]@{ Name = 'Python 3.8.10 (64-bit)'; Version = '3.8.10150.0'; InstallDate = $null }
            }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Unsupported programs'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Match '^1 program without security updates: Python 3\.8\.10'
            $result.Recommendation | Should -Match 'runtime'
        }
    }

    Context 'program updates' {
        It 'is OK when winget finds nothing to update' {
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Program updates'
            $result.Status | Should -Be 'OK'
            $result.Value | Should -Be 'Every program winget knows is up to date'
            $result.Allowed | Should -Be '0 - 3'
            $result.Typical | Should -Be 'typical updates'
        }

        It 'lists a few updates for information, without repeating a version that is part of the name' {
            Mock -ModuleName HelpdeskToolkit Get-ProgramUpdate {
                [PSCustomObject]@{
                    Updates = @(
                        [PSCustomObject]@{ Name = 'Fabrikam Archive'; Id = 'Fabrikam.Archive'; Version = '24.1'; Available = '25.0' }
                        [PSCustomObject]@{ Name = 'Contoso Edit 2.0.19'; Id = 'Contoso.Edit'; Version = '2.0.19'; Available = '2.0.28' }
                    )
                }
            }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Program updates'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be '2 programs can be updated: Contoso Edit 2.0.19 -> 2.0.28, Fabrikam Archive 24.1 -> 25.0'
            $result.Recommendation | Should -Match 'winget upgrade --all'
        }

        It 'is a Warning above the limit and keeps the rest as details' {
            Mock -ModuleName HelpdeskToolkit Get-ProgramUpdate {
                [PSCustomObject]@{
                    Updates = @(1..7 | ForEach-Object { [PSCustomObject]@{ Name = 'Program{0}' -f $_; Id = 'P.{0}' -f $_; Version = '1.0'; Available = '2.0' } })
                }
            }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Program updates'
            $result.Status | Should -Be 'Warning'
            $result.Value | Should -Match '^7 programs can be updated: Program1 1\.0 -> 2\.0, .* and 2 more$'
            $result.Details | Should -Be @('Program6 1.0 -> 2.0', 'Program7 1.0 -> 2.0')
            $result.Recommendation | Should -Match 'security holes'
        }

        It 'passes the time limit of the configuration to winget' {
            Get-SoftwareHealth | Out-Null
            Should -Invoke -ModuleName HelpdeskToolkit Get-ProgramUpdate -ParameterFilter { $TimeoutSeconds -eq 5 }
        }

        It 'says so when winget is not installed' {
            Mock -ModuleName HelpdeskToolkit Get-ProgramUpdate { }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Program updates'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Not checked (winget is not installed for this user)'
        }

        It 'is information, not a problem of this computer, when winget fails' {
            Mock -ModuleName HelpdeskToolkit Get-ProgramUpdate { throw 'winget did not answer within 5 seconds' }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Program updates'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Could not be checked: winget did not answer within 5 seconds'
        }

        It 'does not ask winget at all with -SkipUpdateCheck' {
            $result = Get-SoftwareHealth -SkipUpdateCheck | Where-Object Check -eq 'Program updates'
            $result.Value | Should -Be 'Skipped'
            Should -Invoke -ModuleName HelpdeskToolkit Get-ProgramUpdate -Times 0 -Exactly
        }
    }

    Context 'Microsoft Office and Outlook' {
        It 'has no result where neither is installed' {
            Get-SoftwareHealth | Where-Object { $_.Check -in 'Microsoft Office', 'Outlook data files' } | Should -BeNullOrEmpty
        }

        It 'reports version, platform and update channel of Office' {
            Mock -ModuleName HelpdeskToolkit Get-OfficeInstallation {
                [PSCustomObject]@{ Version = '16.0.17928.20156'; Channel = 'Current Channel'; UpdatesEnabled = $true; Platform = 'x64'; Products = @('O365ProPlusRetail') }
            }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Microsoft Office'
            $result.Status | Should -Be 'Info'
            $result.Value | Should -Be 'Version 16.0.17928.20156 (64-bit), Current Channel, automatic updates on'
        }

        It 'is a Warning when Office does not update itself' {
            Mock -ModuleName HelpdeskToolkit Get-OfficeInstallation {
                [PSCustomObject]@{ Version = '16.0.14332.20000'; Channel = 'Office LTSC 2021'; UpdatesEnabled = $false; Platform = 'x86'; Products = @() }
            }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Microsoft Office'
            $result.Status | Should -Be 'Warning'
            $result.Value | Should -Be 'Version 16.0.14332.20000 (32-bit), Office LTSC 2021, automatic updates off'
            $result.Recommendation | Should -Match 'Enable Updates'
        }

        It 'judges the mailbox files of Outlook by the largest one: <Gigabytes> GB is <Status>' -ForEach @(
            @{ Gigabytes = 8; Status = 'OK' }
            @{ Gigabytes = 31; Status = 'Warning' }
            @{ Gigabytes = 48; Status = 'Critical' }
        ) {
            $bytes = [long]$Gigabytes * 1GB
            Mock -ModuleName HelpdeskToolkit Get-OutlookDataFile {
                [PSCustomObject]@{ Name = 'archive.pst'; Bytes = 2GB }
                [PSCustomObject]@{ Name = 'm.horvat@contoso.com.ost'; Bytes = $bytes }
            }.GetNewClosure()
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Outlook data files'
            $result.Status | Should -Be $Status
            $result.Value | Should -Be ('2 files: m.horvat@contoso.com.ost ({0} GB), archive.pst (2 GB)' -f $Gigabytes)
            $result.Allowed | Should -Be '0 - 25 GB (critical above 45 GB)'
            $result.Typical | Should -Be 'typical mailbox'
        }

        It 'warns about the size limit of Outlook when a file is close to it' {
            Mock -ModuleName HelpdeskToolkit Get-OutlookDataFile { [PSCustomObject]@{ Name = 'big.ost'; Bytes = 48GB } }
            $result = Get-SoftwareHealth | Where-Object Check -eq 'Outlook data files'
            $result.Value | Should -Be '1 file: big.ost (48 GB)'
            $result.Recommendation | Should -Match '50 GB'
        }
    }
}
