# Tests for what the application keeps for itself: settings, the history of reports and
# the text summary, and for the places in Windows that the checks lead to.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $appData = Join-Path -Path $TestDrive -ChildPath 'AppData'
}

Describe 'Get-AppDataPath' {
    It 'returns the folder the tests redirected the application to' {
        InModuleScope HelpdeskToolkit { Get-AppDataPath } | Should -Be $appData
    }

    It 'returns a path inside that folder for a file or folder name' {
        InModuleScope HelpdeskToolkit { Get-AppDataPath -ChildPath 'settings.json' } | Should -Be (Join-Path -Path $appData -ChildPath 'settings.json')
    }

    It 'uses a HelpdeskToolkit folder in the local application data of the user by default' {
        try {
            InModuleScope HelpdeskToolkit { $script:AppDataRoot = $null; Get-AppDataPath } | Should -Be (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'HelpdeskToolkit')
        }
        finally {
            InModuleScope HelpdeskToolkit -Parameters @{ Folder = $appData } { $script:AppDataRoot = $Folder }
        }
    }

    It 'does not create the folder by asking for its path' {
        InModuleScope HelpdeskToolkit { Get-AppDataPath -ChildPath 'Nothing' } | Should -Not -Exist
    }
}

Describe 'Get-AppSetting and Save-AppSetting' {
    BeforeEach {
        if (Test-Path -LiteralPath $appData) {
            Remove-Item -LiteralPath $appData -Recurse -Force
        }
        Mock -ModuleName HelpdeskToolkit Get-UICulture { [cultureinfo]'en-US' }
    }

    It 'returns the defaults when nothing was saved yet' {
        $settings = InModuleScope HelpdeskToolkit { Get-AppSetting }

        $settings.Language | Should -Be 'en'
        $settings.Theme | Should -Be 'System'
        $settings.MonitorIntervalSeconds | Should -Be 2
        $settings.WindowWidth | Should -BeNullOrEmpty
        $settings.WindowMaximized | Should -BeFalse
    }

    It 'starts in Croatian on a Windows that is set to Croatian' {
        Mock -ModuleName HelpdeskToolkit Get-UICulture { [cultureinfo]'hr-HR' }
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).Language | Should -Be 'hr'
    }

    It 'returns what was saved' {
        InModuleScope HelpdeskToolkit {
            $settings = Get-AppSetting
            $settings.Language = 'hr'
            $settings.Theme = 'Dark'
            $settings.MonitorIntervalSeconds = 10
            $settings.WindowWidth = 1400
            Save-AppSetting -Setting $settings
        } | Should -BeTrue

        $loaded = InModuleScope HelpdeskToolkit { Get-AppSetting }
        $loaded.Language | Should -Be 'hr'
        $loaded.Theme | Should -Be 'Dark'
        $loaded.MonitorIntervalSeconds | Should -Be 10
        $loaded.WindowWidth | Should -Be 1400
    }

    It 'creates the application folder and writes UTF-8 without a byte order mark' {
        InModuleScope HelpdeskToolkit { Save-AppSetting -Setting (Get-AppSetting) } | Out-Null
        $file = Join-Path -Path $appData -ChildPath 'settings.json'

        $file | Should -Exist
        [System.IO.File]::ReadAllBytes($file)[0] | Should -Be ([byte][char]'{')
    }

    It 'fills in the default for a setting the file does not have' {
        New-Item -Path $appData -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $appData -ChildPath 'settings.json') -Value '{ "Theme": "Light" }'
        $settings = InModuleScope HelpdeskToolkit { Get-AppSetting }

        $settings.Theme | Should -Be 'Light'
        $settings.Language | Should -Be 'en'
        $settings.MonitorIntervalSeconds | Should -Be 2
    }

    It 'replaces a value that is not allowed with the default' {
        New-Item -Path $appData -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $appData -ChildPath 'settings.json') -Value '{ "Language": "xx", "Theme": "Pink", "MonitorIntervalSeconds": 1 }'
        $settings = InModuleScope HelpdeskToolkit { Get-AppSetting }

        $settings.Language | Should -Be 'en'
        $settings.Theme | Should -Be 'System'
        $settings.MonitorIntervalSeconds | Should -Be 2
    }

    It 'returns the defaults when the file is damaged' {
        New-Item -Path $appData -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $appData -ChildPath 'settings.json') -Value 'this is not json {'
        (InModuleScope HelpdeskToolkit { Get-AppSetting }).Theme | Should -Be 'System'
    }

    It 'returns $false instead of failing when the settings cannot be written' {
        Mock -ModuleName HelpdeskToolkit New-Item { throw 'The disk is full' }
        InModuleScope HelpdeskToolkit { Save-AppSetting -Setting @{ Language = 'en' } } | Should -BeFalse
    }
}

