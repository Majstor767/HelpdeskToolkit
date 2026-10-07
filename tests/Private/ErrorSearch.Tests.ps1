# Tests for the web search an error leads to when Windows has no place to fix it: a
# program that crashes, an update that fails, a blue screen, an error code. They cover
# the address of the search, what may become part of it, the links on the result cards,
# on the Timeline page and in the HTML report.
#
# No test opens a browser or touches the network: an address is only built and compared.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $help = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Help.psd1')

    # The address of a search for the given words, as the tool must build it.
    function Get-TestSearch {
        param([string]$Words)
        $help.SearchUrl -f [uri]::EscapeDataString($Words)
    }

    function Get-TestLink {
        param([string]$Check, [string]$Category = '', [string[]]$Detail = @(), [string]$Value = '', [string]$ErrorText = '')
        InModuleScope HelpdeskToolkit -Parameters @{ Check = $Check; Category = $Category; Detail = $Detail; Value = $Value; ErrorText = $ErrorText } {
            Get-CheckHelpLink -Check $Check -Category $Category -Detail $Detail -Value $Value -ErrorText $ErrorText
        }
    }

    function Get-TestItem {
        param($Result)
        InModuleScope HelpdeskToolkit -Parameters @{ Result = $Result } { $Result | ConvertTo-WindowItem }
    }

    function Get-TestName {
        param([string]$Name)
        InModuleScope HelpdeskToolkit -Parameters @{ Name = $Name } { ConvertTo-SearchName -Name $Name }
    }

    function Get-TestTimelineLink {
        param($Entry)
        InModuleScope HelpdeskToolkit -Parameters @{ Entry = $Entry } { Get-TimelineHelpLink -Entry $Entry }
    }

    # An entry of the time line as a report carries it.
    function New-TestEntry {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Kind, [string]$Title = '', [string]$Code = '', [string]$Level = 'Problem', [string]$Time = '2026-01-15 10:30', [int]$Count = 1)

        [PSCustomObject]@{ Time = $Time; Level = $Level; Kind = $Kind; Title = $Title; Count = $Count; Code = $Code }
    }

    # A record as Win32_ReliabilityRecords returns it.
    function New-TestRecord {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Source, [int]$Id, [string]$Product = '', [string]$Message = '', [int]$HoursAgo = 30)

        [PSCustomObject]@{ SourceName = $Source; EventIdentifier = $Id; TimeGenerated = (Get-Date).AddHours(-$HoursAgo); ProductName = $Product; Message = $Message }
    }

    # Runs a script with another signed-in user and computer name.
    function Invoke-TestAsUser {
        param([string]$User, [string]$Computer, [scriptblock]$Script)
        $before = $env:USERNAME, $env:COMPUTERNAME
        try {
            $env:USERNAME = $User
            $env:COMPUTERNAME = $Computer
            & $Script
        }
        finally {
            $env:USERNAME, $env:COMPUTERNAME = $before
        }
    }
}

Describe 'The search engine' {
    It 'is Google, over https, with a place for the search words' {
        $help.SearchUrl | Should -Be 'https://www.google.com/search?q={0}'
    }

    It 'builds the address of a search from the words' {
        InModuleScope HelpdeskToolkit { Get-SearchAddress -Words 'Windows error 0x80070005' } | Should -Be 'https://www.google.com/search?q=Windows%20error%200x80070005'
    }

    It 'keeps whatever the words contain inside the search, so they cannot change the address' {
        # The last character is a letter outside the English alphabet.
        $words = 'a&b=c #d "e" ?f /g <h> ' + [char]0x0161
        $url = InModuleScope HelpdeskToolkit -Parameters @{ Words = $words } { Get-SearchAddress -Words $Words }

        $query = $url.Substring('https://www.google.com/search?q='.Length)
        $query | Should -Not -Match '[&=#"?/<> ]'
        [uri]::UnescapeDataString($query) | Should -Be $words
        ([uri]$url).Host | Should -Be 'www.google.com'
    }
}

