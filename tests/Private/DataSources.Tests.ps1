# Tests for the small functions that read one source each for the newer checks:
# winget, the list of programs without support, Microsoft Office, the privacy records
# of Windows, the upgrade assessment and the logs of the memory test and of the System File
# Checker.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    # A registry key as Get-ChildItem returns it: a name, a path and values.
    function New-TestKey {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Name, [hashtable]$Value = @{}, [string]$Path = '')

        $key = [PSCustomObject]@{ PSChildName = $Name; PSPath = $(if ($Path) { $Path } else { $Name }); Values = $Value }
        $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($Name) $this.Values[$Name] }
        $key
    }
}

Describe 'ConvertFrom-WingetTable' {
    BeforeAll {
        $table = @(
            'Name                     Id                    Version    Available'
            '-------------------------------------------------------------------'
            'Contoso Edit 2.0.19      Contoso.Edit          2.0.19     2.0.28'
            'Fabrikam Archive Tool    Fabrikam.Archive      24.1       25.0 (beta)'
            '2 upgrades available.'
            ''
            'The following packages have an upgrade available, but require explicit targeting for upgrade:'
            'Name            Id                Version  Available'
            '-----------------------------------------------------'
            'Northwind Sync  Northwind.Sync    1.0      1.1'
        ) -join "`r`n"
        $rows = @(InModuleScope HelpdeskToolkit -Parameters @{ Text = $table } { ConvertFrom-WingetTable -Text $Text })
    }

    It 'returns one object per row, cut at the positions of the headings' {
        $rows.Count | Should -Be 3
        $rows[0].Name | Should -Be 'Contoso Edit 2.0.19'
        $rows[0].Id | Should -Be 'Contoso.Edit'
        $rows[0].Version | Should -Be '2.0.19'
        $rows[0].Available | Should -Be '2.0.28'
    }

    It 'keeps a version that contains a space' {
        $rows[1].Available | Should -Be '25.0 (beta)'
    }

    It 'stops at the summary line and reads a second table as well' {
        $rows.Id | Should -Be @('Contoso.Edit', 'Fabrikam.Archive', 'Northwind.Sync')
    }

    It 'ignores a progress animation in front of the headings' {
        $text = "   - `r   \ `rName      Id          Version  Available`r`n----------------------------------------`r`nContoso   Contoso.App 1.0      2.0"
        $row = InModuleScope HelpdeskToolkit -Parameters @{ Text = $text } { ConvertFrom-WingetTable -Text $Text }
        $row.Id | Should -Be 'Contoso.App'
        $row.Available | Should -Be '2.0'
    }

    It 'does not depend on the language of the headings' {
        $text = "Nom       ID          Version  Disponible`r`n----------------------------------------`r`nContoso   Contoso.App 1.0      2.0"
        (InModuleScope HelpdeskToolkit -Parameters @{ Text = $text } { ConvertFrom-WingetTable -Text $Text }).Version | Should -Be '1.0'
    }

    It 'returns nothing for a text without a table' {
        InModuleScope HelpdeskToolkit { ConvertFrom-WingetTable -Text 'No installed package found matching input criteria.' } | Should -BeNullOrEmpty
        InModuleScope HelpdeskToolkit { ConvertFrom-WingetTable -Text '' } | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-Winget and Get-ProgramUpdate' {
    It 'returns nothing when winget is not installed for the user' {
        $original = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = Join-Path -Path $TestDrive -ChildPath 'NoWinget'
            InModuleScope HelpdeskToolkit { Invoke-Winget -Arguments 'upgrade' } | Should -BeNullOrEmpty
            InModuleScope HelpdeskToolkit { Get-ProgramUpdate } | Should -BeNullOrEmpty
        }
        finally {
            $env:LOCALAPPDATA = $original
        }
    }

    It 'only asks for the list and never for an installation' {
        Mock -ModuleName HelpdeskToolkit Invoke-Winget { [PSCustomObject]@{ ExitCode = 0; Output = '' } }
        InModuleScope HelpdeskToolkit { Get-ProgramUpdate -TimeoutSeconds 7 } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-Winget -Times 1 -Exactly -ParameterFilter {
            $Arguments -eq 'upgrade --source winget --disable-interactivity' -and $Arguments -notmatch '--all|install|uninstall' -and $TimeoutSeconds -eq 7
        }
    }

    It 'returns the updates winget lists' {
        Mock -ModuleName HelpdeskToolkit Invoke-Winget {
            [PSCustomObject]@{ ExitCode = 0; Output = "Name      Id          Version  Available`r`n----------------------------------------`r`nContoso   Contoso.App 1.0      2.0`r`n1 upgrades available." }
        }
        $result = InModuleScope HelpdeskToolkit { Get-ProgramUpdate }
        @($result.Updates).Count | Should -Be 1
        $result.Updates[0].Name | Should -Be 'Contoso'
    }

    It 'returns an empty list when everything is up to date' {
        Mock -ModuleName HelpdeskToolkit Invoke-Winget { [PSCustomObject]@{ ExitCode = 0; Output = 'No installed package found matching input criteria.' } }
        $result = InModuleScope HelpdeskToolkit { Get-ProgramUpdate }
        $result | Should -Not -BeNullOrEmpty
        @($result.Updates).Count | Should -Be 0
    }

    It 'throws with the message of winget when winget fails' {
        Mock -ModuleName HelpdeskToolkit Invoke-Winget { [PSCustomObject]@{ ExitCode = -1978335212; Output = "`r`nFailed when searching source: winget`r`n" } }
        { InModuleScope HelpdeskToolkit { Get-ProgramUpdate } } | Should -Throw '*Failed when searching source: winget*'
    }
}

