# Tests for what differs on computers other than the one the tool was written on:
# regional settings whose calendar does not count the year 2026 (Saudi Arabia, Thailand,
# Iran), a language in which "I" and "i" are not the same letter in two sizes (Turkish),
# and a screen that is smaller than the window was designed for (most laptops).
#
# The regional settings are those of the thread that runs the test; every test puts
# them back.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    # Runs the script block as a computer with the given regional settings would.
    function Invoke-InCulture {
        param([string]$Culture, [scriptblock]$Action)

        $thread = [System.Threading.Thread]::CurrentThread
        $previous = $thread.CurrentCulture
        try {
            $thread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
            & $Action
        }
        finally {
            $thread.CurrentCulture = $previous
        }
    }

    # Whether the settings really count the years differently on this Windows; a
    # computer that lacks them cannot run the test.
    function Test-OtherCalendar {
        param([string]$Culture)
        try {
            (Invoke-InCulture -Culture $Culture -Action { [cultureinfo]::CurrentCulture.Calendar.GetYear((New-Object -TypeName datetime -ArgumentList 2026, 3, 9)) }) -ne 2026
        }
        catch {
            $false
        }
    }
}

Describe 'Dates on a computer with the calendar of <_>' -ForEach 'ar-SA', 'th-TH', 'fa-IR' {
    BeforeAll {
        $culture = $_
        $otherCalendar = Test-OtherCalendar -Culture $culture
        $year = (Get-Date).ToString('yyyy', $invariant)

        Mock -ModuleName HelpdeskToolkit Get-SystemHealth { New-TestResult -Category 'System' -Check 'Uptime' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-ComputerSpecification { New-TestResult -Category 'Specifications' -Check 'Processor' -Status Info }
        Mock -ModuleName HelpdeskToolkit Get-HardwareHealth { New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical }
        Mock -ModuleName HelpdeskToolkit Get-SoftwareHealth { New-TestResult -Category 'Software' -Check 'Installed programs' -Status Info }
        Mock -ModuleName HelpdeskToolkit Get-EventLogHealth { New-TestResult -Category 'Event Log' -Check 'System log - errors' -Status Warning }
        Mock -ModuleName HelpdeskToolkit Get-WindowsUpdateHealth { New-TestResult -Category 'Windows Update' -Check 'Pending restart' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-SecurityHealth { New-TestResult -Category 'Security' -Check 'Secure Boot' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-NetworkHealth { New-TestResult -Category 'Network' -Check 'Proxy' -Status Info }
        Mock -ModuleName HelpdeskToolkit Get-PrinterHealth { New-TestResult -Category 'Printers' -Check 'Print queue' -Status OK }
        Mock -ModuleName HelpdeskToolkit Get-ServiceHealth { New-TestResult -Category 'Services' -Check 'Spooler' -Status OK }
        Mock -ModuleName HelpdeskToolkit Write-Progress { }
        Mock -ModuleName HelpdeskToolkit Get-ChangeTimeline {
            [PSCustomObject]@{ Time = (New-Object -TypeName datetime -ArgumentList 2026, 1, 14, 9, 5, 0); Level = 'Problem'; Kind = 'Program crashed'; Title = 'editor.exe'; Count = 3 }
        }
    }

    It 'really is another calendar here, or the tests below say nothing' {
        if (-not $otherCalendar) {
            Set-ItResult -Skipped -Because "this Windows does not have the calendar of $culture"
            return
        }
        $otherCalendar | Should -BeTrue
    }

    It 'writes the time of a report in the calendar every program reads' {
        $report = Invoke-InCulture -Culture $culture -Action { Get-PCHealthReport }
        $report.GeneratedAt | Should -Match ('^{0}-\d\d-\d\d \d\d:\d\d:\d\d$' -f $year)
        $report.Timeline[0].Time | Should -Be '2026-01-14 09:05'
    }

    It 'finds a kept report again, with the time it was made' {
        $report = Invoke-InCulture -Culture $culture -Action { Get-PCHealthReport }
        $report.ComputerName = 'FIN-LT-014'
        $points = @(Invoke-InCulture -Culture $culture -Action {
                InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } {
                    [void](Save-HealthReportHistory -Report $Report)
                    Get-HealthScoreHistory -ComputerName ([string]$Report.ComputerName)
                }
            })
        $points.Count | Should -BeGreaterThan 0
        $points[-1].Time.Year | Should -Be (Get-Date).Year
        ((Get-Date) - $points[-1].Time).TotalMinutes | Should -BeLessThan 5
    }

    It 'writes a date inside a result in that calendar too' {
        # The three releases of the test configuration: out of support, ending soon,
        # supported for a long time. Each names a day.
        $values = Invoke-InCulture -Culture $culture -Action {
            InModuleScope HelpdeskToolkit {
                foreach ($release in '90H1', '90H2', '91H1') {
                    (Get-WindowsSupportInfo -Caption 'Microsoft Windows 11 Pro' -BuildNumber 26100 -DisplayVersion $release).Value
                }
            }
        }
        $values.Count | Should -Be 3
        foreach ($value in $values) {
            $value | Should -Match '\b20\d\d-\d\d-\d\d\b' -Because "'$value' has to name a day in the calendar every program reads"
        }
    }

    It 'starts a line of the log with the year every program reads' {
        $path = Invoke-InCulture -Culture $culture -Action { InModuleScope HelpdeskToolkit { Write-AppLog -Message 'Started' -Level Info } }
        (Get-Content -LiteralPath $path | Select-Object -Last 1) | Should -Match ('^{0}-\d\d-\d\d \d\d:\d\d:\d\d \[Info\] Started' -f $year)
    }
}

Describe 'The code of the module and regional settings' {
    BeforeAll {
        $files = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private'), (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1'
        $datePart = 'yyyy|(?<![A-Za-z])MM(?![A-Za-z])|(?<![A-Za-z])dd(?![A-Za-z])'
    }

    It 'formats no date with the calendar of the computer' {
        $found = foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)

            # $date.ToString('yyyy-MM-dd') without a culture
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true) |
                Where-Object {
                    $_.Member.Extent.Text -eq 'ToString' -and $_.Arguments -and $_.Arguments.Count -eq 1 -and
                    $_.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Arguments[0].Value -match $datePart
                } |
                ForEach-Object { '{0}:{1}: {2}' -f $file.Name, $_.Extent.StartLineNumber, $_.Extent.Text }

            # '... {0:yyyy-MM-dd}' -f $date, which uses the settings of the computer
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.BinaryExpressionAst] -and $node.Operator -eq 'Format' }, $true) |
                Where-Object {
                    $_.Left -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $_.Left.Value -match ('\{\d+:[^}]*(' + $datePart + ')[^}]*\}')
                } |
                ForEach-Object { '{0}:{1}: {2}' -f $file.Name, $_.Extent.StartLineNumber, $_.Left.Extent.Text }
        }
        $found | Should -BeNullOrEmpty -Because 'a Thai or Saudi Windows would write another year; use [string]::Format([cultureinfo]::InvariantCulture, ...)'
    }

    It 'changes capital and small letters the same way on every computer' {
        $found = foreach ($file in $files) {
            Select-String -LiteralPath $file.FullName -Pattern '\.ToUpper\(\)|\.ToLower\(\)' | ForEach-Object { '{0}:{1}' -f $file.Name, $_.LineNumber }
        }
        $found | Should -BeNullOrEmpty -Because 'in Turkish "INFO" in small letters is not "info"; use ToUpperInvariant and ToLowerInvariant'
    }
}

