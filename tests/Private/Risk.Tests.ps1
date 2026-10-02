# Tests for "Why this is a problem": the text next to every Warning and Critical result
# that says what the problem leads to when it is left as it is.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit')).Path
    $risks = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Risks.psd1')

    function Get-TestRisk {
        param([string]$Check, [string]$Category = '')
        InModuleScope HelpdeskToolkit -Parameters @{ Check = $Check; Category = $Category } { Get-CheckRisk -Check $Check -Category $Category }
    }
}

Describe 'Get-CheckRisk' {
    It 'returns the text of a check by its name' {
        Get-TestRisk -Check 'Memory usage' -Category 'Hardware' | Should -Be $risks['Memory usage']
    }

    It 'finds "<Check>" under "<Key>"' -ForEach @(
        @{ Check = 'Disk (C:)'; Category = 'Hardware'; Key = 'Disk' }
        @{ Check = 'Drive: Contoso HDD 500GB'; Category = 'Hardware'; Key = 'Drive' }
        @{ Check = 'Drive details: Contoso NVMe 256GB'; Category = 'Hardware'; Key = 'Drive details' }
        @{ Check = 'Wi-Fi: CONTOSO-CORP'; Category = 'Network'; Key = 'Wi-Fi' }
        @{ Check = 'BitLocker (C:)'; Category = 'Security'; Key = 'BitLocker' }
        @{ Check = 'Firewall - Public profile'; Category = 'Security'; Key = 'Firewall' }
        @{ Check = 'Print Spooler (Spooler)'; Category = 'Services'; Key = 'Service:Spooler' }
        @{ Check = 'Windows Update (wuauserv)'; Category = 'Services'; Key = 'Service:wuauserv' }
    ) {
        Get-TestRisk -Check $Check -Category $Category | Should -Be $risks[$Key]
    }

    It 'has a text of its own for the drive Windows is installed on' {
        $windows = InModuleScope HelpdeskToolkit { Get-CheckRisk -Check 'Disk (C:)' -Category 'Hardware' -Value '3 % free (3 GB of 100 GB), Windows drive' }
        $data = InModuleScope HelpdeskToolkit { Get-CheckRisk -Check 'Disk (D:)' -Category 'Hardware' -Value '3 % free (3 GB of 100 GB)' }

        $windows | Should -Be $risks['Disk:Windows drive']
        $windows | Should -Match '^Windows is installed on this drive'
        $data | Should -Be $risks['Disk']
        $windows | Should -Not -Be $data
    }

    It 'says nothing about Windows for a drive that is not the one of Windows' {
        $risks['Disk'] | Should -Not -Match 'Windows'
    }

    It 'only looks at the end of the value, so a name that contains the words changes nothing' {
        InModuleScope HelpdeskToolkit { Get-CheckRisk -Check 'Memory usage' -Category 'Hardware' -Value 'Windows drive tool (3 GB)' } | Should -Be $risks['Memory usage']
        # A check without a text for the Windows drive falls back to its ordinary one.
        InModuleScope HelpdeskToolkit { Get-CheckRisk -Check 'BitLocker (C:)' -Category 'Security' -Value 'Protection off, Windows drive' } | Should -Be $risks['BitLocker']
    }

    It 'prefers the text of the check itself to the one of its category' {
        Get-TestRisk -Check 'Uptime' -Category 'System' | Should -Not -Be $risks['Category:System']
    }

    It 'falls back to the text of the category for a check without one of its own' {
        Get-TestRisk -Check 'Some new check' -Category 'Security' | Should -Be $risks['Category:Security']
        Get-TestRisk -Check 'Contoso Agent (ContosoSvc)' -Category 'Services' | Should -Be $risks['Category:Services']
    }

    It 'returns an empty text when nothing fits' {
        Get-TestRisk -Check 'Some new check' -Category 'Some new category' | Should -Be ''
        Get-TestRisk -Check 'Some new check' | Should -Be ''
    }
}