Describe 'Get-UnsupportedProgram' {
    BeforeAll {
        function Find-TestUnsupported {
            param([string]$Name, [string]$Version = '')
            $program = [PSCustomObject]@{ Name = $Name; Version = $Version }
            InModuleScope HelpdeskToolkit -Parameters @{ Program = $program } { Get-UnsupportedProgram -Program @($Program) }
        }
    }

    AfterEach {
        # The list is cached; a test that replaced it must not leak into the next one.
        InModuleScope HelpdeskToolkit { $script:EndOfLife = $null }
    }

    It 'finds <Name> as a <Level>' -ForEach @(
        @{ Name = 'Adobe Flash Player 32 NPAPI'; Level = 'Warning' }
        @{ Name = 'Microsoft Office Professional Plus 2016'; Level = 'Warning' }
        @{ Name = 'Microsoft Silverlight'; Level = 'Warning' }
        @{ Name = 'Skype version 8.110'; Level = 'Warning' }
        @{ Name = 'Java 7 Update 80'; Level = 'Warning' }
        @{ Name = 'Python 3.8.10 (64-bit)'; Level = 'Info' }
        @{ Name = 'Microsoft Windows Desktop Runtime - 6.0.25 (x64)'; Level = 'Info' }
        @{ Name = 'Microsoft ASP.NET Core 3.1.32 - Shared Framework (x64)'; Level = 'Info' }
    ) {
        (Find-TestUnsupported -Name $Name).Level | Should -Be $Level
    }

    It 'leaves <_> alone' -ForEach @(
        'Microsoft 365 Apps for enterprise - en-us'
        'Skype for Business Basic 2016'
        'Java 8 Update 401 (64-bit)'
        'Python 3.13.1 (64-bit)'
        'Microsoft SQL Server 2012 Native Client'
        'Microsoft Visual C++ 2010 x64 Redistributable - 10.0.40219'
        'Microsoft Windows Desktop Runtime - 10.0.1 (x64)'
    ) {
        Find-TestUnsupported -Name $_ | Should -BeNullOrEmpty
    }

    It 'adds the version to a name that does not contain one, and gives the end date' {
        $found = Find-TestUnsupported -Name 'Adobe Flash Player 32 NPAPI' -Version '32.0.0.465'
        $found.Name | Should -Be 'Adobe Flash Player 32 NPAPI 32.0.0.465'
        $found.EndDate | Should -Be ([datetime]'2020-12-31')

        (Find-TestUnsupported -Name 'Python 3.8.10 (64-bit)' -Version '3.8.10150.0').Name | Should -Be 'Python 3.8.10 (64-bit)'
    }

    It 'only counts an entry from the day after its end date' {
        InModuleScope HelpdeskToolkit {
            $script:EndOfLife = @(
                @{ Match = '^Ended Yesterday'; End = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd'); Level = 'Warning' }
                @{ Match = '^Ends Today'; End = (Get-Date).ToString('yyyy-MM-dd'); Level = 'Warning' }
                @{ Match = '^Ends Next Month'; End = (Get-Date).AddDays(30).ToString('yyyy-MM-dd'); Level = 'Warning' }
            )
        }
        $programs = 'Ended Yesterday Tool', 'Ends Today Tool', 'Ends Next Month Tool' | ForEach-Object { [PSCustomObject]@{ Name = $_; Version = '' } }
        $found = @(InModuleScope HelpdeskToolkit -Parameters @{ Program = $programs } { Get-UnsupportedProgram -Program $Program })
        $found.Name | Should -Be 'Ended Yesterday Tool'
    }

    It 'returns nothing for an empty list of programs' {
        InModuleScope HelpdeskToolkit { Get-UnsupportedProgram -Program @() } | Should -BeNullOrEmpty
    }
}

Describe 'Config\EndOfLife.psd1' {
    BeforeAll {
        $products = @((Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit\Config\EndOfLife.psd1')).Products)
    }

    It 'lists products' {
        $products.Count | Should -BeGreaterThan 10
    }

    It 'gives every entry a valid expression, a date and a level' {
        foreach ($product in $products) {
            { [regex]::new($product.Match) } | Should -Not -Throw -Because "'$($product.Match)' is used as a regular expression"
            $product.Match | Should -Match '^\^' -Because "'$($product.Match)' should fit the start of a name, not any part of it"
            { [datetime]::ParseExact($product.End, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture) } | Should -Not -Throw
            $product.Level | Should -BeIn 'Warning', 'Info'
        }
    }
}

Describe 'Get-OfficeInstallation' {
    It 'returns nothing when Click-to-Run Office is not installed' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { }
        InModuleScope HelpdeskToolkit { Get-OfficeInstallation } | Should -BeNullOrEmpty
    }

    Context 'with Microsoft 365 Apps installed' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue { }
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'VersionToReport' } { '16.0.17928.20156' }
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'CDNBaseUrl' } { 'http://officecdn.microsoft.com/pr/492350F6-3A01-4F97-B9C0-C7C6DDF67D60' }
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'Platform' } { 'x64' }
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'ProductReleaseIds' } { 'O365ProPlusRetail,VisioProRetail' }
        }

        It 'reads version, platform and products, and names the update channel' {
            $office = InModuleScope HelpdeskToolkit { Get-OfficeInstallation }
            $office.Version | Should -Be '16.0.17928.20156'
            $office.Channel | Should -Be 'Current Channel'
            $office.Platform | Should -Be 'x64'
            $office.Products | Should -Be @('O365ProPlusRetail', 'VisioProRetail')
            $office.UpdatesEnabled | Should -BeTrue
        }

        It 'says so when the updates were switched off in Office' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'UpdatesEnabled' } { 'False' }
            (InModuleScope HelpdeskToolkit { Get-OfficeInstallation }).UpdatesEnabled | Should -BeFalse
        }

        It 'says so when a policy switches the updates off' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'EnableAutomaticUpdates' } { 0 }
            (InModuleScope HelpdeskToolkit { Get-OfficeInstallation }).UpdatesEnabled | Should -BeFalse
        }

        It 'does not guess a channel it does not know' {
            Mock -ModuleName HelpdeskToolkit Get-RegistryValue -ParameterFilter { $Name -eq 'CDNBaseUrl' } { 'http://officecdn.microsoft.com/pr/00000000-0000-0000-0000-000000000000' }
            (InModuleScope HelpdeskToolkit { Get-OfficeInstallation }).Channel | Should -Be 'Unknown channel'
        }
    }
}

