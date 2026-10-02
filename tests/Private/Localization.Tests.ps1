# Tests for the translation of the window: how a text is looked up, and that the
# Croatian file covers everything the window can show.

BeforeDiscovery {
    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $descriptionData = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Descriptions.psd1')
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $languageFile = Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1'

    # Translates a text into Croatian.
    function ConvertTo-Croatian {
        param([string]$Text)
        InModuleScope HelpdeskToolkit -Parameters @{ Text = $Text } { Get-LocalizedText $Text }
    }

    # Every text that is written in the code or in the layout of the window.
    function Get-SourceText {
        $texts = New-Object -TypeName 'System.Collections.Generic.List[string]'

        [xml]$xaml = Get-Content -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml') -Raw
        foreach ($node in $xaml.SelectNodes('//*[@Text or @Content or @ToolTip or @Title]')) {
            foreach ($attribute in 'Text', 'Content', 'ToolTip', 'Title') {
                $value = $node.GetAttribute($attribute)
                if ($value -and -not $value.StartsWith('{') -and $value -match '[A-Za-z]{2}') {
                    $texts.Add($value)
                }
            }
        }

        foreach ($file in Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private'), (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $calls = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Get-LocalizedText' }, $true)
            foreach ($call in $calls) {
                $argument = $call.CommandElements[1]
                if ($argument -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $texts.Add($argument.Value)
                }
            }
        }

        $texts | Sort-Object -Unique
    }

    InModuleScope HelpdeskToolkit { $script:Language = 'hr'; $script:Translations = $null }
}

AfterAll {
    InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
}