Describe 'A Turkish computer' {
    BeforeAll {
        $report = New-TestReport -Result @(
            New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free' -Recommendation 'Free up space.'
            New-TestResult -Category 'Network' -Check 'Proxy' -Status Info -Value 'Not configured'
            New-TestResult -Category 'System' -Check 'Uptime' -Status Warning -Value '9 d' -Recommendation 'Restart.'
        )
    }

    AfterAll {
        InModuleScope HelpdeskToolkit { $script:Language = 'en'; $script:Translations = $null }
    }

    It 'gives the statuses of the HTML report the names its style sheet knows' {
        $html = Invoke-InCulture -Culture 'tr-TR' -Action { InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthReportHtml -Report $Report } }
        $html | Should -MatchExactly '<div class="tile info">'
        $html | Should -MatchExactly '<div class="tile critical">'
        # -cmatch: in Turkish a comparison that ignores capitals takes this letter for an "I".
        $html | Should -Not -MatchExactly ([string][char]0x0131) -Because 'that is the Turkish small letter of "I", which no style sheet and no reader expects'
    }

    It 'writes the status labels of the summary with ordinary capitals' {
        $text = Invoke-InCulture -Culture 'tr-TR' -Action { InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } { ConvertTo-HealthSummaryText -Report $Report } }
        $text | Should -MatchExactly '\[CRITICAL\] Hardware - Disk \(C:\)'
        $text | Should -Not -MatchExactly ([string][char]0x0130)
    }

    It 'still finds every status, category and setting by its name' {
        Invoke-InCulture -Culture 'tr-TR' -Action {
            (Compare-PCHealthReport -Reference $report -Difference $report) | Should -BeNullOrEmpty
            InModuleScope HelpdeskToolkit -Parameters @{ Report = $report } {
                (Get-HealthSummary -Result $Report.Results).Info | Should -Be 1
                Get-CheckHelpLink -Check 'Firewall - Public profile' -Category 'Security' | ForEach-Object Kind | Should -Be 'Page'
                (Get-AppSetting).Language | Should -BeIn 'en', 'hr'
                $script:Language = 'hr'
                $script:Translations = $null
                Get-LocalizedText 'RUN CHECK' | Should -Be 'POKRENI PROVJERU'
                Get-LocalizedText 'Info' | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Limit-WindowToScreen' -Skip:(-not $isSta) {
    BeforeAll {
        function New-TestArea {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds an object in memory.')]
            param([double]$Width, [double]$Height, [double]$Left = 0, [double]$Top = 0)
            New-Object -TypeName System.Windows.Rect -ArgumentList $Left, $Top, $Width, $Height
        }

        function Get-TestWindow {
            (InModuleScope HelpdeskToolkit { New-HealthCheckWindow }).Window
        }
    }

    It 'leaves the window as designed on a screen that has room for it' {
        $window = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Window = $window; Area = (New-TestArea 1920 1040) } { Limit-WindowToScreen -Window $Window -Area $Area } | Should -BeFalse
        $window.Width | Should -Be 1180
        $window.Height | Should -Be 860
    }

    It 'makes it as tall as <Name> allows' -ForEach @(
        @{ Name = 'a laptop screen of 1366 x 768'; Width = 1366; Height = 728; ExpectedWidth = 1180; ExpectedHeight = 728 }
        @{ Name = 'a Full HD screen scaled to 150 %'; Width = 1280; Height = 680; ExpectedWidth = 1180; ExpectedHeight = 680 }
        @{ Name = 'a Full HD screen scaled to 125 %'; Width = 1536; Height = 824; ExpectedWidth = 1180; ExpectedHeight = 824 }
        @{ Name = 'a screen of 1024 x 768'; Width = 1024; Height = 728; ExpectedWidth = 1024; ExpectedHeight = 728 }
    ) {
        $window = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Window = $window; Area = (New-TestArea $Width $Height) } { Limit-WindowToScreen -Window $Window -Area $Area } | Should -BeTrue
        $window.Width | Should -Be $ExpectedWidth
        $window.Height | Should -Be $ExpectedHeight
        # Still not smaller than the layout needs.
        $window.Width | Should -BeGreaterOrEqual $window.MinWidth
        $window.Height | Should -BeGreaterOrEqual $window.MinHeight
    }

    It 'gives way where even the smallest size does not fit, and starts in the corner so the title bar can be reached' {
        $window = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Window = $window; Area = (New-TestArea 800 536 -Left 0 -Top 0) } { Limit-WindowToScreen -Window $Window -Area $Area } | Should -BeTrue
        $window.Width | Should -Be 800
        $window.Height | Should -Be 536
        $window.MinHeight | Should -Be 536
        $window.WindowStartupLocation | Should -Be 'Manual'
        $window.Left | Should -Be 0
        $window.Top | Should -Be 0
    }

    It 'does nothing without an area' {
        $window = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Window = $window; Area = ([System.Windows.Rect]::Empty) } { Limit-WindowToScreen -Window $Window -Area $Area } | Should -BeFalse
        $window.Height | Should -Be 860
    }

    It 'is applied when the window is opened' {
        [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Public\Show-PCHealthCheck.ps1')) | Should -Match 'Limit-WindowToScreen -Window \$window -Area \$area'
    }
}