Describe 'Get-OutlookDataFile' {
    It 'returns the mailbox files of the Outlook folder with their sizes, and nothing else' {
        $original = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = Join-Path -Path $TestDrive -ChildPath 'Local'
            $folder = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Outlook'
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'test-mailbox-a.ost') -Value ('x' * 2000) -NoNewline
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'test-archive-b.pst') -Value ('x' * 500) -NoNewline
            Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'test-notes.xml') -Value 'not a mailbox'

            $files = @(InModuleScope HelpdeskToolkit { Get-OutlookDataFile } | Where-Object { $_.Name -like 'test-*' })
            $files.Name | Sort-Object | Should -Be @('test-archive-b.pst', 'test-mailbox-a.ost')
            ($files | Where-Object Name -eq 'test-mailbox-a.ost').Bytes | Should -Be 2000
        }
        finally {
            $env:LOCALAPPDATA = $original
        }
    }
}

Describe 'Get-CapabilityUsage' {
    BeforeAll {
        $used = ([datetime]'2026-01-10 08:00').ToFileTime()
        $ended = ([datetime]'2026-01-10 08:45').ToFileTime()
        $older = ([datetime]'2025-12-01 12:00').ToFileTime()

        Mock -ModuleName HelpdeskToolkit Get-ChildItem {
            New-TestKey -Name 'Contoso.Meetings_8wekyb3d8bbwe' -Value @{ LastUsedTimeStart = $used; LastUsedTimeStop = $ended }
            New-TestKey -Name 'Never.Used_abcdefghijklm' -Value @{}
            New-TestKey -Name 'NonPackaged'
        }
        Mock -ModuleName HelpdeskToolkit Get-ChildItem -ParameterFilter { $Path -like '*\NonPackaged' } {
            New-TestKey -Name 'C:#Program Files#Contoso#record.exe' -Value @{ LastUsedTimeStart = $used; LastUsedTimeStop = 0 }
            New-TestKey -Name 'C:#Users#m.horvat#AppData#Local#Chat#app-1.0.1#chat.exe' -Value @{ LastUsedTimeStart = $older; LastUsedTimeStop = $older }
            New-TestKey -Name 'C:#Users#m.horvat#AppData#Local#Chat#app-1.0.2#chat.exe' -Value @{ LastUsedTimeStart = $used; LastUsedTimeStop = $ended }
        }
        $usage = @(InModuleScope HelpdeskToolkit { Get-CapabilityUsage -Capability microphone })
    }

    It 'reads the list of the right device from the registry of the user' {
        Should -Invoke -ModuleName HelpdeskToolkit Get-ChildItem -Scope Describe -ParameterFilter { $Path -like 'HKCU:\*\ConsentStore\microphone' }
    }

    It 'names a Store app after its package, without the publisher code' {
        $app = $usage | Where-Object Program -eq 'Contoso.Meetings'
        $app.LastUsed | Should -Be ([datetime]'2026-01-10 08:45')
        $app.InUse | Should -BeFalse
    }

    It 'names a program after its file and notices that it is using the device right now' {
        ($usage | Where-Object Program -eq 'record.exe').InUse | Should -BeTrue
    }

    It 'returns a program that exists in several versions once, with its newest use' {
        $chat = @($usage | Where-Object Program -eq 'chat.exe')
        $chat.Count | Should -Be 1
        $chat[0].LastUsed | Should -Be ([datetime]'2026-01-10 08:45')
    }

    It 'leaves out what never used the device' {
        $usage.Program | Should -Not -Contain 'Never.Used'
        $usage.Count | Should -Be 3
    }
}