Describe 'Config\Risks.psd1' {
    BeforeAll {
        $descriptions = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Descriptions.psd1')
        $categories = 'System', 'Specifications', 'Hardware', 'Software', 'Event Log', 'Windows Update', 'Security', 'Network', 'Printers', 'Services'
    }

    It 'has a text for every category that can report a problem, so no problem is left without one' {
        foreach ($category in $categories | Where-Object { $_ -ne 'Specifications' }) {
            $risks.ContainsKey("Category:$category") | Should -BeTrue -Because "a problem in $category needs a text"
        }
    }

    It 'only has keys that belong to a check, a service or a category the tool knows' {
        foreach ($key in $risks.Keys) {
            if ($key -like 'Category:*') {
                $categories | Should -Contain ($key -replace '^Category:', '')
            }
            else {
                $descriptions.ContainsKey($key) | Should -BeTrue -Because "'$key' must be the name of a check (Config\Descriptions.psd1 knows them all)"
            }
        }
    }

    It 'has a text for every monitored service' {
        $services = (Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Thresholds.psd1')).Services
        foreach ($service in $services) {
            $risks.ContainsKey("Service:$service") | Should -BeTrue -Because "the service $service is monitored"
        }
    }

    It 'writes every text as whole sentences of a readable length' {
        foreach ($key in $risks.Keys) {
            $text = [string]$risks[$key]
            $text | Should -Match '^[A-Z].*\.$' -Because "the text of '$key' is shown to the user as it is"
            $text.Length | Should -BeLessThan 320 -Because "the text of '$key' must stay short"
            $text.Length | Should -BeGreaterThan 60 -Because "the text of '$key' must say something"
        }
    }

    It 'has a Croatian translation for every text' {
        try {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
            $missing = @($risks.Keys | Where-Object { (InModuleScope HelpdeskToolkit -Parameters @{ Text = [string]$risks[$_] } { Get-LocalizedText $Text }) -ceq [string]$risks[$_] })
            $missing | Should -BeNullOrEmpty -Because 'the window shows these texts in the language of the user'
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
        }
    }
}

Describe 'ConvertTo-WindowItem: why a problem matters' {
    It 'explains a <Status> result' -ForEach @(
        @{ Status = 'Warning' }
        @{ Status = 'Critical' }
    ) {
        $result = New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status $Status -Value '3 % free' -Recommendation 'Free up space.'
        $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $result } { $Result | ConvertTo-WindowItem }

        $item.Risk | Should -Be $risks['Disk']
        $item.RiskLabel | Should -Be 'WHY THIS IS A PROBLEM'
    }

    It 'says nothing about a result that is <Status>' -ForEach @(
        @{ Status = 'OK' }
        @{ Status = 'Info' }
    ) {
        $result = New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status $Status -Value '60 % free'
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $result } { $Result | ConvertTo-WindowItem }).Risk | Should -Be ''
    }

    It 'says nothing about a check that could not be read: that is no finding' {
        $result = New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Warning -Value 'Unavailable' -Recommendation 'The information could not be read: Access denied'
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $result } { $Result | ConvertTo-WindowItem }).Risk | Should -Be ''
    }

    It 'explains a problem of a check without a text of its own by its category' {
        $result = New-TestResult -Category 'Security' -Check 'Some new check' -Status Warning -Value 'Off'
        (InModuleScope HelpdeskToolkit -Parameters @{ Result = $result } { $Result | ConvertTo-WindowItem }).Risk | Should -Be $risks['Category:Security']
    }

    It 'shows the text and its label in the language of the window' {
        $result = New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status Warning -Value '91 %'
        try {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
            $item = InModuleScope HelpdeskToolkit -Parameters @{ Result = $result } { $Result | ConvertTo-WindowItem }

            $item.Risk | Should -Not -Be $risks['Memory usage']
            $item.Risk | Should -Match '^Kad je memorija puna'
            $item.RiskLabel | Should -Not -Be 'WHY THIS IS A PROBLEM'
            $item.RiskLabel | Should -BeExactly $item.RiskLabel.ToUpper()
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
        }
    }
}

Describe 'The window: why a problem matters' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        $results = @(
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '3 % free' -Recommendation 'Free up space.'
            New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status Warning -Value '91 %' -Recommendation 'Close programs.'
            New-TestResult -Category 'Hardware' -Check 'CPU load' -Status OK -Value '12 %'
        )
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = (New-TestReport -Result $results) } { Show-WindowReport -Gui $Gui -Report $Report }
    }

    It 'hands every problem card of the Overview its text' {
        $cards = @($gui.Controls.ResultItems.ItemsSource)
        $cards.SourceCheck | Should -Be @('Disk (C:)', 'Memory usage')
        $cards[0].Risk | Should -Be $risks['Disk']
        $cards[1].Risk | Should -Be $risks['Memory usage']
    }

    It 'hands the compact cards of a category page the same texts, and none to a result that is fine' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Hardware' }

        @($gui.Controls.ColumnCriticalItems.ItemsSource)[0].Risk | Should -Be $risks['Disk']
        @($gui.Controls.ColumnWarningItems.ItemsSource)[0].Risk | Should -Be $risks['Memory usage']
        @($gui.Controls.ColumnOKItems.ItemsSource)[0].Risk | Should -Be ''
    }

    It 'does not find a result by the text about consequences: a search for "disk" finds the disk, not the memory' {
        $gui.Controls.SearchBox.Text = 'slower disk'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'Overview' }
        @($gui.Controls.ResultItems.ItemsSource).Count | Should -Be 0
        $gui.Controls.SearchBox.Text = ''
    }
}

Describe 'The HTML report: why a problem matters' {
    BeforeAll {
        $results = @(
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '3 % free (3 GB of 100 GB), Windows drive' -Recommendation 'Free up space.'
            New-TestResult -Category 'Hardware' -Check 'CPU load' -Status OK -Value '12 %'
            New-TestResult -Category 'Network' -Check 'Proxy' -Status Warning -Value 'Unavailable' -Recommendation 'The information could not be read: Access denied'
        )
        $html = InModuleScope HelpdeskToolkit -Parameters @{ Report = (New-TestReport -Result $results) } { ConvertTo-HealthReportHtml -Report $Report }
    }

    It 'says next to a problem what it leads to' {
        $html | Should -Match ([regex]::Escape('<div class="risk">Windows is installed on this drive. When it is full, Windows updates no longer install'))
    }

    It 'says it in the problem list and in the card of the category' {
        ([regex]::Matches($html, '<div class="risk">')).Count | Should -Be 2
    }

    It 'puts it before the recommendation: first why, then what to do' {
        $html.IndexOf('<div class="risk">') | Should -BeLessThan $html.IndexOf('<div class="recommendation">Free up space.')
    }

    It 'says nothing about a result that is fine or could not be read' {
        $html | Should -Not -Match ([regex]::Escape('<div class="risk">A network problem'))
    }

    It 'labels it in the stylesheet, like the recommendation' {
        $html | Should -Match 'content: "Why this is a problem: "'
    }
}