Describe 'ConvertTo-SearchName: what may go into a search besides numbers and codes' {
    It 'keeps the name <_>' -ForEach @(
        'contoso.exe'
        'Contoso Edit 2.1 (x64)'
        'Microsoft.WidgetsPlatformRuntime'
        "Tom's Tool & Co, v2"
        '7zFM.exe'
    ) {
        Get-TestName -Name $_ | Should -Be $_
    }

    It 'keeps letters of other alphabets' {
        $name = '{0}ita{0}.exe' -f [char]0x010D
        Get-TestName -Name $name | Should -Be $name
    }

    It 'keeps only the file name of a path, because the folders above it can name a user' {
        Get-TestName -Name 'C:\Users\marko\AppData\Roaming\tool\tool-setup.exe' | Should -Be 'tool-setup.exe'
        Get-TestName -Name '\\server\share\Ana Kovac\report tool.exe' | Should -Be 'report tool.exe'
    }

    It 'refuses <Why>' -ForEach @(
        @{ Name = ''; Why = 'an empty name' }
        @{ Name = '   '; Why = 'a name of spaces' }
        @{ Name = 'marko@contoso.test'; Why = 'an e-mail address' }
        @{ Name = 'tool.exe; shutdown'; Why = 'a command' }
        @{ Name = 'a=b'; Why = 'something with an equals sign' }
        @{ Name = 'what?'; Why = 'a question' }
        @{ Name = '%TEMP%'; Why = 'a variable' }
        @{ Name = '<script>'; Why = 'a tag' }
        @{ Name = '.hidden'; Why = 'a name that starts with a dot' }
        @{ Name = ('x' * 101); Why = 'a name of more than 100 characters' }
    ) {
        Get-TestName -Name $Name | Should -Be ''
    }

    It 'refuses a name that contains the name of the signed-in user or of the computer' {
        Invoke-TestAsUser -User 'marko.horvat' -Computer 'FIN-LT-014' {
            Get-TestName -Name 'marko.horvat-backup.exe' | Should -Be ''
            Get-TestName -Name 'Sync for MARKO.HORVAT' | Should -Be ''
            Get-TestName -Name 'agent-fin-lt-014.exe' | Should -Be ''
            Get-TestName -Name 'contoso.exe' | Should -Be 'contoso.exe'
        }
    }

    It 'does not refuse half the programs because a user name is two letters long' {
        Invoke-TestAsUser -User 'ab' -Computer 'PC' {
            Get-TestName -Name 'cab-viewer.exe' | Should -Be 'cab-viewer.exe'
            Get-TestName -Name 'PCHealth.exe' | Should -Be 'PCHealth.exe'
        }
    }
}

Describe 'Get-CheckHelpLink: the programs that crash' {
    It 'offers a search for the crashes of every program the value names' {
        $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value '12 in the last 7 days: contoso.exe (10), Fabrikam Tool.exe (2)' | Where-Object Kind -eq 'Program')

        $links.Text | Should -Be @('contoso.exe', 'Fabrikam Tool.exe')
        $links[0].Url | Should -Be (Get-TestSearch 'contoso.exe crash Windows')
        $links[1].Url | Should -Be (Get-TestSearch 'Fabrikam Tool.exe crash Windows')
        # These are shown below the fix, not in a line of the details.
        $links.Line | Should -Be @('', '')
    }

    It 'keeps the page that explains the problem as the first link' {
        $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value '3 in the last 7 days: contoso.exe (3)')
        $links.Kind | Should -Be @('Page', 'Program')
    }

    It 'offers the first three programs of the value only, and does not take "and 3 more" for a program' {
        $value = '20 in the last 7 days: a1.exe (9), b2.exe (5), c3.exe (3), d4.exe (2), e5.exe (1) and 3 more'
        $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value $value | Where-Object Kind -eq 'Program')
        $links.Text | Should -Be @('a1.exe', 'b2.exe', 'c3.exe')
    }

    It 'gives every program in the details a link of its own line' {
        $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value '9 in the last 7 days: contoso.exe (5) and 2 more' -Detail @('old.exe (3)', 'helper.exe (1)') |
                Where-Object { $_.Kind -eq 'Program' -and $_.Line })

        $links.Line | Should -Be @('old.exe (3)', 'helper.exe (1)')
        # How often each of them crashed
        @($links | ForEach-Object { $_.Count }) | Should -Be @(3, 1)
        $links[0].Url | Should -Be (Get-TestSearch 'old.exe crash Windows')
    }

    It 'does not take a program whose name ends in a number for an event of the event log' {
        $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value '4 in the last 7 days' -Detail @('Contoso Tool 2 (4)'))

        @($links | Where-Object Kind -eq 'Event').Count | Should -Be 0
        ($links | Where-Object Kind -eq 'Program').Text | Should -Be 'Contoso Tool 2'
    }

    It 'searches for the file name only when Windows names the program by its path' {
        $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value '1 in the last day: C:\Users\marko\Desktop\game.exe (1)' | Where-Object Kind -eq 'Program')

        $links[0].Text | Should -Be 'game.exe'
        $links[0].Url | Should -Be (Get-TestSearch 'game.exe crash Windows')
        $links[0].Url | Should -Not -Match 'marko|Users|Desktop'
    }

    It 'offers no search for a program whose name cannot go into an address' {
        $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value '2 in the last day: marko@contoso.test (2)' -Detail @('a=b (1)'))
        @($links | Where-Object Kind -eq 'Program').Count | Should -Be 0
    }

    It 'never puts the name of the user or the computer into the address' {
        Invoke-TestAsUser -User 'marko.horvat' -Computer 'FIN-LT-014' {
            $links = @(Get-TestLink -Check 'Application crashes' -Category 'Software' -Value '3 in the last day: marko.horvat-sync.exe (2), contoso.exe (1)' -Detail @('FIN-LT-014-agent.exe (1)'))
            foreach ($link in $links) {
                $link.Url | Should -Not -Match 'marko|horvat|FIN-LT'
            }
            ($links | Where-Object Kind -eq 'Program').Text | Should -Be 'contoso.exe'
        }
    }

    It 'reads programs only from the result that lists crashes' {
        $links = @(Get-TestLink -Check 'Installed programs' -Category 'Software' -Value '2 programs: contoso.exe (10), fabrikam.exe (2)' -Detail @('old.exe (3)'))
        @($links | Where-Object Kind -eq 'Program').Count | Should -Be 0
    }
}