Describe 'Get-UsbStorageDevice' {
    It 'returns the name of every device, falling back to the model key' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem -ParameterFilter { $Path -like '*\Enum\USBSTOR' } {
            New-TestKey -Name 'Disk&Ven_Contoso&Prod_Stick_Pro&Rev_1.00' -Path 'model-a'
            New-TestKey -Name 'Disk&Ven_Fabrikam&Prod_Drive&Rev_2.0' -Path 'model-b'
        }
        Mock -ModuleName HelpdeskToolkit Get-ChildItem -ParameterFilter { $Path -eq 'model-a' } {
            New-TestKey -Name 'SERIAL1&0' -Value @{ FriendlyName = 'Contoso Stick Pro USB Device' }
            New-TestKey -Name 'SERIAL2&0' -Value @{ FriendlyName = 'Contoso Stick Pro USB Device' }
        }
        Mock -ModuleName HelpdeskToolkit Get-ChildItem -ParameterFilter { $Path -eq 'model-b' } {
            New-TestKey -Name 'SERIAL3&0'
        }

        InModuleScope HelpdeskToolkit { Get-UsbStorageDevice } | Should -Be @('Contoso Stick Pro', 'Contoso Stick Pro', 'Fabrikam Drive')
    }

    It 'returns nothing when no device was ever connected' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem { }
        InModuleScope HelpdeskToolkit { Get-UsbStorageDevice } | Should -BeNullOrEmpty
    }
}