Describe 'Get-LocalizedText' {
    It 'returns the text unchanged while the language is English' {
        try {
            InModuleScope HelpdeskToolkit { $script:Language = 'en'; Get-LocalizedText 'Run check' } | Should -Be 'Run check'
        }
        finally {
            InModuleScope HelpdeskToolkit { $script:Language = 'hr' }
        }
    }

    It 'returns the translation of a whole text' {
        ConvertTo-Croatian 'Run check' | Should -Be 'Pokreni provjeru'
    }

    It 'returns an empty text for an empty text' {
        ConvertTo-Croatian '' | Should -Be ''
    }

    It 'returns a text without a translation unchanged' {
        ConvertTo-Croatian 'Contoso Graphics 770' | Should -Be 'Contoso Graphics 770'
    }

    It 'translates a text in capitals with the translation in capitals' {
        ConvertTo-Croatian 'CRITICAL' | Should -BeExactly 'KRITIČNO'
        ConvertTo-Croatian 'RECOMMENDED FIX' | Should -BeExactly 'PREPORUČENO RJEŠENJE'
        ConvertTo-Croatian 'Critical' | Should -BeExactly 'Kritično'
    }

    It 'leaves the placeholders of a text in place, so the code can still fill them in' {
        (ConvertTo-Croatian 'Check finished: {0} results.') -f 12 | Should -Be 'Provjera je gotova: 12 rezultata.'
        (ConvertTo-Croatian 'What the computer is doing right now. Updated {0:HH:mm:ss}; refreshes about every {1} seconds.') -f [datetime]'2026-01-15 10:30:05', 2 |
            Should -Match 'Ažurirano 10:30:05'
    }

    It 'recognizes a text whose placeholders were filled in already' {
        ConvertTo-Croatian 'No update was installed for more than 45 days. Open Settings > Windows Update and check for updates.' |
            Should -Be 'Nijedno ažuriranje nije instalirano više od 45 dana. Otvori Postavke > Windows Update i provjeri ima li ažuriranja.'
    }

    It 'translates what stood at a placeholder when that is a text of its own' {
        ConvertTo-Croatian 'The computer has never been scanned. Run a scan: open Windows Security > Virus & threat protection and choose "Quick scan".' |
            Should -Be 'Računalo nikad nije skenirano. Pokreni skeniranje: otvori Sigurnost u sustavu Windows > Zaštita od virusa i prijetnji i odaberi "Brzo skeniranje".'
    }

    It 'translates several known sentences in a row' {
        $advice = 'The drive is too hot. Clean the dust out of the computer and make sure the air can flow; heat shortens the life of a drive.',
            'The drive is close to the end of its rated lifetime. Back up the data and plan to replace it.' -join ' '
        ConvertTo-Croatian $advice | Should -Be ('Pogon je prevruć. Očisti prašinu iz računala i provjeri može li zrak strujati; toplina skraćuje vijek pogona. ' +
            'Pogon je blizu kraja predviđenog životnog vijeka. Napravi sigurnosnu kopiju podataka i planiraj zamjenu.')
    }

    It 'translates "<Text>" as "<Expected>"' -ForEach @(
        @{ Text = '28 programs: A, B and 20 more'; Expected = 'Programi (28): A, B i još 20' }
        @{ Text = '0 tasks'; Expected = 'Zadaci (0)' }
        @{ Text = '9 in the last 7 days: EXCEL.EXE (6)'; Expected = '9 u zadnjih 7 dana: EXCEL.EXE (6)' }
        @{ Text = 'None in the last 30 days'; Expected = 'Nema u zadnjih 30 dana' }
        @{ Text = '3.1 % free (7.4 GB of 237.9 GB)'; Expected = '3.1 % slobodno (7.4 GB od 237.9 GB)' }
        @{ Text = '3.1 % free (7.4 GB of 237.9 GB), Windows drive'; Expected = '3.1 % slobodno (7.4 GB od 237.9 GB), disk s Windowsom' }
        @{ Text = '88 % (14 GB of 15.8 GB used)'; Expected = '88 % (zauzeto 14 GB od 15.8 GB)' }
        @{ Text = 'KB5000001 on 2026-09-18 (12 days ago)'; Expected = 'KB5000001, 2026-09-18 (prije 12 dana)' }
        @{ Text = 'Supported until 2026-10-13 (13 days left)'; Expected = 'Podržano do 2026-10-13 (još 13 dana)' }
        @{ Text = 'SSD, NVMe, 238.5 GB, health: Healthy'; Expected = 'SSD, NVMe, 238.5 GB, stanje: ispravno' }
        @{ Text = 'Running (start mode: Auto)'; Expected = 'Radi (pokretanje: Auto)' }
        @{ Text = '10.20.30.1 replied in 3 ms'; Expected = '10.20.30.1 odgovara za 3 ms' }
        @{ Text = '64 % (plugged in)'; Expected = '64 % (na punjaču)' }
        @{ Text = '0 - 85 % (critical above 95 %)'; Expected = '0 - 85 % (kritično iznad 95 %)' }
        @{ Text = '15 - 100 % free (critical below 5 % free)'; Expected = '15 - 100 % slobodno (kritično ispod 5 % slobodno)' }
        @{ Text = '0 - 7 days'; Expected = '0 - 7 dana' }
        @{ Text = 'step 3 of 10'; Expected = 'korak 3 od 10' }
    ) {
        ConvertTo-Croatian $Text | Should -Be $Expected
    }

    It 'remembers a text it had to work out, so the next lookup is immediate' {
        ConvertTo-Croatian '5 tasks: A, B' | Out-Null
        InModuleScope HelpdeskToolkit { $script:Translations.Cache['5 tasks: A, B'] } | Should -Be 'Zadaci (5): A, B'
    }
}