Describe 'Get-CheckHelpLink: a check that could not be read' {
    It 'offers a search for the error code its error names, and nothing else' {
        $links = @(Get-TestLink -Check 'Defender definitions' -Category 'Security' -ErrorText 'The information could not be read: Element not found. (Exception from HRESULT: 0x80070490)')

        $links.Kind | Should -Be @('Code')
        $links[0].Text | Should -Be '0x80070490'
        $links[0].Url | Should -Be (Get-TestSearch 'Windows error 0x80070490')
    }

    It 'offers nothing when the error names no code' {
        @(Get-TestLink -Check 'Defender definitions' -Category 'Security' -ErrorText 'The information could not be read: The RPC server is unavailable.').Count | Should -Be 0
    }

    It 'never puts the text of the error into the address' {
        $text = 'The information could not be read: Access to C:\Users\marko\NTUSER.DAT failed for CONTOSO\marko (0x80070005)'
        $links = @(Get-TestLink -Check 'Mapped drives' -Category 'Network' -ErrorText $text)

        $links.Count | Should -Be 1
        $links[0].Url | Should -Be (Get-TestSearch 'Windows error 0x80070005')
    }

    It 'searches for at most three codes, each once, in capital letters' {
        $links = @(Get-TestLink -Check 'Some check' -ErrorText '0x8007000e 0x8007000E 0x80041010 0x80004005 0x80070057')
        $links.Text | Should -Be @('0x8007000E', '0x80041010', '0x80004005')
    }
}

Describe 'Get-ResultHelpLink: which links a result gets' {
    BeforeAll {
        function Get-TestResultLink {
            param($Result)
            @(InModuleScope HelpdeskToolkit -Parameters @{ Result = $Result } { Get-ResultHelpLink -Result $Result })
        }
    }

    It 'gives a problem everything: the page, the codes and the programs' {
        $result = New-TestResult -Category 'Software' -Check 'Application crashes' -Status Warning -Value '6 in the last 7 days: contoso.exe (6)' -Recommendation 'Update it.'
        (Get-TestResultLink $result).Kind | Should -Be @('Page', 'Program')
    }

    It 'gives a result that is fine only the links of its lines' {
        $result = New-TestResult -Category 'Event Log' -Check 'System log - errors' -Status OK -Value '2 in the last 7 days' -Details @('Service Control Manager 7031 (2)')
        $links = Get-TestResultLink $result
        $links.Kind | Should -Be @('Event')
        $links[0].Line | Should -Be 'Service Control Manager 7031 (2)'
    }

    It 'gives a result that is fine and has no details nothing' {
        (Get-TestResultLink (New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status OK -Value '60 % free')).Count | Should -Be 0
    }

    It 'gives a check that could not be read the search for its error code only' {
        $result = New-TestResult -Category 'Security' -Check 'Firewall' -Status Warning -Value 'Unavailable' -Recommendation 'The information could not be read: Unspecified error (0x80004005)'
        $links = Get-TestResultLink $result
        $links.Kind | Should -Be @('Code')
        $links[0].Text | Should -Be '0x80004005'
    }
}

Describe 'Get-HelpLinkCaption' {
    It 'names a link of the kind <Kind> "<Caption>"' -ForEach @(
        @{ Kind = 'Page'; Text = ''; Caption = 'What this means and how to fix it' }
        @{ Kind = 'Article'; Text = 'KB5050009'; Caption = 'About update KB5050009' }
        @{ Kind = 'Code'; Text = '0x80070005'; Caption = 'Search the web for error 0x80070005' }
        @{ Kind = 'Program'; Text = 'contoso.exe'; Caption = 'Search the web for crashes of contoso.exe' }
        @{ Kind = 'Search'; Text = ''; Caption = 'Search the web for this problem' }
    ) {
        $link = [PSCustomObject]@{ Kind = $Kind; Url = 'https://example.test/'; Text = $Text }
        InModuleScope HelpdeskToolkit -Parameters @{ Link = $link } { Get-HelpLinkCaption -Link $Link } | Should -Be $Caption
    }

    It 'returns the text in the language of the window when asked to' {
        $link = [PSCustomObject]@{ Kind = 'Program'; Url = 'https://example.test/'; Text = 'contoso.exe' }
        InModuleScope HelpdeskToolkit -Parameters @{ Link = $link } {
            $script:Language = 'hr'
            $script:Translations = $null
            try {
                Get-HelpLinkCaption -Link $Link -Translate | Should -Match 'contoso\.exe na webu$'
                # The report stays English.
                Get-HelpLinkCaption -Link $Link | Should -Be 'Search the web for crashes of contoso.exe'
            }
            finally {
                $script:Language = 'en'
                $script:Translations = $null
            }
        }
    }
}