Describe 'Get-DeviceGuardService' {
    It 'returns the numbers of the running protection features' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { [PSCustomObject]@{ SecurityServicesRunning = [uint32[]]@(1, 2) } }
        InModuleScope HelpdeskToolkit { Get-DeviceGuardService } | Should -Be @(1, 2)
        Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_DeviceGuard' -and $Namespace -eq 'root/Microsoft/Windows/DeviceGuard' }
    }

    It 'returns 0 when nothing runs, which is different from "unknown"' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { [PSCustomObject]@{ SecurityServicesRunning = [uint32[]]@(0) } }
        InModuleScope HelpdeskToolkit { Get-DeviceGuardService } | Should -Be 0
    }

    It 'returns nothing when Windows does not have the class' {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw 'Invalid namespace' }
        InModuleScope HelpdeskToolkit { Get-DeviceGuardService } | Should -BeNullOrEmpty
    }
}

Describe 'Get-BootDegradation' {
    BeforeAll {
        function New-TestBootEvent {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds objects in memory.')]
            param([int]$Id, [hashtable]$Data)

            $nodes = ($Data.Keys | ForEach-Object { '<Data Name="{0}">{1}</Data>' -f $_, $Data[$_] }) -join ''
            $entry = [PSCustomObject]@{ Id = $Id; TimeCreated = [datetime]'2026-01-12 08:01'; Xml = "<Event><EventData>$nodes</EventData></Event>" }
            $entry | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $this.Xml }
            $entry
        }
    }

    It 'names the culprit by its friendly name, with its kind and delay' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            New-TestBootEvent -Id 101 -Data @{ Name = 'sync.exe'; FriendlyName = 'Contoso Sync'; TotalTime = 9000; DegradationTime = 6200 }
            New-TestBootEvent -Id 102 -Data @{ Name = 'ctsdrv'; FriendlyName = ''; DegradationTime = 3100 }
            New-TestBootEvent -Id 107 -Data @{ DegradationTime = 12000 }
        }
        $delays = @(InModuleScope HelpdeskToolkit { Get-BootDegradation -Since (Get-Date).AddDays(-30) })

        $delays.Count | Should -Be 3
        $delays[0].Name | Should -Be 'Contoso Sync'
        $delays[0].Kind | Should -Be 'program'
        $delays[0].Milliseconds | Should -Be 6200
        $delays[1].Name | Should -Be 'ctsdrv'
        $delays[1].Kind | Should -Be 'driver'
        # Policies have no name of their own.
        $delays[2].Name | Should -Be 'computer policy'
    }

    It 'asks the performance log for the delay events since the given time' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { }
        $since = (Get-Date).AddDays(-30)
        InModuleScope HelpdeskToolkit -Parameters @{ Since = $since } { Get-BootDegradation -Since $Since } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Get-WinEvent -Times 1 -Exactly -ParameterFilter {
            $FilterHashtable[0].LogName -eq 'Microsoft-Windows-Diagnostics-Performance/Operational' -and
            $FilterHashtable[0].Id -contains 101 -and $FilterHashtable[0].Id -notcontains 100 -and $FilterHashtable[0].StartTime -eq $since
        }
    }

    It 'returns nothing when Windows recorded no delay' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound') }
        InModuleScope HelpdeskToolkit { Get-BootDegradation -Since (Get-Date).AddDays(-30) } | Should -BeNullOrEmpty
    }

    It 'passes on any other error, so the check can report it' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { throw 'The event log service is not running' }
        { InModuleScope HelpdeskToolkit { Get-BootDegradation -Since (Get-Date).AddDays(-30) } } | Should -Throw '*not running*'
    }
}

