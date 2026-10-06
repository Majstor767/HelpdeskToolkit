# Tests for the links that explain a problem: the page of the maker below the
# recommended fix, and the events of the event log that can be looked up one by one.
# Nothing is opened: Start-Process is replaced wherever a link is "clicked".

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

    function Get-TestLink {
        param([string]$Check, [string]$Category = '', [string[]]$Detail = @(), [string]$Value = '')
        InModuleScope HelpdeskToolkit -Parameters @{ Check = $Check; Category = $Category; Detail = $Detail; Value = $Value } {
            Get-CheckHelpLink -Check $Check -Category $Category -Detail $Detail -Value $Value
        }
    }

    function Get-TestItem {
        param($Result)
        InModuleScope HelpdeskToolkit -Parameters @{ Result = $Result } { $Result | ConvertTo-WindowItem }
    }
}

Describe 'Config\Help.psd1' {
    BeforeAll {
        $addresses = foreach ($entry in $help.Pages.Values) {
            if ($entry -is [hashtable]) { $entry.Values } else { $entry }
        }
    }

    It 'lists only pages of Microsoft, over https' {
        foreach ($address in $addresses) {
            $address | Should -Match '^https://(support|learn)\.microsoft\.com/\S+$'
        }
    }

    It 'leaves the language out of every address, so Microsoft shows the page in the language of the browser' {
        foreach ($address in $addresses) {
            $address | Should -Not -Match '\.com/[a-z]{2}-[a-z]{2}/'
        }
    }

    It 'has an address for the article of an update, with a place for its number' {
        $help.ArticleUrl | Should -Match '^https://support\.microsoft\.com/\S*\{0\}$'
    }

    It 'has a search address with a place for the search words' {
        $help.SearchUrl | Should -Match '^https://'
        $help.SearchUrl | Should -Match '\{0\}'
    }

    It 'has both addresses for an entry that depends on the Windows version' {
        foreach ($entry in $help.Pages.Values | Where-Object { $_ -is [hashtable] }) {
            $entry.Windows10 | Should -Match '^https://'
            $entry.Windows11 | Should -Match '^https://'
        }
    }
}