Describe 'Get-WindowTheme' {
    It 'returns the theme the user chose' {
        InModuleScope HelpdeskToolkit {
            Get-WindowTheme -Setting 'Dark' | Should -Be 'Dark'
            Get-WindowTheme -Setting 'Light' | Should -Be 'Light'
        }
    }

    It 'follows Windows: <Expected> when "apps use the light theme" is <Value>' -ForEach @(
        @{ Value = 0; Expected = 'Dark' }
        @{ Value = 1; Expected = 'Light' }
        @{ Value = $null; Expected = 'Light' }
    ) {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { $Value }
        InModuleScope HelpdeskToolkit { Get-WindowTheme -Setting 'System' } | Should -Be $Expected
    }

    It 'reads the setting of the current user' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { 1 }
        InModuleScope HelpdeskToolkit { Get-WindowTheme } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Path -like 'HKCU:\*\Themes\Personalize' -and $Name -eq 'AppsUseLightTheme' }
    }
}

Describe 'Get-CheckAction' {
    It 'finds the place by the full name of the check' {
        $action = InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Startup programs' -Category 'System' }
        $action.Label | Should -Be 'Open Startup apps'
        $action.Target | Should -Be 'ms-settings:startupapps'
        $action.Arguments | Should -Be ''
    }

    It 'finds it by the first part of a name with a drive letter or a device name' {
        InModuleScope HelpdeskToolkit {
            (Get-CheckAction -Check 'Disk (C:)' -Category 'Hardware').Target | Should -Be 'ms-settings:storagesense'
            (Get-CheckAction -Check 'Wi-Fi: Office' -Category 'Network').Target | Should -Be 'ms-settings:network-wifi'
            (Get-CheckAction -Check 'BitLocker (C:)' -Category 'Security').Label | Should -Be 'Open BitLocker'
        }
    }

    It 'falls back to the place of the category' {
        InModuleScope HelpdeskToolkit {
            (Get-CheckAction -Check 'Print Spooler (Spooler)' -Category 'Services').Target | Should -Be 'services.msc'
            (Get-CheckAction -Check 'System log - errors' -Category 'Event Log').Target | Should -Be 'eventvwr.msc'
        }
    }

    It 'returns the arguments of a program that needs them' {
        $action = InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Stability index' -Category 'System' }
        $action.Target | Should -Be 'perfmon.exe'
        $action.Arguments | Should -Be '/rel'
    }

    It 'returns nothing for a check without such a place' {
        InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Computer name' -Category 'System' } | Should -BeNullOrEmpty
    }

    It 'picks the support page by the maker named in the value' {
        $action = InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Warranty and support' -Category 'Specifications' -Value 'Dell Inc.: looked up with the serial number' }
        $action.Label | Should -Be 'Open the support page'
        $action.Target | Should -Be 'https://www.dell.com/support/home'

        (InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Warranty and support' -Value 'LENOVO' }).Target | Should -Match '^https://pcsupport\.lenovo\.com/'
        (InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Warranty and support' -Value 'HP' }).Target | Should -Match '^https://support\.hp\.com/'
        (InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Warranty and support' -Value 'Hewlett-Packard' }).Target | Should -Match '^https://support\.hp\.com/'
    }

    It 'has no support page for a maker that is not listed, or without a value' {
        InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Warranty and support' -Value 'Contoso Computers' } | Should -BeNullOrEmpty
        InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Warranty and support' } | Should -BeNullOrEmpty
        # "HP" inside another word is not Hewlett-Packard.
        InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Warranty and support' -Value 'Alphpa Systems' } | Should -BeNullOrEmpty
    }
}

Describe 'Config\Actions.psd1' {
    BeforeAll {
        $actions = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Actions.psd1')
    }

    It 'gives every entry a label and a target, or a list of makers with their pages' {
        foreach ($key in $actions.Keys) {
            $actions[$key].Label | Should -Not -BeNullOrEmpty -Because "the entry '$key' needs a caption for its button"
            if ($actions[$key].ContainsKey('Vendors')) {
                $actions[$key].Vendors.Count | Should -BeGreaterThan 0 -Because "the entry '$key' needs at least one maker"
            }
            else {
                $actions[$key].Target | Should -Not -BeNullOrEmpty -Because "the entry '$key' needs something to open"
            }
        }
    }

    It 'only opens places of Windows: settings pages, consoles and system programs' {
        foreach ($key in ($actions.Keys | Where-Object { -not $actions[$_].ContainsKey('Vendors') })) {
            $actions[$key].Target | Should -Match '^(ms-settings:[a-z-]+|windowsdefender:(//[a-z]+)?|[A-Za-z0-9]+\.(msc|exe))$' -Because "the entry '$key' must not start an arbitrary command"
        }
    }

    It 'opens the support pages of the makers over https only, without anything of the computer in the address' {
        $vendors = $actions['Warranty and support'].Vendors
        foreach ($maker in $vendors.Keys) {
            { [regex]::new($maker) } | Should -Not -Throw -Because "'$maker' is used as a regular expression"
            $vendors[$maker] | Should -Match '^https://[a-z0-9.-]+\.[a-z]{2,}/[A-Za-z0-9/_-]*$' -Because "the page of '$maker' must be a plain https address"
        }
    }

    It 'starts every label with "Open", so the button says what it does' {
        $actions.Values | ForEach-Object { $_.Label } | Where-Object { $_ -notlike 'Open *' } | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-CheckAction' {
    It 'opens a settings page' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        InModuleScope HelpdeskToolkit { Invoke-CheckAction -Check 'Proxy' -Category 'Network' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'ms-settings:network-proxy' -and -not $ArgumentList }
    }

    It 'passes the arguments of a program on' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        InModuleScope HelpdeskToolkit { Invoke-CheckAction -Check 'Recycle Bin' -Category 'Hardware' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq 'explorer.exe' -and $ArgumentList -eq 'shell:RecycleBinFolder' }
    }

    It 'returns $false and starts nothing for a check without such a place' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        InModuleScope HelpdeskToolkit { Invoke-CheckAction -Check 'Computer name' -Category 'System' } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly
    }

    It 'returns $false when Windows cannot open the place' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'The system cannot find the file specified' }
        InModuleScope HelpdeskToolkit { Invoke-CheckAction -Check 'TPM' -Category 'Security' } | Should -BeFalse
    }
}