Describe 'Get-UpgradeIndicator' {
    It 'returns the verdict of the newest release Windows has judged' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem {
            New-TestKey -Name 'NI22H2' -Value @{ UpgEx = 'Red'; RedReason = [string[]]@('CpuFms', 'Tpm') }
            New-TestKey -Name 'GE24H2' -Value @{ UpgEx = 'Red'; RedReason = [string[]]@('CpuFms') }
            New-TestKey -Name 'UNV' -Value @{ UpgEx = ''; RedReason = $null }
        }
        $indicator = InModuleScope HelpdeskToolkit { Get-UpgradeIndicator }
        $indicator.Release | Should -Be 'GE24H2'
        $indicator.Verdict | Should -Be 'Red'
        $indicator.Reasons | Should -Be @('CpuFms')
    }

    It 'has no reasons when nothing stands in the way' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem { New-TestKey -Name 'GE25H2' -Value @{ UpgEx = 'Green'; RedReason = [string[]]@('None') } }
        $indicator = InModuleScope HelpdeskToolkit { Get-UpgradeIndicator }
        $indicator.Verdict | Should -Be 'Green'
        @($indicator.Reasons).Count | Should -Be 0
    }

    It 'returns nothing when Windows has not judged the computer' {
        Mock -ModuleName HelpdeskToolkit Get-ChildItem { }
        InModuleScope HelpdeskToolkit { Get-UpgradeIndicator } | Should -BeNullOrEmpty
    }
}