Describe 'Get-CheckHelpLink' {
    It 'finds the page of a check by the part of its name before the parenthesis' {
        $link = @(Get-TestLink -Check 'Disk (C:)' -Category 'Hardware')
        $link.Count | Should -Be 1
        $link[0].Kind | Should -Be 'Page'
        $link[0].Url | Should -Be $help.Pages['Disk']
    }

    It 'falls back to the page of the category' {
        $link = @(Get-TestLink -Check 'Pending restart' -Category 'Windows Update')
        $link[0].Kind | Should -Be 'Page'
        $link[0].Url | Should -Be $help.Pages['Category:Windows Update']
    }

    It 'picks the address for the Windows version of this computer' {
        $link = @(Get-TestLink -Check 'Windows support' -Category 'System')
        $link[0].Kind | Should -Be 'Page'
        $link[0].Url | Should -BeIn @($help.Pages['Windows support'].Windows10, $help.Pages['Windows support'].Windows11)
    }

    It 'searches the web for the name of a check that has no page' {
        $link = @(Get-TestLink -Check 'Scheduled tasks' -Category 'System')
        $link.Count | Should -Be 1
        $link[0].Kind | Should -Be 'Search'
        $link[0].Url | Should -Be ($help.SearchUrl -f 'Windows%20Scheduled%20tasks')
    }

    It 'leaves the part in parentheses out of the search, which can name a drive or a user' {
        $link = @(Get-TestLink -Check 'Some check (D:\Private folder)' -Category 'Elsewhere')
        $link[0].Url | Should -Not -Match 'Private'
        $link[0].Url | Should -Be ($help.SearchUrl -f 'Windows%20Some%20check')
    }

    It 'returns a link for every event named in the details, with its number, source and count' {
        $details = 'Microsoft-Windows-DistributedCOM 10016 (45)', 'Service Control Manager 7031 (16)', 'A line that is no event'
        $links = @(Get-TestLink -Check 'System log - errors' -Category 'Event Log' -Detail $details)

        $links.Count | Should -Be 2
        $links.Kind | Select-Object -Unique | Should -Be 'Event'
        $links[0].Id | Should -Be '10016'
        $links[0].Source | Should -Be 'DistributedCOM'
        $links[0].Count | Should -Be 45
        $links[0].Line | Should -Be 'Microsoft-Windows-DistributedCOM 10016 (45)'
        $links[0].Url | Should -Be ($help.SearchUrl -f 'Windows%20event%20ID%2010016%20Microsoft-Windows-DistributedCOM')
        $links[1].Id | Should -Be '7031'
        $links[1].Source | Should -Be 'Service Control Manager'
    }

    It 'returns the page and the events when a check has both' {
        $links = @(Get-TestLink -Check 'Blue screens' -Category 'Event Log' -Detail 'Microsoft-Windows-WER-SystemErrorReporting 1001 (2)')
        $links.Kind | Should -Be @('Page', 'Event')
    }

    It 'finds the page of <Check> by <How>' -ForEach @(
        @{ Check = 'Firewall - Public profile'; Category = 'Security'; Key = 'Firewall'; How = 'the part of its name before " - "' }
        @{ Check = 'Drive: Contoso SSD 512GB'; Category = 'Hardware'; Key = 'Drive'; How = 'the part of its name before the colon' }
        @{ Check = 'Print Spooler (Spooler)'; Category = 'Services'; Key = 'Service:Spooler'; How = 'the name of the service in parentheses' }
        @{ Check = 'Windows Update (wuauserv)'; Category = 'Services'; Key = 'Service:wuauserv'; How = 'the name of the service in parentheses' }
    ) {
        $link = @(Get-TestLink -Check $Check -Category $Category)
        $link.Count | Should -Be 1
        $link[0].Kind | Should -Be 'Page'
        $link[0].Url | Should -Be $help.Pages[$Key]
    }

    It 'takes the name in parentheses for a service only among the services' {
        # "Disk (C:)" must not be looked up as a service called "C:".
        @(Get-TestLink -Check 'Some check (Spooler)' -Category 'Elsewhere')[0].Kind | Should -Be 'Search'
    }

    It 'searches for a service without a page by its name and the word "service"' {
        $link = @(Get-TestLink -Check 'Contoso Agent (ContosoSvc)' -Category 'Services')
        $link.Count | Should -Be 1
        $link[0].Kind | Should -Be 'Search'
        $link[0].Url | Should -Be ($help.SearchUrl -f 'Windows%20service%20ContosoSvc%20not%20running')
    }

    It 'has a page for every check that can be a problem in <_>' -ForEach @(
        'Stability index', 'File system', 'Memory test', 'Drive details: Contoso SSD', 'Application crashes', 'Default browser',
        'Microsoft Office', 'Program updates', 'Unsupported programs', 'Disk errors', 'Hardware errors', 'Failed sign-ins',
        'Account lockouts', 'Automatic sign-in', 'Guest account'
    ) {
        @(Get-TestLink -Check $_ -Category 'Nowhere')[0].Kind | Should -Be 'Page'
    }

    It 'links the article of every update that is named, each once' {
        $value = '2 updates: 2026-01 Cumulative Update for Windows 11 (KB5050009) (error 0x80070005), Security Update (KB5049622) (error 0x800F0922)'
        $links = @(Get-TestLink -Check 'Failed updates' -Category 'Windows Update' -Value $value -Detail @('Another one (KB5050009) (error 0x80070005)'))

        $articles = @($links | Where-Object Kind -eq 'Article')
        $articles.Text | Should -Be @('KB5050009', 'KB5049622')
        $articles[0].Url | Should -Be 'https://support.microsoft.com/help/5050009'
        $articles[1].Url | Should -Be 'https://support.microsoft.com/help/5049622'
    }

    It 'searches for every error code that is named, as an error of Windows Update there' {
        $value = '2 updates: Update A (KB5050009) (error 0x80070005), Update B (KB5049622) (error 0x800f0922)'
        $codes = @(Get-TestLink -Check 'Failed updates' -Category 'Windows Update' -Value $value | Where-Object Kind -eq 'Code')

        $codes.Text | Should -Be @('0x80070005', '0x800F0922')
        $codes[0].Url | Should -Be ($help.SearchUrl -f 'Windows%20Update%20error%200x80070005')
        $codes[1].Url | Should -Be ($help.SearchUrl -f 'Windows%20Update%20error%200x800F0922')
    }

    It 'searches for the stop code of a blue screen' {
        $links = @(Get-TestLink -Check 'Blue screens' -Category 'Event Log' -Value '3 in the last 7 days' -Detail @('Stop code 0x0000009F (2x)', 'Stop code 0x00000050 (1x)'))
        $links.Kind | Should -Be @('Page', 'Code', 'Code')
        $links[1].Text | Should -Be '0x0000009F'
        $links[1].Url | Should -Be ($help.SearchUrl -f 'Windows%20stop%20code%200x0000009F')
    }

    It 'searches for the code Device Manager gives a device, each code once' {
        $value = '3 devices: Contoso Camera (code 28), Unknown device (code 28), Contoso Dock (code 43)'
        $codes = @(Get-TestLink -Check 'Devices with problems' -Category 'Hardware' -Value $value | Where-Object Kind -eq 'Code')
        $codes.Text | Should -Be @('code 28', 'code 43')
        $codes[0].Url | Should -Be ($help.SearchUrl -f 'Device%20Manager%20error%20code%2028')
    }

    It 'reads "(code N)" as a code of Device Manager only for the devices' {
        @(Get-TestLink -Check 'Startup programs' -Category 'System' -Value 'Contoso Tool (code 28)' | Where-Object Kind -eq 'Code').Count | Should -Be 0
    }

    It 'links only the first three updates and codes, so a card does not fill with links' {
        $value = (1..6 | ForEach-Object { 'Update (KB500000{0}) (error 0x8007000{0})' -f $_ }) -join ', '
        $links = @(Get-TestLink -Check 'Failed updates' -Category 'Windows Update' -Value $value)
        @($links | Where-Object Kind -eq 'Article').Count | Should -Be 3
        @($links | Where-Object Kind -eq 'Code').Count | Should -Be 3
    }

    It 'never puts anything but the number or the code into the address' {
        $value = '1 update: Update for Marko Horvat on D:\Private (KB5050009) (error 0x80070005)'
        foreach ($link in Get-TestLink -Check 'Failed updates' -Category 'Windows Update' -Value $value -Detail @('C:\Users\marko\file.txt 0xZZ', 'KB12 is too short')) {
            $link.Url | Should -Not -Match 'Marko|Horvat|Private|Users|file'
        }
    }

    It 'takes nothing for a code that only looks like one' {
        $links = @(Get-TestLink -Check 'Failed updates' -Category 'Windows Update' -Value 'KB12 0x1234 0x123456789ABCDEF0 KB1234567890')
        @($links | Where-Object { $_.Kind -in 'Article', 'Code' }).Count | Should -Be 0
    }

    It 'does not read the number of an event as anything else' {
        $links = @(Get-TestLink -Check 'System log - errors' -Category 'Event Log' -Detail @('Microsoft-Windows-Kernel-Power 41 (3)'))
        $links.Kind | Should -Be @('Event')
    }

    It 'returns only addresses that begin with https' {
        foreach ($check in 'Disk (C:)', 'Guest account', 'System log - errors') {
            foreach ($link in Get-TestLink -Check $check -Category 'Event Log' -Detail 'Source 1 (1)') {
                $link.Url | Should -Match '^https://'
            }
        }
    }
}