Describe 'The crashes on a result card' {
    BeforeAll {
        $result = New-TestResult -Category 'Software' -Check 'Application crashes' -Status Warning -Value '14 in the last 7 days: contoso.exe (9), fabrikam.exe (3) and 2 more' `
            -Recommendation 'Update or reinstall the program.' -Details @('old.exe (1)', 'marko@contoso.test (1)')
        $item = Get-TestItem -Result $result
    }

    It 'offers a search for the crashes of each program below the fix' {
        $item.Links.Label | Should -Be @('What this means and how to fix it', 'Search the web for crashes of contoso.exe', 'Search the web for crashes of fabrikam.exe')
        $item.Links[1].Url | Should -Be (Get-TestSearch 'contoso.exe crash Windows')
    }

    It 'makes a program in the details a line that can be clicked, and leaves the text of the line as it is' {
        $item.MoreItems[0].Text | Should -Be 'old.exe (1)'
        $item.MoreItems[0].Link | Should -Be 'Yes'
        $item.MoreItems[0].Url | Should -Be (Get-TestSearch 'old.exe crash Windows')
        $item.MoreItems[0].Action | Should -Be ''
        $item.MoreItems[0].Tip | Should -Be 'Search the web for the crashes of this program'
    }

    It 'leaves a line whose name cannot be searched for as plain text' {
        $item.MoreItems[1].Text | Should -Be 'marko@contoso.test (1)'
        $item.MoreItems[1].Link | Should -Be ''
        $item.MoreItems[1].Url | Should -Be ''
    }

    It 'makes the lines of a result that is fine clickable too, without links below a fix it does not have' {
        $fine = Get-TestItem -Result (New-TestResult -Category 'Software' -Check 'Application crashes' -Status OK -Value '7 in the last 7 days: contoso.exe (2) and 1 more' -Details @('old.exe (1)'))
        @($fine.Links).Count | Should -Be 0
        $fine.MoreItems[0].Link | Should -Be 'Yes'
    }

    It 'offers a check that could not be read the search for its error code' {
        $failed = Get-TestItem -Result (New-TestResult -Category 'Security' -Check 'Firewall' -Status Warning -Value 'Unavailable' `
                -Recommendation 'The information could not be read: Unspecified error (0x80004005)')
        $failed.Links.Label | Should -Be @('Search the web for error 0x80004005')
        $failed.Links[0].Url | Should -Be (Get-TestSearch 'Windows error 0x80004005')
    }
}