Describe 'Save-HealthReportHistory and Get-PreviousHealthReport' {
    BeforeAll {
        # A report of the given day, with one result of the given status.
        function New-TestHistoryReport {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([int]$Day, [string]$Status = 'OK', [string]$Computer = 'TEST-PC-01')

            $report = New-TestReport -Result @(New-TestResult -Category 'System' -Check 'Uptime' -Status $Status -Value "day $Day")
            $report.ComputerName = $Computer
            $report.GeneratedAt = '2026-01-{0:00} 10:30:00' -f $Day
            $report
        }
    }

    BeforeEach {
        if (Test-Path -LiteralPath $appData) {
            Remove-Item -LiteralPath $appData -Recurse -Force
        }
    }

    It 'stores the report as JSON, named after the computer and the time of the check' {
        $path = InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 5) } { Save-HealthReportHistory -Report $Report }

        $path | Should -Be (Join-Path -Path $appData -ChildPath 'History\PCHealth_TEST-PC-01_20260105-103000.json')
        $path | Should -Exist
    }

    It 'returns nothing for the first check of a computer' {
        InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 5) } { Get-PreviousHealthReport -Report $Report } | Should -BeNullOrEmpty
    }

    It 'returns the newest report that is older than the given one' {
        foreach ($day in 3, 5, 9) {
            InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day $day) } { Save-HealthReportHistory -Report $Report } | Out-Null
        }
        $previous = InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 9) } { Get-PreviousHealthReport -Report $Report }

        $previous.GeneratedAt | Should -Be '2026-01-05 10:30:00'
        $previous.Results[0].Value | Should -Be 'day 5'
        $previous.PSObject.TypeNames[0] | Should -Be 'HelpdeskToolkit.HealthReport'
    }

    It 'does not return the report of another computer' {
        InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 3 -Computer 'OTHER-PC') } { Save-HealthReportHistory -Report $Report } | Out-Null
        InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 9) } { Get-PreviousHealthReport -Report $Report } | Should -BeNullOrEmpty
    }

    It 'keeps only the newest reports of a computer and leaves other computers alone' {
        InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 1 -Computer 'OTHER-PC') } { Save-HealthReportHistory -Report $Report -Keep 3 } | Out-Null
        foreach ($day in 1..6) {
            InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day $day) } { Save-HealthReportHistory -Report $Report -Keep 3 } | Out-Null
        }
        $files = (Get-ChildItem -LiteralPath (Join-Path -Path $appData -ChildPath 'History')).Name | Sort-Object

        $files | Should -Be @(
            'PCHealth_OTHER-PC_20260101-103000.json'
            'PCHealth_TEST-PC-01_20260104-103000.json'
            'PCHealth_TEST-PC-01_20260105-103000.json'
            'PCHealth_TEST-PC-01_20260106-103000.json'
        )
    }

    It 'returns nothing instead of failing when the report cannot be stored' {
        Mock -ModuleName HelpdeskToolkit Export-HealthReportJson { throw 'The disk is full' }
        { InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 5) } { Save-HealthReportHistory -Report $Report } } | Should -Not -Throw
    }

    It 'returns nothing when the stored report is damaged' {
        InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 3) } { Save-HealthReportHistory -Report $Report } | Out-Null
        Set-Content -LiteralPath (Join-Path -Path $appData -ChildPath 'History\PCHealth_TEST-PC-01_20260103-103000.json') -Value 'not json {'
        InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestHistoryReport -Day 9) } { Get-PreviousHealthReport -Report $Report } | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-HealthSummaryText' {
    BeforeAll {
        $report = New-TestReport -Result @(
            New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d'
            New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '20 programs' -Recommendation 'Disable some.'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free' -Recommendation 'Free up space.'
            New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
        )
        $lines = (InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthSummaryText -Report $Report }) -split "`r`n"
    }

    It 'starts with the computer, the time, the score and the count per status' {
        $lines[0] | Should -Be 'PC Health Check - TEST-PC-01'
        $lines[1] | Should -Be 'Checked: 2026-01-15 10:30:00  |  Health score: 81 of 100'
        $lines[2] | Should -Be '1 critical, 1 warning, 1 OK, 1 info'
    }

    It 'lists the problems, critical ones first, each with its fix' {
        $lines[4] | Should -Be '[CRITICAL] Hardware - Disk (C:): 2 % free'
        $lines[5] | Should -Be '    Fix: Free up space.'
        $lines[6] | Should -Be '[WARNING] System - Startup programs: 20 programs'
        $lines[7] | Should -Be '    Fix: Disable some.'
    }

    It 'leaves out the results that are no problem' {
        $lines -join "`n" | Should -Not -Match 'Uptime|Proxy'
    }

    It 'ends with the version of the tool and the note about administrator rights' {
        $lines[-1] | Should -Be 'Created with HelpdeskToolkit 9.9.9. Run without administrator rights: checks marked "Requires admin" were skipped.'
    }

    It 'says so when there is no problem, and leaves out the note for an elevated run' {
        $healthy = New-TestReport -Result @(New-TestResult -Status OK) -IsElevated $true
        $text = InModuleScope HelpdeskToolkit -Parameters @{ Report = $healthy } { ConvertTo-HealthSummaryText -Report $Report }

        $text | Should -Match 'No problems found\.'
        $text | Should -Not -Match 'Requires admin'
    }
}