Describe 'The links of a result card' {
    It 'gives a problem the page that explains it' {
        $item = Get-TestItem -Result (New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '3 % free' -Recommendation 'Free up space.')
        @($item.Links).Count | Should -Be 1
        $item.Links[0].Label | Should -Be 'What this means and how to fix it'
        $item.Links[0].Url | Should -Be $help.Pages['Disk']
    }

    It 'gives a problem without a page a search for its name, never for its value' {
        $item = Get-TestItem -Result (New-TestResult -Category 'System' -Check 'Scheduled tasks' -Status Warning -Value 'Failed for Marko' -Recommendation 'Look at them.')
        $item.Links[0].Label | Should -Be 'Search the web for this problem'
        $item.Links[0].Url | Should -Not -Match 'Marko'
    }

    It 'offers the article of a failed update and a search for its error code below the fix' {
        $item = Get-TestItem -Result (New-TestResult -Category 'Windows Update' -Check 'Failed updates' -Status Warning `
                -Value '1 update: 2026-01 Cumulative Update for Windows 11 (KB5050009) (error 0x80070005)' -Recommendation 'Run the troubleshooter.')

        $item.Links.Label | Should -Be @('What this means and how to fix it', 'About update KB5050009', 'Search the web for error 0x80070005')
        $item.Links[1].Url | Should -Be 'https://support.microsoft.com/help/5050009'
    }

    It 'offers a search for the code of a device that does not work' {
        $item = Get-TestItem -Result (New-TestResult -Category 'Hardware' -Check 'Devices with problems' -Status Warning `
                -Value '1 devices: Contoso Camera (code 28)' -Recommendation 'Install the driver.')
        $item.Links.Label | Should -Be @('What this means and how to fix it', 'Search the web for error code 28')
    }

    It 'offers no link for the updates of a result that is fine' {
        $item = Get-TestItem -Result (New-TestResult -Category 'Windows Update' -Check 'Last installed update' -Status OK -Value 'KB5050009, 3 days ago')
        @($item.Links).Count | Should -Be 0
    }

    It 'gives no link to a result that is fine, and none to one that could not be read' {
        @((Get-TestItem -Result (New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status OK -Value '60 % free')).Links).Count | Should -Be 0
        @((Get-TestItem -Result (New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Warning -Value 'Unavailable')).Links).Count | Should -Be 0
    }

    It 'turns every event in the details into a line that can be clicked, with the exact event number' {
        $result = New-TestResult -Category 'Event Log' -Check 'System log - errors' -Status Warning -Value '66 in the last 7 days' `
            -Recommendation 'Look them up.' -Details @('Microsoft-Windows-DistributedCOM 10016 (45)', 'Service Control Manager 7031 (16)')
        $item = Get-TestItem -Result $result

        @($item.MoreItems).Count | Should -Be 2
        $item.MoreItems[0].Text | Should -Be 'Event 10016: DistributedCOM (45x)'
        $item.MoreItems[0].Url | Should -Match 'event%20ID%2010016'
        $item.MoreItems[1].Text | Should -Be 'Event 7031: Service Control Manager (16x)'
        # The search already is the explanation; no second, vaguer link below the fix.
        @($item.Links).Count | Should -Be 0
        # The one text the search field looks through stays as it was.
        $item.More | Should -Be "Microsoft-Windows-DistributedCOM 10016 (45)`nService Control Manager 7031 (16)"
    }

    It 'makes the events of a result that is fine clickable too' {
        $result = New-TestResult -Category 'Event Log' -Check 'Application log - errors' -Status OK -Value '11 in the last 7 days' -Details @('Application Error 1000 (7)')
        $item = Get-TestItem -Result $result
        $item.MoreItems[0].Url | Should -Match '^https://'
        @($item.Links).Count | Should -Be 0
    }

    It 'leaves any other line of the details as plain text' {
        $result = New-TestResult -Category 'System' -Check 'Startup programs' -Status Warning -Value '28 programs' -Recommendation 'Disable some.' -Details @('Steam', 'Teams')
        $item = Get-TestItem -Result $result
        $item.MoreItems.Text | Should -Be @('Steam', 'Teams')
        $item.MoreItems.Url | Should -Be @('', '')
    }
}

