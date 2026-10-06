# Tests for a window that is given results nobody planned for: names with characters that
# mean something to XAML, to regular expressions or to the -f operator, texts that are
# empty or very long, a category the window has never heard of, hundreds of results, a
# report without results. Whatever a computer reports, no page of the window may fail.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    # Texts that have broken programs before.
    $awkward = @(
        'Tool {0} {beta} {1:N2}'
        'A & B <Contoso> "quoted" ''single'''
        'C:\Program Files (x86)\Contoso\[v2]\app.exe $1 $& ${name}'
        '100 % (50 % of 200 %) ^$.*+?|\'
        "First line`nSecond line`tafter a tab"
        ([string][char]0x010C + 'akovec ' + [char]0x0161 + [char]0x0111 + [char]0x017E + ' ' + [char]0x4E2D + [char]0x6587)
        ('long ' * 600)
        ' '
    )

    function New-AwkwardReport {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param()

        $categories = 'System', 'Hardware', 'Event Log', 'Windows Update', 'Security', 'A category of the future'
        $number = 0
        $results = foreach ($category in $categories) {
            foreach ($status in 'OK', 'Warning', 'Critical', 'Info') {
                foreach ($text in $awkward) {
                    $number++
                    New-TestResult -Category $category -Check ('Check {0} {1}' -f $number, $text.Substring(0, [math]::Min(40, $text.Length))) -Status $status `
                        -Value $text -Description $text -Allowed $text -Typical $text -Recommendation $text -Details @($text, 'Source 12 (3)', 'KB5050009 (error 0x80070005)')
                }
            }
        }
        # A result as bare as a result can be
        $results += New-TestResult -Category 'System' -Check 'Bare' -Status Warning -Value ''
        $report = New-TestReport -Result $results
        $report | Add-Member -NotePropertyName Timeline -NotePropertyValue @(
            foreach ($text in $awkward) {
                [PSCustomObject]@{ Time = '2026-01-14 09:30'; Level = 'Error'; Kind = $text; Title = $text; Count = 3 }
            }
        )
        $report
    }

    # A report as it would be if not a single check had returned anything.
    function New-EmptyReport {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param()

        $report = New-TestReport -Result @(New-TestResult)
        $report.Results = @()
        $report.Summary = [ordered]@{ OK = 0; Warning = 0; Critical = 0; Info = 0 }
        $report.Score = 100
        $report
    }

    function Get-TestWindow {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }
}

AfterAll {
    InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
}

Describe 'A report full of awkward texts, in <_>' -Skip:(-not $isSta) -ForEach 'en', 'hr' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        InModuleScope HelpdeskToolkit -Parameters @{ Language = $_ } { $script:Language = $Language; $script:Translations = $null }
        $gui = Get-TestWindow
        $report = New-AwkwardReport
    }

    It 'is shown' {
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report } } | Should -Not -Throw
        $gui.Report | Should -Not -BeNullOrEmpty
        @($gui.Controls.CategoryList.ItemsSource).Name | Should -Contain 'A category of the future'
    }

    It 'opens every page, the one of the unknown category included' {
        foreach ($page in @($gui.Controls.CategoryList.ItemsSource).Name) {
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Name = $page } { Show-WindowPage -Gui $Gui -Name $Name } } | Should -Not -Throw -Because "the page '$page' has to open"
        }
    }

    It 'searches for <_>' -ForEach '{0}', '$1', '[v2]', '(x86)', '\', '*', '^$.*+?|', '&', '<Contoso>', 'long', ' ' {
        $gui.Controls.SearchBox.Text = $_
        foreach ($page in 'Overview', 'Hardware', 'Timeline') {
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Name = $page } { Show-WindowPage -Gui $Gui -Name $Name } } | Should -Not -Throw
        }
        $gui.Controls.SearchBox.Text = ''
    }

    It 'filters by every status on every page' {
        foreach ($item in @($gui.Controls.StatusFilter.Items)) {
            $gui.Controls.StatusFilter.SelectedItem = $item
            foreach ($page in 'Overview', 'Security', 'A category of the future') {
                { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Name = $page } { Show-WindowPage -Gui $Gui -Name $Name } } | Should -Not -Throw
            }
        }
        $gui.Controls.StatusFilter.SelectedIndex = 0
    }

    It 'turns every result into a card with texts only' {
        $items = InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { $Report.Results | ConvertTo-WindowItem -ShowCategory }
        @($items).Count | Should -Be @($report.Results).Count
        foreach ($item in $items | Select-Object -First 40) {
            $item.Check | Should -BeOfType [string]
            $item.Value | Should -BeOfType [string]
            foreach ($link in $item.Links) {
                $link.Url | Should -Match '^https://[^\s"]+$' -Because 'only such an address is ever opened'
            }
        }
    }

    It 'is compared with itself and with an empty report' {
        $empty = New-EmptyReport
        { Compare-PCHealthReport -Reference $report -Difference $report } | Should -Not -Throw
        { Compare-PCHealthReport -Reference $empty -Difference $report } | Should -Not -Throw
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report; Previous = $empty } { Show-WindowReport -Gui $Gui -Report $Report -Previous $Previous } } | Should -Not -Throw
    }

    It 'is saved as <_> and, as JSON, read back' -ForEach 'Json', 'Html', 'Csv' {
        $path = Join-Path -Path $TestDrive -ChildPath ('awkward-{0}.{1}' -f [guid]::NewGuid().ToString('N'), $_.ToLowerInvariant())
        { InModuleScope HelpdeskToolkit -Parameters @{ Report = $report; Path = $path; Format = $_ } { & "Export-HealthReport$Format" -Report $Report -Path $Path } } | Should -Not -Throw
        if ($_ -eq 'Json') {
            $loaded = InModuleScope HelpdeskToolkit -Parameters @{ Path = $path } { Import-HealthReport -Path $Path }
            @($loaded.Results).Count | Should -Be @($report.Results).Count
            $loaded.Results[0].Value | Should -Be $report.Results[0].Value
        }
    }
}

Describe 'A report with nothing in it' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Enable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        $gui = Get-TestWindow
    }

    It 'is shown, and its pages open' {
        $report = New-EmptyReport
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } { Show-WindowReport -Gui $Gui -Report $Report } } | Should -Not -Throw
        foreach ($page in @($gui.Controls.CategoryList.ItemsSource).Name) {
            { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Name = $page } { Show-WindowPage -Gui $Gui -Name $Name } } | Should -Not -Throw
        }
    }

    It 'opens a page that does not exist without failing' {
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowPage -Gui $Gui -Name 'No such page' } } | Should -Not -Throw
    }
}

Describe 'The table of translated texts' {
    AfterAll {
        InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
    }

    It 'tells a text in capitals from the same text as it is written, without searching the table' {
        InModuleScope HelpdeskToolkit {
            $script:Language = 'hr'
            $script:Translations = $null
            # The label of a card is written in capitals; the table has the ordinary spelling.
            Get-LocalizedText 'Run check' | Should -Be 'Pokreni provjeru'
            Get-LocalizedText 'RUN CHECK' | Should -Be 'POKRENI PROVJERU'
            $script:Translations.Exact.Contains('Run check') | Should -BeTrue
            $script:Translations.Exact.Contains('RUN CHECK') | Should -BeFalse
            # A text the table has in capitals is taken as it is.
            Get-LocalizedText 'OK' | Should -Be $script:Translations.Text['OK']
        }
    }

    It 'does not grow without end while values keep changing' {
        InModuleScope HelpdeskToolkit {
            $script:Language = 'hr'
            $script:Translations = $null
            foreach ($number in 1..5200) {
                [void](Get-LocalizedText ('A value that was never seen before: {0}' -f $number))
            }
            $script:Translations.Cache.Count | Should -BeLessOrEqual 5000
            # A text is still translated after the table started again.
            Get-LocalizedText 'Run check' | Should -Be 'Pokreni provjeru'
        }
    }
}
