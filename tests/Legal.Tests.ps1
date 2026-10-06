# Tests for what has to be true of the project before it is given to other people: the
# license comes with every copy, the notices exist and are linked, and the privacy page
# names every address the program contacts. They compare the documents with the code and
# the configuration, so the two cannot drift apart unnoticed.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    Import-TestModule

    $root = Join-Path -Path $PSScriptRoot -ChildPath '..'
    $moduleRoot = Join-Path -Path $root -ChildPath 'HelpdeskToolkit'

    function Get-TestText {
        param([string]$Name)
        [System.IO.File]::ReadAllText((Join-Path -Path $root -ChildPath $Name), [System.Text.Encoding]::UTF8)
    }
}

Describe 'The license' {
    It 'is the MIT License, with the author and the disclaimer of warranty' {
        $license = Get-TestText 'LICENSE'
        $license | Should -Match '^MIT License'
        $license | Should -Match 'Copyright \(c\) \d{4} Antonio Majstorovic'
        $license | Should -Match 'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND'
    }

    It 'is named by the manifest of the module' {
        $manifest = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'HelpdeskToolkit.psd1')
        $manifest.Copyright | Should -Match 'MIT License'
        $manifest.PrivateData.PSData.LicenseUri | Should -Match '/LICENSE$'
    }

    It 'is shown by the installer before anything is installed' {
        Get-TestText 'installer\HelpdeskToolkit.iss' | Should -Match '(?m)^LicenseFile=.*\\LICENSE\s*$'
    }

    It 'goes into every package together with the notices and the privacy page' {
        $build = Get-TestText 'tools\Build-Release.ps1'
        foreach ($file in 'LICENSE', 'NOTICE.md', 'PRIVACY.md') {
            $build | Should -Match ("'{0}'" -f [regex]::Escape($file)) -Because "$file has to reach whoever receives the program"
        }
    }
}

Describe 'The notices' {
    It 'has the file <_>' -ForEach 'NOTICE.md', 'PRIVACY.md', 'SECURITY.md', 'CONTRIBUTING.md', '.github\ISSUE_TEMPLATE\bug_report.md' {
        Join-Path -Path $root -ChildPath $_ | Should -Exist
    }

    It 'says that the project is not affiliated with Microsoft and whose the trademarks are' {
        $notice = Get-TestText 'NOTICE.md'
        $notice | Should -Match 'not made, endorsed, sponsored\s+or supported by Microsoft'
        $notice | Should -Match 'trademarks of the Microsoft\s+group\s+of\s+companies'
        $notice | Should -Match 'without warranty of any kind'
    }

    It 'tells people not to post reports of real computers' {
        Get-TestText 'CONTRIBUTING.md' | Should -Match 'Do not attach a report of a real computer'
        Get-TestText '.github\ISSUE_TEMPLATE\bug_report.md' | Should -Match 'do NOT attach a report of a real computer'
    }

    It 'says under which license a contribution is released' {
        Get-TestText 'CONTRIBUTING.md' | Should -Match 'your contribution is released under the same license'
    }

    It 'is linked from <_>, which also carries the short form' -ForEach 'README.md', 'README.hr.md' {
        $readme = Get-TestText $_
        foreach ($file in 'PRIVACY.md', 'NOTICE.md', 'SECURITY.md', 'CONTRIBUTING.md', 'LICENSE') {
            $readme | Should -Match ('\]\({0}\)' -f [regex]::Escape($file))
        }
        $readme | Should -Match 'Microsoft'
        $readme | Should -Match '-ComputerName'
    }
}

Describe 'The privacy page' {
    BeforeAll {
        $privacy = Get-TestText 'PRIVACY.md'
        $network = (Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Thresholds.psd1')).Network
    }

    It 'names every address the connectivity tests contact' {
        $privacy | Should -Match ([regex]::Escape([string]$network.PingTarget))
        $privacy | Should -Match ([regex]::Escape([string]$network.DnsTestName))
        $privacy | Should -Match ([regex]::Escape([string]$network.HttpsTestUrl))
    }

    It 'names the sites the links lead to, and they are the only ones the configuration knows' {
        $help = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Help.psd1')
        $addresses = @($help.SearchUrl, $help.ArticleUrl) + @(foreach ($entry in $help.Pages.Values) { if ($entry -is [hashtable]) { $entry.Values } else { $entry } })
        $hosts = @($addresses | ForEach-Object { ([uri]$_).Host } | Sort-Object -Unique)
        $hosts | Should -Be @('learn.microsoft.com', 'support.microsoft.com', 'www.bing.com')
        $privacy | Should -Match 'Microsoft Support'
        $privacy | Should -Match 'Microsoft Learn'
        $privacy | Should -Match 'Bing'
    }

    It 'names winget and the remote computer, the other two ways out of the computer' {
        $privacy | Should -Match 'winget upgrade'
        $privacy | Should -Match '-ComputerName'
    }

    It 'says where the program keeps its files' {
        foreach ($place in 'settings.json', 'History', 'Cache', 'app.log') {
            $privacy | Should -Match ([regex]::Escape($place))
        }
    }

    It 'covers every command of the module that contacts the network' {
        # Whoever adds a way out of the computer has to describe it on the privacy page
        # and then add the command here.
        $known = 'Invoke-WebRequest', 'Invoke-Command'
        $files = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private'), (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1'
        $found = foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
                ForEach-Object { $_.GetCommandName() } |
                Where-Object { $_ -match '^(Invoke-WebRequest|Invoke-RestMethod|Invoke-Command|New-PSSession|Enter-PSSession|Send-MailMessage|Start-BitsTransfer|Test-NetConnection|Test-Connection|Resolve-DnsName)$' }
        }
        @($found | Sort-Object -Unique) | Should -Be ($known | Sort-Object)
    }

    It 'has no .NET class that talks to the network in the module besides ping and the name lookup' {
        # WebUtility only encodes text and IPStatus is the answer of a ping; neither connects.
        $files = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private'), (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1'
        $classes = foreach ($file in $files) {
            [regex]::Matches([System.IO.File]::ReadAllText($file.FullName), 'System\.Net\.(?!ServicePointManager|SecurityProtocolType|WebUtility|NetworkInformation\.IPStatus)[A-Za-z.]+') | ForEach-Object { $_.Value }
        }
        @($classes | Sort-Object -Unique) | Should -Be @('System.Net.Dns', 'System.Net.NetworkInformation.Ping')
    }
}

Describe 'The About text of the window' -Skip:(-not $isSta) {
    It 'says what kind of software this is' {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowSetting -Gui $Gui }
        $gui.Controls.AboutText.Text | Should -Match '^HelpdeskToolkit \S+  \|  PowerShell '
        $gui.Controls.AboutText.Text | Should -Match 'MIT License, provided without warranty'
        $gui.Controls.AboutText.Text | Should -Match 'not affiliated with Microsoft'
    }

    It 'says it in Croatian too' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        $texts['Free software under the MIT License, provided without warranty. An independent project, not affiliated with Microsoft.'] | Should -Match 'bez jamstva'
    }
}