Describe 'Opening a link' -Skip:(-not $isSta) {
    BeforeAll {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
    }

    It 'opens the address and says so' {
        Mock -ModuleName HelpdeskToolkit Open-WebAddress { $true }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'ContosoHTML'; Path = 'C:\Contoso\browser.exe'; Exists = $true; IsBroken = $false; Usable = 'C:\Contoso\browser.exe' } }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowHelpLink -Gui $Gui -Url 'https://support.microsoft.com/windows/activation/activate-windows' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Open-WebAddress -Times 1 -Exactly -Scope It -ParameterFilter { $Url -eq 'https://support.microsoft.com/windows/activation/activate-windows' }
        $gui.Controls.StatusText.Text | Should -Be 'The page was opened in the browser.'
    }

    It 'says so when the page had to be opened in another browser because the default one is gone' {
        Mock -ModuleName HelpdeskToolkit Open-WebAddress { $true }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'RemovedHTML'; Path = 'C:\Gone\browser.exe'; Exists = $false; IsBroken = $true; Usable = 'C:\Other\browser.exe' } }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowHelpLink -Gui $Gui -Url 'https://example.test/' } | Should -BeTrue

        $gui.Controls.StatusText.Text | Should -Be 'The page was opened in another browser: the default browser of Windows is no longer installed. Choose one under Settings > Apps > Default apps.'
    }

    It 'opens nothing for an address that is refused, and says nothing' {
        Mock -ModuleName HelpdeskToolkit Open-WebAddress { $false }
        $before = $gui.Controls.StatusText.Text
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowHelpLink -Gui $Gui -Url 'file:///C:/Windows/System32/calc.exe' } | Should -BeFalse
        $gui.Controls.StatusText.Text | Should -Be $before
    }

    It 'says so when the address cannot be opened' {
        Mock -ModuleName HelpdeskToolkit Open-WebAddress { throw 'No browser' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowHelpLink -Gui $Gui -Url 'https://example.test/' } | Should -BeFalse
        $gui.Controls.StatusText.Text | Should -Be 'The page could not be opened: No browser'
    }

    It 'is what a click on a link in a card does' {
        Mock -ModuleName HelpdeskToolkit Open-WindowHelpLink { $true }
        Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
        $button = New-Object -TypeName System.Windows.Controls.Button
        $button.DataContext = [PSCustomObject]@{ Label = 'What this means and how to fix it'; Url = 'https://example.test/' }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Source = $button } { Invoke-WindowCardClick -Gui $Gui -Source $Source }
        Should -Invoke -ModuleName HelpdeskToolkit Open-WindowHelpLink -Times 1 -Exactly -Scope It -ParameterFilter { $Url -eq 'https://example.test/' }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 0 -Exactly -Scope It
    }
}

