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
    }

    Context 'on a typical computer' {
        BeforeAll {
            $results = Get-SoftwareHealth
        }

        It 'returns five results in the Software category' {
            @($results).Count | Should -Be 5
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
}