Describe 'Get-LauncherArgument' {
    It 'starts the launcher script that lies next to the module folder' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }
        InModuleScope HelpdeskToolkit { Get-LauncherArgument } | Should -Match '^-NoProfile -ExecutionPolicy Bypass -File ".+\\Start-HelpdeskToolkit\.ps1"$'
    }

    It 'imports the module by its manifest when there is no launcher script' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        InModuleScope HelpdeskToolkit { Get-LauncherArgument } | Should -Match 'Import-Module ''.+HelpdeskToolkit\.psd1''; Show-PCHealthCheck'
    }
}

Describe 'Lock-AppFile' {
    BeforeAll {
        $file = Join-Path -Path $TestDrive -ChildPath 'application.ico'
        Set-Content -LiteralPath $file -Value 'icon'
    }

    It 'keeps the file open, so nobody can replace or delete it' {
        $lock = InModuleScope HelpdeskToolkit -Parameters @{ Path = $file } { Lock-AppFile -Path $Path }
        try {
            $lock | Should -BeOfType [System.IO.FileStream]
            # What the installer tries before an update: the file for itself alone.
            { [System.IO.File]::Open($file, 'Open', 'ReadWrite', 'None').Dispose() } | Should -Throw
            { Remove-Item -LiteralPath $file -Force -ErrorAction Stop } | Should -Throw
        }
        finally {
            $lock.Dispose()
        }
    }

    It 'lets other programs read the file meanwhile' {
        $lock = InModuleScope HelpdeskToolkit -Parameters @{ Path = $file } { Lock-AppFile -Path $Path }
        try {
            [System.IO.File]::Open($file, 'Open', 'Read', 'Read').Dispose()
            Get-Content -LiteralPath $file | Should -Be 'icon'
        }
        finally {
            $lock.Dispose()
        }
    }

    It 'gives the file free again when it is closed' {
        $lock = InModuleScope HelpdeskToolkit -Parameters @{ Path = $file } { Lock-AppFile -Path $Path }
        $lock.Dispose()
        { [System.IO.File]::Open($file, 'Open', 'ReadWrite', 'None').Dispose() } | Should -Not -Throw
    }

    It 'keeps the icon of the application open by default' {
        $lock = InModuleScope HelpdeskToolkit { Lock-AppFile }
        try {
            $lock.Name | Should -BeLike '*\Assets\HelpdeskToolkit.ico'
        }
        finally {
            $lock.Dispose()
        }
    }

    It 'returns nothing for a file that does not exist, instead of stopping the window' {
        InModuleScope HelpdeskToolkit { Lock-AppFile -Path 'Q:\no-such-folder\missing.ico' } | Should -BeNullOrEmpty
    }
}