Describe 'The layout' {
    BeforeAll {
        $layout = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml'))
    }

    It 'shows the links of a problem on the page of a category and in the list of the Overview' {
        [regex]::Matches($layout, 'ItemsSource="\{Binding Links\}"').Count | Should -Be 2
    }

    It 'shows the details line by line in all three kinds of card' {
        [regex]::Matches($layout, 'ItemsSource="\{Binding MoreItems\}"').Count | Should -Be 3
        $layout | Should -Not -Match 'Text="\{Binding More\}"'
    }
}

Describe 'Get-EventLogHealth: the events behind a count' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable[0].LogName -eq 'System' -and -not $FilterHashtable[0].ContainsKey('ProviderName') -and -not $FilterHashtable[0].ContainsKey('Id') } {
            New-TestEvent -Level 2 -Source 'Service Control Manager' -Id 7031 -Count 3
            New-TestEvent -Level 2 -Source 'Microsoft-Windows-DistributedCOM' -Id 10016 -Count 9
            New-TestEvent -Level 2 -Source 'Service Control Manager' -Id 7000 -Count 1
            New-TestEvent -Level 1 -Source 'Microsoft-Windows-Kernel-Power' -Id 41 -Count 2
        }
        $results = Get-EventLogHealth
    }

    It 'lists every kind of error with its source, its event number and how often it happened, the most frequent first' {
        ($results | Where-Object Check -eq 'System log - errors').Details | Should -Be @(
            'Microsoft-Windows-DistributedCOM 10016 (9)'
            'Service Control Manager 7031 (3)'
            'Service Control Manager 7000 (1)'
        )
    }

    It 'lists the critical events separately' {
        ($results | Where-Object Check -eq 'System log - critical events').Details | Should -Be 'Microsoft-Windows-Kernel-Power 41 (2)'
    }

    It 'has no details for a log without such events' {
        @(($results | Where-Object Check -eq 'Application log - errors').Details | Where-Object { $_ }).Count | Should -Be 0
    }
}

Describe 'Get-EventLogHealth: the stop codes behind the blue screens' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent {
            throw (New-TestErrorRecord -Message 'No events were found' -ErrorId 'NoMatchingEventsFound')
        }
    }

    It 'lists every stop code with how often it happened, the most frequent first' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' } {
            New-TestEvent -Source 'Microsoft-Windows-WER-SystemErrorReporting' -Id 1001 -Program '0x00000050 (0xffffa8000c5a0000, 0x0000000000000000, 0xfffff80002a5b0c1, 0x0000000000000002)'
            New-TestEvent -Source 'Microsoft-Windows-WER-SystemErrorReporting' -Id 1001 -Count 2 -Program '0x0000009f (0x0000000000000003, 0xffffe0015d3a7060, 0xfffff8012b4a3990, 0xffffe0015e1c2010)'
        }
        $result = Get-EventLogHealth | Where-Object Check -eq 'Blue screens'

        $result.Value | Should -BeLike '3 *'
        $result.Details | Should -Be @('Stop code 0x0000009F (2x)', 'Stop code 0x00000050 (1x)')
    }

    It 'still counts a blue screen whose event names no stop code' {
        Mock -ModuleName HelpdeskToolkit Get-WinEvent -ParameterFilter { $FilterHashtable.ProviderName -eq 'Microsoft-Windows-WER-SystemErrorReporting' } {
            New-TestEvent -Source 'Microsoft-Windows-WER-SystemErrorReporting' -Id 1001 -Program ''
            [PSCustomObject]@{ Level = 2; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001; Properties = @() }
        }
        $result = Get-EventLogHealth | Where-Object Check -eq 'Blue screens'

        $result.Value | Should -BeLike '2 *'
        @($result.Details).Count | Should -Be 0
    }

    It 'has no details without a blue screen' {
        @((Get-EventLogHealth | Where-Object Check -eq 'Blue screens').Details).Count | Should -Be 0
    }
}

Describe 'The texts of the links' {
    It 'are translated into Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'What this means and how to fix it', 'Search the web for this problem', 'Event {0}: {1} ({2}x)',
            'About update {0}', 'Search the web for error {0}',
            'Look up what this event means and how it is fixed', 'The page was opened in the browser.', 'The page could not be opened: {0}') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
    }
}