Describe 'Get-Windows11Readiness' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } {
            [PSCustomObject]@{ NumberOfCores = 4; AddressWidth = 64; MaxClockSpeed = 2400 }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_ComputerSystem' } {
            [PSCustomObject]@{ TotalPhysicalMemory = 8GB - 100MB }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } {
            [PSCustomObject]@{ Size = 256GB }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Tpm' } {
            [PSCustomObject]@{ SpecVersion = '2.0, 0, 1.59' }
        }
        Mock -ModuleName HelpdeskToolkit Get-SecureBootState { 'Enabled' }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        Mock -ModuleName HelpdeskToolkit Get-UpgradeIndicator { [PSCustomObject]@{ Release = 'GE24H2'; Verdict = 'Green'; Reasons = @() } }
    }

    It 'is ready when every requirement is met' {
        $readiness = InModuleScope HelpdeskToolkit { Get-Windows11Readiness }
        $readiness.Ready | Should -BeTrue
        $readiness.Requirements.Name | Should -Be @('Processor (64-bit, 2 cores, 1 GHz)', 'Memory (4 GB)', 'System drive (64 GB)', 'UEFI with Secure Boot', 'TPM 2.0', 'Assessment by Windows')
        $readiness.Requirements.Met | Sort-Object -Unique | Should -Be $true
        ($readiness.Requirements | Where-Object Name -eq 'TPM 2.0').Value | Should -Be 'version 2.0'
    }

    It 'accepts Secure Boot that is supported but switched off' {
        Mock -ModuleName HelpdeskToolkit Get-SecureBootState { 'Disabled' }
        $requirement = (InModuleScope HelpdeskToolkit { Get-Windows11Readiness }).Requirements | Where-Object Name -eq 'UEFI with Secure Boot'
        $requirement.Met | Should -BeTrue
        $requirement.Value | Should -Be 'supported, switched off'
    }

    It 'is not ready with <Name>' -ForEach @(
        @{ Name = 'too little memory'; Class = 'Win32_ComputerSystem'; Object = @{ TotalPhysicalMemory = 2GB }; Requirement = 'Memory (4 GB)' }
        @{ Name = 'a small system drive'; Class = 'Win32_LogicalDisk'; Object = @{ Size = 32GB }; Requirement = 'System drive (64 GB)' }
        @{ Name = 'a single core'; Class = 'Win32_Processor'; Object = @{ NumberOfCores = 1; AddressWidth = 64; MaxClockSpeed = 2400 }; Requirement = 'Processor (64-bit, 2 cores, 1 GHz)' }
        @{ Name = 'an old TPM'; Class = 'Win32_Tpm'; Object = @{ SpecVersion = '1.2, 2, 3' }; Requirement = 'TPM 2.0' }
    ) {
        $filter = [scriptblock]::Create("`$ClassName -eq '$Class'")
        $data = [PSCustomObject]$Object
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter $filter { $data }.GetNewClosure()

        $readiness = InModuleScope HelpdeskToolkit { Get-Windows11Readiness }
        $readiness.Ready | Should -BeFalse
        ($readiness.Requirements | Where-Object Name -eq $Requirement).Met | Should -BeFalse
    }

    It 'is not ready in legacy BIOS mode' {
        Mock -ModuleName HelpdeskToolkit Get-SecureBootState { 'Unsupported' }
        (InModuleScope HelpdeskToolkit { Get-Windows11Readiness }).Ready | Should -BeFalse
    }

    It 'is not ready when Windows names a processor that is not supported, and says so in words' {
        Mock -ModuleName HelpdeskToolkit Get-UpgradeIndicator { [PSCustomObject]@{ Release = 'GE24H2'; Verdict = 'Red'; Reasons = @('CpuFms', 'SomethingNew') } }
        $readiness = InModuleScope HelpdeskToolkit { Get-Windows11Readiness }
        $readiness.Ready | Should -BeFalse
        ($readiness.Requirements | Where-Object Name -eq 'Assessment by Windows').Value | Should -Be 'processor model not supported, SomethingNew'
    }

    Context 'without administrator rights' {
        BeforeAll {
            Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        }

        It 'does not ask for the TPM and still says yes when Windows itself does' {
            $readiness = InModuleScope HelpdeskToolkit { Get-Windows11Readiness }
            Should -Invoke -ModuleName HelpdeskToolkit Get-CimInstance -Times 0 -Exactly -ParameterFilter { $ClassName -eq 'Win32_Tpm' }
            ($readiness.Requirements | Where-Object Name -eq 'TPM 2.0').Met | Should -BeNullOrEmpty
            $readiness.Ready | Should -BeTrue
        }

        It 'leaves the answer open when Windows has no assessment either' {
            Mock -ModuleName HelpdeskToolkit Get-UpgradeIndicator { }
            $readiness = InModuleScope HelpdeskToolkit { Get-Windows11Readiness }
            $readiness.Ready | Should -BeNullOrEmpty
            ($readiness.Requirements | Where-Object Name -eq 'Assessment by Windows').Value | Should -Match 'processor model is not checked'
        }
    }
}

