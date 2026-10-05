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
        param([string]$Check, [string]$Category = '', [string[]]$Detail = @())
        InModuleScope HelpdeskToolkit -Parameters @{ Check = $Check; Category = $Category; Detail = $Detail } {
            Get-CheckHelpLink -Check $Check -Category $Category -Detail $Detail
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
        $link = @(Get-TestLink -Check 'Guest account' -Category 'Security')
        $link.Count | Should -Be 1
        $link[0].Kind | Should -Be 'Search'
        $link[0].Url | Should -Be ($help.SearchUrl -f 'Windows%20Guest%20account')
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
        $item = Get-TestItem -Result (New-TestResult -Category 'Security' -Check 'Guest account' -Status Warning -Value 'Enabled for Marko' -Recommendation 'Disable it.')
        $item.Links[0].Label | Should -Be 'Search the web for this problem'
        $item.Links[0].Url | Should -Not -Match 'Marko'
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
        $item.MoreItems[0].Text | Should -Be 'Event 10016: DistributedCOM, 45 times'
        $item.MoreItems[0].Url | Should -Match 'event%20ID%2010016'
        $item.MoreItems[1].Text | Should -Be 'Event 7031: Service Control Manager, 16 times'
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

    It 'hands the address to Windows and says so' {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowHelpLink -Gui $Gui -Url 'https://support.microsoft.com/windows/activation/activate-windows' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'https://support.microsoft.com/windows/activation/activate-windows' }
        $gui.Controls.StatusText.Text | Should -Be 'The page was opened in the browser.'
    }

    It 'opens nothing that is not an https address' -ForEach @(
        'http://example.test/page', 'file:///C:/Windows/System32/calc.exe', 'C:\Windows\System32\calc.exe', 'https://example.test/a b', ''
    ) {
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Url = $_ } { Open-WindowHelpLink -Gui $Gui -Url $Url } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
    }

    It 'says so when Windows cannot open the address' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'No browser' }
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

Describe 'The texts of the links' {
    It 'are translated into Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'What this means and how to fix it', 'Search the web for this problem', 'Event {0}: {1}, {2} times',
            'Look up what this event means and how it is fixed', 'The page was opened in the browser.', 'The page could not be opened: {0}') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
    }
}