Describe 'Get-ChangeTimeline: the error code of a problem' {
    BeforeAll {
        $crash = 'Faulting application name: editor.exe, version: 9.7.0.0, time stamp: 0x66eaf76b Faulting module name: editor.dll, version: 9.7.0.0, time stamp: 0x66eaf76c ' +
            'Exception code: 0xc0000005 Fault offset: 0x001cb627 Faulting process id: 0x153C Faulting application path: C:\Users\marko\editor.exe'
        # The same record of a Windows in another language: the labels differ, the order does not.
        $crashOther = 'Naziv aplikacije: viewer.exe, verzija: 1.0.0.0, vremenska oznaka: 0x5f1a2b3c Naziv modula: ntdll.dll, verzija: 10.0.1.2, vremenska oznaka: 0x4d5e6f70 ' +
            'Kod iznimke: 0xc0000409 Pomak: 0x00000000000a1b2c ID procesa: 0x2a4'

        Mock -ModuleName HelpdeskToolkit Get-ReliabilityRecord {
            New-TestRecord -Source 'Application Error' -Id 1000 -Product 'editor.exe' -Message $crash -HoursAgo 30
            New-TestRecord -Source 'Application Error' -Id 1000 -Product 'viewer.exe' -Message $crashOther -HoursAgo 31
            New-TestRecord -Source 'Application Error' -Id 1000 -Product 'silent.exe' -Message 'A program stopped.' -HoursAgo 32
            New-TestRecord -Source 'Application Hang' -Id 1002 -Product 'browser.exe' -Message 'The program browser.exe version 1.0.0.0 stopped interacting with Windows (0x12345678).' -HoursAgo 33
            New-TestRecord -Source 'Microsoft-Windows-WindowsUpdateClient' -Id 20 -Product '2026-01 Cumulative Update for Windows 11 (KB5000001)' `
                -Message 'Installation Failure: Windows failed to install the following update with error 0x800f0922: 2026-01 Cumulative Update for Windows 11 (KB5000001).' -HoursAgo 34
            New-TestRecord -Source 'Microsoft-Windows-WER-SystemErrorReporting' -Id 1001 -Product '' `
                -Message 'The computer has rebooted from a bugcheck.  The bugcheck was: 0x0000009f (0x0000000000000003, 0xffffe00123456789, 0xfffff80012345678, 0xffffe00198765432).' -HoursAgo 35
            New-TestRecord -Source 'EventLog' -Id 6008 -Product '' -Message 'The previous system shutdown at 10:00:00 was unexpected (0x00000001).' -HoursAgo 36
            New-TestRecord -Source 'MsiInstaller' -Id 1033 -Product 'Contoso Edit' -Message 'Installed with status 0x00000000.' -HoursAgo 37
        }
        $timeline = @(Get-ChangeTimeline)
        $codeOf = { param($Title, $Kind) ($timeline | Where-Object { $_.Title -eq $Title -and $_.Kind -eq $Kind }).Code }
    }

    It 'takes the exception code of a crash, not the time stamps before it, in capital letters' {
        & $codeOf 'editor.exe' 'Program crashed' | Should -Be '0xC0000005'
    }

    It 'finds the exception code by its place when Windows writes the record in another language' {
        & $codeOf 'viewer.exe' 'Program crashed' | Should -Be '0xC0000409'
    }

    It 'has no code for a crash whose record names none' {
        & $codeOf 'silent.exe' 'Program crashed' | Should -Be ''
    }

    It 'takes the error of an update that failed' {
        & $codeOf '2026-01 Cumulative Update for Windows 11 (KB5000001)' 'Update failed' | Should -Be '0x800F0922'
    }

    It 'takes the stop code of a blue screen, not its parameters' {
        & $codeOf '' 'Windows crashed (blue screen)' | Should -Be '0x0000009F'
    }

    It 'has no code for a program that stopped responding, a shutdown or a change, whatever number their record contains' {
        & $codeOf 'browser.exe' 'Program stopped responding' | Should -Be ''
        & $codeOf '' 'Unexpected shutdown' | Should -Be ''
        & $codeOf 'Contoso Edit' 'Program installed' | Should -Be ''
    }

    It 'does not fail on a record without a message' {
        Mock -ModuleName HelpdeskToolkit Get-ReliabilityRecord {
            [PSCustomObject]@{ SourceName = 'Application Error'; EventIdentifier = 1000; TimeGenerated = (Get-Date).AddHours(-5); ProductName = 'editor.exe' }
        }
        $entry = @(Get-ChangeTimeline)
        $entry.Count | Should -Be 1
        $entry[0].Code | Should -Be ''
    }

    It 'carries the code into the report' {
        Mock -ModuleName HelpdeskToolkit Get-ChangeTimeline {
            [PSCustomObject]@{ Time = (Get-Date).AddHours(-3); Level = 'Problem'; Kind = 'Program crashed'; Title = 'editor.exe'; Count = 2; Code = '0xC0000005' }
            # An entry of another source that knows no code
            [PSCustomObject]@{ Time = (Get-Date).AddHours(-4); Level = 'Change'; Kind = 'Program installed'; Title = 'Contoso Edit'; Count = 1 }
        }
        foreach ($check in 'Get-SystemHealth', 'Get-ComputerSpecification', 'Get-HardwareHealth', 'Get-SoftwareHealth', 'Get-EventLogHealth', 'Get-WindowsUpdateHealth',
            'Get-SecurityHealth', 'Get-NetworkHealth', 'Get-PrinterHealth', 'Get-ServiceHealth') {
            Mock -ModuleName HelpdeskToolkit $check { New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d' }
        }
        Mock -ModuleName HelpdeskToolkit Write-Progress { }
        $report = Get-PCHealthReport -SkipNetwork

        @($report.Timeline).Count | Should -Be 2
        $report.Timeline[0].Code | Should -Be '0xC0000005'
        $report.Timeline[1].Code | Should -Be ''
    }
}

Describe 'Get-TimelineHelpLink: the search for a problem of the time line' {
    It 'searches for <Words> when <Case>' -ForEach @(
        @{ Case = 'a program crashed'; Kind = 'Program crashed'; Title = 'editor.exe'; Code = '0xC0000005'; Words = 'editor.exe crash exception code 0xC0000005' }
        @{ Case = 'a crash has no code'; Kind = 'Program crashed'; Title = 'editor.exe'; Code = ''; Words = 'editor.exe crash' }
        @{ Case = 'a crash has no usable name'; Kind = 'Program crashed'; Title = 'marko@contoso.test'; Code = '0xC0000005'; Words = 'Windows program crash Application Error 1000 exception code 0xC0000005' }
        @{ Case = 'a program stopped responding'; Kind = 'Program stopped responding'; Title = 'browser.exe'; Code = ''; Words = 'browser.exe not responding' }
        @{ Case = 'a program without a name stopped responding'; Kind = 'Program stopped responding'; Title = ''; Code = ''; Words = 'Windows program not responding Application Hang 1002' }
        @{ Case = 'an update with a number failed'; Kind = 'Update failed'; Title = '2026-01 Cumulative Update for Windows 11 (KB5000001)'; Code = '0x800F0922'; Words = 'Windows update KB5000001 failed to install error 0x800F0922' }
        @{ Case = 'an app from the Store failed to update'; Kind = 'Update failed'; Title = 'Contoso.Store'; Code = '0x80073D02'; Words = 'Contoso.Store update failed error 0x80073D02' }
        @{ Case = 'an update without a name failed'; Kind = 'Update failed'; Title = ''; Code = ''; Words = 'Windows update failed to install' }
        @{ Case = 'Windows crashed with a stop code'; Kind = 'Windows crashed (blue screen)'; Title = ''; Code = '0x0000009F'; Words = 'Windows stop code 0x0000009F' }
        @{ Case = 'Windows crashed without a known stop code'; Kind = 'Windows crashed (blue screen)'; Title = ''; Code = ''; Words = 'Windows blue screen stop code' }
        @{ Case = 'the computer went off without a shutdown'; Kind = 'Unexpected shutdown'; Title = ''; Code = ''; Words = 'Windows unexpected shutdown event 6008' }
    ) {
        Get-TestTimelineLink (New-TestEntry -Kind $Kind -Title $Title -Code $Code) | Should -Be (Get-TestSearch $Words)
    }

    It 'has no link for a change: <_>' -ForEach @('Update installed', 'Program installed', 'Program removed', 'Program updated', 'Driver installed') {
        Get-TestTimelineLink (New-TestEntry -Kind $_ -Title 'Contoso Edit' -Level 'Change') | Should -Be ''
    }

    It 'has no link for a kind of problem it does not know, and none for nothing' {
        Get-TestTimelineLink (New-TestEntry -Kind 'Something new' -Title 'x') | Should -Be ''
        Get-TestTimelineLink $null | Should -Be ''
    }

    It 'works for the entry of a report saved before entries had a code' {
        $old = [PSCustomObject]@{ Time = '2026-01-15 10:30'; Level = 'Problem'; Kind = 'Program crashed'; Title = 'editor.exe'; Count = 1 }
        Get-TestTimelineLink $old | Should -Be (Get-TestSearch 'editor.exe crash')
    }

    It 'takes a code only in its fixed shape' {
        foreach ($code in 'DROP TABLE', '0x12', '0xC0000005 and more', 'c0000005') {
            Get-TestTimelineLink (New-TestEntry -Kind 'Program crashed' -Title 'editor.exe' -Code $code) | Should -Be (Get-TestSearch 'editor.exe crash')
        }
    }

    It 'searches for the file name only when the title is a path' {
        $url = Get-TestTimelineLink (New-TestEntry -Kind 'Program crashed' -Title 'C:\Users\marko\Games\game.exe')
        $url | Should -Be (Get-TestSearch 'game.exe crash')
    }

    It 'never puts the name of the user or the computer into the address' {
        Invoke-TestAsUser -User 'marko.horvat' -Computer 'FIN-LT-014' {
            foreach ($kind in 'Program crashed', 'Program stopped responding', 'Update failed') {
                foreach ($title in 'marko.horvat-sync.exe', 'Agent on FIN-LT-014') {
                    Get-TestTimelineLink (New-TestEntry -Kind $kind -Title $title) | Should -Not -Match 'marko|horvat|FIN-LT'
                }
            }
        }
    }

    It 'returns only addresses of the search engine, over https' {
        foreach ($kind in 'Program crashed', 'Program stopped responding', 'Update failed', 'Windows crashed (blue screen)', 'Unexpected shutdown') {
            $url = Get-TestTimelineLink (New-TestEntry -Kind $kind -Title 'a&b=c' -Code '0x80070005')
            $url | Should -Match '^https://www\.google\.com/search\?q=[^&=#]+$'
        }
    }
}

Describe 'The Timeline page: a problem is a link' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Open-WindowHelpLink { $true }

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $report = New-TestReport -Result @(New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d')
        $report | Add-Member -NotePropertyName Timeline -NotePropertyValue @(
            New-TestEntry -Kind 'Program crashed' -Title 'editor.exe' -Code '0xC0000005' -Time '2026-01-15 14:20' -Count 3
            New-TestEntry -Kind 'Update installed' -Title 'Contoso Edit' -Level 'Change' -Time '2026-01-15 09:05'
            New-TestEntry -Kind 'Unexpected shutdown' -Time '2026-01-14 08:00'
        ) -Force
        $gui.Report = $report
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTimeline -Gui $Gui }
        $rows = @($gui.Controls.TimelineItems.ItemsSource | ForEach-Object { $_.Events })
    }

    It 'gives the row of a problem the search for exactly that error' {
        $rows[0].Title | Should -Be 'editor.exe'
        $rows[0].Link | Should -Be 'Yes'
        $rows[0].Url | Should -Be (Get-TestSearch 'editor.exe crash exception code 0xC0000005')
        $rows[2].Url | Should -Be (Get-TestSearch 'Windows unexpected shutdown event 6008')
    }

    It 'leaves the row of a change as plain text' {
        $rows[1].Title | Should -Be 'Contoso Edit'
        $rows[1].Link | Should -Be ''
        $rows[1].Url | Should -Be ''
    }

    It 'opens the search when the link of a row is clicked' {
        $button = New-Object -TypeName System.Windows.Controls.Button
        $button.DataContext = $rows[0]
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowTimelineClick -Gui $Gui -Source $Source }

        Should -Invoke -ModuleName HelpdeskToolkit Open-WindowHelpLink -Times 1 -Exactly -Scope It -ParameterFilter { $Url -eq 'https://www.google.com/search?q=editor.exe%20crash%20exception%20code%200xC0000005' }
    }

    It 'opens nothing for a row without an address, for another element, or for nothing' {
        $button = New-Object -TypeName System.Windows.Controls.Button
        $button.DataContext = $rows[1]
        $text = New-Object -TypeName System.Windows.Controls.TextBlock
        $text.DataContext = $rows[0]
        foreach ($source in $button, $text, $null) {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $source } { Invoke-WindowTimelineClick -Gui $Gui -Source $Source }
        }
        Should -Invoke -ModuleName HelpdeskToolkit Open-WindowHelpLink -Times 0 -Exactly -Scope It
    }

}