Describe 'Get-MemoryDiagnosticResult' {
    It 'reports a test without errors' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { [PSCustomObject]@{ Id = 1101; Level = 4; TimeCreated = [datetime]'2026-01-11 07:30' } }
        $result = InModuleScope HelpdeskToolkit { Get-MemoryDiagnosticResult }
        $result.HasErrors | Should -BeFalse
        $result.TestedAt | Should -Be ([datetime]'2026-01-11 07:30')
        Should -Invoke -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter {
            $FilterHashtable[0].ProviderName -eq 'Microsoft-Windows-MemoryDiagnostics-Results' -and $MaxEvents -eq 1
        }
    }

    It 'reports a test that found errors (event <_>)' -ForEach @(1102, 1202) {
        $id = $_
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { [PSCustomObject]@{ Id = $id; Level = 4; TimeCreated = Get-Date } }.GetNewClosure()
        (InModuleScope HelpdeskToolkit { Get-MemoryDiagnosticResult }).HasErrors | Should -BeTrue
    }

    It 'returns nothing when the memory was never tested' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound') }
        InModuleScope HelpdeskToolkit { Get-MemoryDiagnosticResult } | Should -BeNullOrEmpty
    }
}

Describe 'Get-SystemFileCheckResult' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Test-Path { $true }

        # The lines Select-String finds in the servicing log.
        function Register-TestServicingLog {
            param([string[]]$Line)
            $found = @($Line | ForEach-Object { [PSCustomObject]@{ Line = $_ } })
            Mock -ModuleName HelpdeskToolkit Select-String { $found }.GetNewClosure()
        }
    }

    It 'reports a check that found nothing' {
        Register-TestServicingLog -Line @(
            '2026-01-09 21:00:01, Info                  CSI    00000007 [SR] Verifying 100 components'
            '2026-01-09 21:00:01, Info                  CSI    00000008 [SR] Beginning Verify and Repair transaction'
            '2026-01-09 21:04:40, Info                  CSI    00000a11 [SR] Verify complete'
            '2026-01-09 21:04:41, Info                  CSI    00000a12 [SR] Repairing 0 components'
        )
        $result = InModuleScope HelpdeskToolkit { Get-SystemFileCheckResult }
        $result.Verdict | Should -Be 'Clean'
        $result.CheckedAt | Should -Be ([datetime]'2026-01-09 21:04:41')
    }

    It 'reports files that were repaired' {
        Register-TestServicingLog -Line @(
            '2026-01-09 21:04:41, Info                  CSI    00000a12 [SR] Repairing 1 components'
            '2026-01-09 21:04:42, Info                  CSI    00000a13 [SR] Repairing corrupted file \??\C:\WINDOWS\System32\contoso.dll from store'
            '2026-01-09 21:04:43, Info                  CSI    00000a14 [SR] Repair complete'
        )
        (InModuleScope HelpdeskToolkit { Get-SystemFileCheckResult }).Verdict | Should -Be 'Repaired'
    }

    It 'reports files that could not be repaired' {
        Register-TestServicingLog -Line @(
            '2026-01-09 21:04:42, Info                  CSI    00000a13 [SR] Repairing corrupted file \??\C:\WINDOWS\System32\contoso.dll from store'
            '2026-01-09 21:04:43, Info                  CSI    00000a14 [SR] Cannot repair member file [l:11]"contoso.dll" of Contoso-Component, version 10.0.1'
        )
        (InModuleScope HelpdeskToolkit { Get-SystemFileCheckResult }).Verdict | Should -Be 'Unrepaired'
    }

    It 'judges the newest check only' {
        Register-TestServicingLog -Line @(
            '2025-11-02 10:00:00, Info                  CSI    00000a14 [SR] Cannot repair member file [l:11]"contoso.dll" of Contoso-Component, version 10.0.1'
            '2026-01-09 21:04:40, Info                  CSI    00000a11 [SR] Verify complete'
        )
        (InModuleScope HelpdeskToolkit { Get-SystemFileCheckResult }).Verdict | Should -Be 'Clean'
    }

    It 'returns nothing when the log has no entry of the checker' {
        Register-TestServicingLog -Line @()
        InModuleScope HelpdeskToolkit { Get-SystemFileCheckResult } | Should -BeNullOrEmpty
    }

    It 'returns nothing when there is no servicing log' {
        Mock -ModuleName HelpdeskToolkit Test-Path { $false }
        InModuleScope HelpdeskToolkit { Get-SystemFileCheckResult } | Should -BeNullOrEmpty
    }
}