Describe 'Get-LocalizedCheckName' {
    It 'translates the name of a check' {
        InModuleScope HelpdeskToolkit { Get-LocalizedCheckName 'Memory usage' } | Should -Be 'Zauzeće memorije'
    }

    It 'translates only the first part of a name that ends with the name of a thing' {
        InModuleScope HelpdeskToolkit { Get-LocalizedCheckName 'Drive: Contoso NVMe 256GB' } | Should -Be 'Pogon: Contoso NVMe 256GB'
        InModuleScope HelpdeskToolkit { Get-LocalizedCheckName 'Largest folders (C:)' } | Should -Match '^\S.* \(C:\)$'
        InModuleScope HelpdeskToolkit { Get-LocalizedCheckName 'Largest folders (C:)' } | Should -Not -Match 'Largest'
    }

    It 'returns an unknown name unchanged' {
        InModuleScope HelpdeskToolkit { Get-LocalizedCheckName 'Contoso Agent (ContosoSvc)' } | Should -Be 'Contoso Agent (ContosoSvc)'
    }

    It 'names the checks in the list of changes in the language of the window' -Skip:([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
        $before = New-TestReport -Result @(New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status 'OK')
        $after = New-TestReport -Result @(New-TestResult -Category 'Hardware' -Check 'Memory usage' -Status 'Warning')

        $text = InModuleScope HelpdeskToolkit -Parameters @{ Before = $before; After = $after } {
            $gui = New-HealthCheckWindow
            Show-WindowReport -Gui $gui -Report $After -Previous $Before
            @($gui.Controls.ChangesItems.ItemsSource).Text
        }

        $text | Should -Be 'Hardver / Zauzeće memorije'
    }
}

Describe 'Import-TranslationTable' {
    It 'returns empty tables for a language without a file, so the window falls back to English' {
        $table = InModuleScope HelpdeskToolkit { Import-TranslationTable -Language 'xx' }
        $table.Text.Count | Should -Be 0
        @($table.Patterns).Count | Should -Be 0
    }

    It 'does not use a text with hardly any words of its own to recognize other texts' {
        $table = InModuleScope HelpdeskToolkit { Import-TranslationTable -Language 'hr' }
        $table.Templates.Translation | Should -Not -Contain '{0} od {1}'
        $table.Templates.Count | Should -BeGreaterThan 20
    }
}

Describe 'The Croatian translation file' {
    BeforeAll {
        $text = [System.IO.File]::ReadAllText($languageFile, [System.Text.Encoding]::UTF8)
        $data = InModuleScope HelpdeskToolkit -Parameters @{ Text = $text } { ConvertFrom-DataFileText -Text $Text }
        $table = InModuleScope HelpdeskToolkit { Import-TranslationTable -Language 'hr' }
    }

    It 'starts with a byte order mark, so every editor and PowerShell version reads its letters correctly' {
        $bytes = [System.IO.File]::ReadAllBytes($languageFile)
        $bytes[0], $bytes[1], $bytes[2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'is plain data with at most 500 entries per table, which is all PowerShell accepts' {
        foreach ($name in $data.Keys | Where-Object { $_ -ne 'Patterns' }) {
            $data[$name].Count | Should -BeLessOrEqual 500 -Because "the table $name must stay loadable"
        }
    }

    It 'keeps its Croatian letters' {
        $table.Text['Critical'] | Should -BeExactly 'Kritično'
        $table.Text['Open Device Manager'] | Should -BeExactly 'Otvori Upravitelj uređaja'
    }

    It 'has no empty translation' {
        $table.Text.Keys | Where-Object { -not $table.Text[$_] } | Should -BeNullOrEmpty
    }

    It 'keeps every placeholder of a text in its translation' {
        foreach ($key in $table.Text.Keys) {
            $expected = [regex]::Matches($key, '\{(\d+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
            $actual = [regex]::Matches($table.Text[$key], '\{(\d+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
            ($actual -join ',') | Should -Be ($expected -join ',') -Because "the translation of '$key' must use the same placeholders"
        }
    }

    It 'only contains patterns that are valid regular expressions' {
        foreach ($pattern in $table.Patterns) {
            { [regex]::Replace('sample text 12', $pattern.Match, $pattern.Text) } | Should -Not -Throw -Because "the pattern '$($pattern.Match)' must be usable"
        }
    }

    It 'translates every text of the window layout and of the window code' {
        # These are the same in both languages on purpose: names, abbreviations and the
        # terms of Windows for parts of the memory, which have no Croatian name in use.
        $same = 'HELPDESKTOOLKIT', 'OK', 'Info', 'English', 'Hrvatski', 'HelpdeskToolkit {0}  |  PowerShell {1}',
            'Paged pool', 'Non-paged pool', 'Page file', 'INTERNET', '1 problem'
        $missing = Get-SourceText | Where-Object { $same -notcontains $_ -and (ConvertTo-Croatian $_) -ceq $_ }
        $missing | Should -BeNullOrEmpty -Because 'every text the window shows needs a Croatian translation in Lang\hr.psd1'
    }

    It 'translates the caption of every button that opens a place in Windows' {
        $actions = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Actions.psd1')
        $missing = $actions.Values | ForEach-Object { $_.Label } | Sort-Object -Unique | Where-Object { (ConvertTo-Croatian $_) -ceq $_ }
        $missing | Should -BeNullOrEmpty
    }

    It 'translates the explanation of the check "<_>"' -ForEach @($descriptionData.Keys | Sort-Object) {
        $descriptions = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Descriptions.psd1')
        ConvertTo-Croatian $descriptions[$_] | Should -Not -BeExactly $descriptions[$_]
    }

    It 'translates every recommendation that is written in the checks' {
        # The recommendations are the long texts in the check functions that end like a
        # sentence. A text with a placeholder is filled in the way the check would.
        $missing = foreach ($file in Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter 'Get-*.ps1') {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$null)
            $strings = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
            foreach ($string in $strings) {
                $value = $string.Value
                if ($value.Length -ge 40 -and $value -match '^[A-Z].*[.)]$' -and $value -match ' ') {
                    $filled = [regex]::Replace($value, '\{\d+(:[^}]*)?\}', '7')
                    if ((ConvertTo-Croatian $filled) -ceq $filled) {
                        '{0}: {1}' -f $file.BaseName, $value
                    }
                }
            }
        }
        $missing | Should -BeNullOrEmpty
    }
}

Describe 'Assets\DarkTheme.psd1' {
    BeforeAll {
        $palette = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Assets\DarkTheme.psd1')
        [xml]$xaml = Get-Content -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml') -Raw
        $namespaces = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $xaml.NameTable
        $namespaces.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
        $brushes = @($xaml.SelectNodes('//*[local-name()="SolidColorBrush"][@x:Key]', $namespaces) | ForEach-Object { $_.GetAttribute('Key', 'http://schemas.microsoft.com/winfx/2006/xaml') })
    }

    It 'only names brushes that exist in the window layout' {
        $palette.Keys | Where-Object { $brushes -notcontains $_ } | Should -BeNullOrEmpty
    }

    It 'gives every color as six hexadecimal digits' {
        foreach ($key in $palette.Keys) {
            $palette[$key] | Should -Match '^#[0-9A-Fa-f]{6}$' -Because "the color of $key must be valid"
        }
    }

    It 'replaces the colors of the surfaces and of the text' {
        foreach ($key in 'WindowBrush', 'SurfaceBrush', 'BorderBrush', 'TextBrush', 'MutedBrush') {
            $palette.ContainsKey($key) | Should -BeTrue -Because "a dark theme without $key would leave a light part"
        }
    }
}

Describe 'The window layout' {
    It 'writes every color as a named brush, so the dark theme can replace it' {
        [xml]$xaml = Get-Content -LiteralPath (Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml') -Raw
        $body = $xaml.DocumentElement.SelectNodes('//*[not(ancestor-or-self::*[local-name()="Window.Resources"])]')
        $hardCoded = foreach ($node in $body) {
            foreach ($attribute in $node.Attributes) {
                if ($attribute.Value -match '^#[0-9A-Fa-f]{6,8}$') {
                    '{0} {1}="{2}"' -f $node.LocalName, $attribute.Name, $attribute.Value
                }
            }
        }
        $hardCoded | Should -BeNullOrEmpty
    }
}