Describe 'A click on a problem of the Timeline page, all the way to the browser' -Skip:(-not $isSta) {
    It 'hands the address of the search to the browser of the user and says that the page was opened' {
        # The last step is replaced: no browser is started by a test.
        Mock -ModuleName HelpdeskToolkit Open-WebAddress { $true }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'ContosoHTML'; Path = 'C:\Contoso\browser.exe'; Exists = $true; IsBroken = $false; Usable = 'C:\Contoso\browser.exe' } }

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $report = New-TestReport -Result @(New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d')
        $report | Add-Member -NotePropertyName Timeline -NotePropertyValue @(New-TestEntry -Kind 'Windows crashed (blue screen)' -Code '0x0000009f') -Force
        $gui.Report = $report
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowTimeline -Gui $Gui }

        $button = New-Object -TypeName System.Windows.Controls.Button
        $button.DataContext = @($gui.Controls.TimelineItems.ItemsSource)[0].Events[0]
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowTimelineClick -Gui $Gui -Source $Source }

        Should -Invoke -ModuleName HelpdeskToolkit Open-WebAddress -Times 1 -Exactly -Scope It -ParameterFilter { $Url -eq 'https://www.google.com/search?q=Windows%20stop%20code%200x0000009F' }
        $gui.Controls.StatusText.Text | Should -Be 'The page was opened in the browser.'
    }

    It 'lets the address of a search through the check every address has to pass before it is opened' {
        # Open-WebAddress refuses anything that is not a plain https address.
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        Mock -ModuleName HelpdeskToolkit Invoke-DesktopShell { }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'ContosoHTML'; Path = 'C:\Contoso\browser.exe'; Exists = $true; IsBroken = $false; Usable = 'C:\Contoso\browser.exe' } }

        foreach ($entry in (New-TestEntry -Kind 'Program crashed' -Title "Tom's Tool & Co (x64).exe" -Code '0xC0000005'), (New-TestEntry -Kind 'Update failed' -Title 'Contoso.Store' -Code '0x80073D02')) {
            $url = Get-TestTimelineLink $entry
            InModuleScope HelpdeskToolkit -Parameters @{ Url = $url } { Open-WebAddress -Url $Url } | Should -BeTrue
        }
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 2 -Exactly -Scope It -ParameterFilter { $FilePath -like 'https://www.google.com/search?q=*' }
    }
}