Describe 'A folder whose name is not plain English' {
    BeforeAll {
        # Cyrillic and Croatian letters, a space, an ampersand, an apostrophe, parentheses
        # and square brackets, which PowerShell reads as wildcards unless told otherwise.
        $cyrillic = -join ([char[]](0x041F, 0x0430, 0x043F, 0x043A, 0x0430))
        $croatian = -join ([char[]](0x017D, 0x0065, 0x006C, 0x006A, 0x006B, 0x006F, 0x0020, 0x0160, 0x0111))
        $folder = Join-Path -Path $TestDrive -ChildPath ("$cyrillic & $croatian's (copy) [v2]")
        [void][System.IO.Directory]::CreateDirectory($folder)
        Copy-Item -LiteralPath $moduleRoot -Destination $folder -Recurse
        $manifest = Join-Path -Path $folder -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1'

        $program = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
        $powershell = Join-Path -Path $PSHOME -ChildPath $program

        # The path reaches the new process through the environment, so no quoting of
        # the command line can get in the way of what is tested.
        $env:HELPDESKTOOLKIT_TEST_MANIFEST = $manifest
    }

    AfterAll {
        $env:HELPDESKTOOLKIT_TEST_MANIFEST = $null
    }

    It 'loads the module, its configuration and its translations from there' {
        $command = 'Import-Module -Name $env:HELPDESKTOOLKIT_TEST_MANIFEST -ErrorAction Stop; ' +
            '$module = Get-Module HelpdeskToolkit; ' +
            '@(Get-Command -Module HelpdeskToolkit).Count; ' +
            '& $module { (Get-HealthThreshold).Score.WarningPenalty; (Get-CheckHelpLink -Check ''Disk (C:)'' -Category ''Hardware'').Kind; ' +
            '$script:Language = ''hr''; Get-LocalizedText ''Run check'' }'
        $output = @(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $command 2>&1 | ForEach-Object { [string]$_ })

        $LASTEXITCODE | Should -Be 0 -Because ($output -join ' | ')
        $output[0] | Should -Be '16'
        [int]$output[1] | Should -BeGreaterThan 0
        $output[2] | Should -Be 'Page'
        $output[3] | Should -Be 'Pokreni provjeru'
    }

    It 'reads every file of its own literally' {
        # A cmdlet that is given -Path takes [v2] in a folder name for a pattern.
        $found = foreach ($file in Get-ChildItem -LiteralPath $moduleRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1' }) {
            Select-String -LiteralPath $file.FullName -Pattern 'Import-PowerShellDataFile -Path|Get-ChildItem -Path \(Join-Path -Path \$(PSScriptRoot|script:ModuleRoot)' |
                ForEach-Object { '{0}:{1}' -f $file.Name, $_.LineNumber }
        }
        $found | Should -BeNullOrEmpty
    }
}