Describe 'The layout of the links' {
    BeforeAll {
        $xaml = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml'))
        $panel = [regex]::Match($xaml, '(?s)<DockPanel x:Name="TimelinePanel".*?</ScrollViewer>').Value
        $window = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Public\Show-PCHealthCheck.ps1'))
    }

    It 'shows the title of a problem on the Timeline page as a link whose tip is the address it opens' {
        $panel | Should -Not -BeNullOrEmpty
        $panel | Should -Match '<Button Content="\{Binding Title\}" ToolTip="\{Binding Url\}">'
        ([regex]::Matches($panel, 'Binding="\{Binding Link\}"')).Count | Should -Be 2
    }

    It 'says on the page that a problem can be clicked' {
        $panel | Should -Match 'A click on a problem searches the web for exactly that error\.'
    }

    It 'hands a click on the Timeline page to the function that opens the search' {
        $window | Should -Match 'TimelineItems\.AddHandler\(\[System\.Windows\.Controls\.Primitives\.ButtonBase\]::ClickEvent'
        $window | Should -Match 'Invoke-WindowTimelineClick -Gui'
    }
}

Describe 'The HTML report: the same links' {
    BeforeAll {
        $results = @(
            New-TestResult -Category 'Software' -Check 'Application crashes' -Status Warning -Value '10 in the last 7 days: contoso.exe (9) and 1 more' -Recommendation 'Update it.' -Details @('old & new.exe (1)')
            New-TestResult -Category 'Windows Update' -Check 'Failed updates' -Status Warning -Value '1 update: 2026-01 Cumulative Update (KB5050009) (error 0x80070005)' -Recommendation 'Run the troubleshooter.'
            New-TestResult -Category 'Event Log' -Check 'System log - errors' -Status OK -Value '2 in the last 7 days' -Details @('Service Control Manager 7031 (2)')
            New-TestResult -Category 'Security' -Check 'Firewall' -Status Warning -Value 'Unavailable' -Recommendation 'The information could not be read: Unspecified error (0x80004005)'
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status OK -Value '60 % free'
        )
        $report = New-TestReport -Result $results
        $report | Add-Member -NotePropertyName Timeline -NotePropertyValue @(
            New-TestEntry -Kind 'Program crashed' -Title 'editor.exe' -Code '0xC0000005' -Count 2
            New-TestEntry -Kind 'Program installed' -Title 'Contoso Edit' -Level 'Change'
        ) -Force
        $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthReportHtml -Report $Report }
        $anchors = @([regex]::Matches($html, '<a href="(?<url>https://[^"]+)"(?<rest>[^>]*)>(?<text>[^<]*)</a>'))
        $attributes = ' target="_blank" rel="noopener noreferrer"'
    }

    It 'offers the search for the crashes of a program and the page that explains the problem' {
        $html | Should -Match ([regex]::Escape(('<a href="{0}"{1}>Search the web for crashes of contoso.exe</a>' -f (Get-TestSearch 'contoso.exe crash Windows'), $attributes)))
        $html | Should -Match ([regex]::Escape(('<a href="{0}"{1}>What this means and how to fix it</a>' -f $help.Pages['Application crashes'], $attributes)))
    }

    It 'offers the article of an update and the search for its error code' {
        $html | Should -Match ([regex]::Escape(('<a href="https://support.microsoft.com/help/5050009"{0}>About update KB5050009</a>' -f $attributes)))
        $html | Should -Match ([regex]::Escape(('<a href="{0}"{1}>Search the web for error 0x80070005</a>' -f (Get-TestSearch 'Windows Update error 0x80070005'), $attributes)))
    }

    It 'makes an event and a program in the details a link, with the text of the line encoded' {
        $html | Should -Match ([regex]::Escape(('<li><a href="{0}"{1}>Service Control Manager 7031 (2)</a></li>' -f (Get-TestSearch 'Windows event ID 7031 Service Control Manager'), $attributes)))
        $html | Should -Match ([regex]::Escape(('<li><a href="{0}"{1}>old &amp; new.exe (1)</a></li>' -f (Get-TestSearch 'old & new.exe crash Windows'), $attributes)))
    }

    It 'offers a check that could not be read the search for its error code' {
        $html | Should -Match ([regex]::Escape(('<a href="{0}"{1}>Search the web for error 0x80004005</a>' -f (Get-TestSearch 'Windows error 0x80004005'), $attributes)))
    }

    It 'makes a problem of the time line a link and leaves a change as text' {
        $html | Should -Match ([regex]::Escape(('<a href="{0}"{1}>editor.exe</a> <span class="times">' -f (Get-TestSearch 'editor.exe crash exception code 0xC0000005'), $attributes)))
        $html | Should -Match '<td>Contoso Edit</td>'
    }

    It 'gives a result that is fine and names nothing no link' {
        $row = [regex]::Match($html, '(?s)<tr><td class="col-status"><span class="badge ok">OK</span></td><td class="col-check"><div class="check">Disk \(C:\).*?</tr>').Value
        $row | Should -Not -BeNullOrEmpty
        $row | Should -Not -Match '<a '
    }

    It 'leads only to Microsoft and the search engine, and tells the page it opens nothing about the report' {
        $anchors.Count | Should -BeGreaterThan 8
        @($anchors | ForEach-Object { ([uri][System.Net.WebUtility]::HtmlDecode($_.Groups['url'].Value)).Host } | Sort-Object -Unique) | Should -Be @('support.microsoft.com', 'www.google.com')
        foreach ($anchor in $anchors) {
            $anchor.Groups['rest'].Value | Should -Be $attributes
        }
        # Every address in the report is one of these links: nothing else points to the web.
        ([regex]::Matches($html, 'https?://')).Count | Should -Be $anchors.Count
    }

    It 'still loads nothing from the web' {
        $html | Should -Not -Match '<link'
        $html | Should -Not -Match '<script'
        $html | Should -Not -Match 'src\s*='
        $html | Should -Not -Match 'url\('
    }
}

Describe 'The texts of the searches' {
    It 'are translated into Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'Search the web for crashes of {0}', 'Search the web for the crashes of this program', 'Search the web for error {0}', 'Search the web for this problem',
            'Look for a change (an installation, an update, a driver) shortly before the first failure: that is the usual cause. A click on a problem searches the web for exactly that error.') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
    }
}
