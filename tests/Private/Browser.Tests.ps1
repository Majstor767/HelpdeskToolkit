# Tests for finding the default browser, noticing that it is gone, and opening a web
# address all the same. Nothing is ever opened: Start-Process and the way through the
# desktop are replaced in every test.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'

    # Program files that exist, and one that does not
    $folder = Join-Path -Path $TestDrive -ChildPath 'Browsers'
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
    $contoso = Join-Path -Path $folder -ChildPath 'contoso.exe'
    $fabrikam = Join-Path -Path $folder -ChildPath 'fabrikam.exe'
    $edge = Join-Path -Path $folder -ChildPath 'msedge.exe'
    foreach ($file in $contoso, $fabrikam, $edge) {
        [System.IO.File]::WriteAllBytes($file, (New-Object byte[] 10))
    }
    $gone = Join-Path -Path $folder -ChildPath 'removed.exe'

    # Says which program file every ProgId leads to.
    $script:paths = @{ ContosoHTML = $contoso; FabrikamHTML = $fabrikam; RemovedHTML = $gone }
}

Describe 'Get-ProgramIdPath' {
    It 'takes the program from a command line in quotes' {
        Mock -ModuleName HelpdeskToolkit Get-Item {
            $key = [PSCustomObject]@{}
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { '"C:\Program Files\Contoso\browser.exe" --single-argument %1' }
            $key
        }
        InModuleScope HelpdeskToolkit { Get-ProgramIdPath -ProgId 'ContosoHTML' } | Should -Be 'C:\Program Files\Contoso\browser.exe'
    }

    It 'takes the program from a command line without quotes' {
        Mock -ModuleName HelpdeskToolkit Get-Item {
            $key = [PSCustomObject]@{}
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { 'C:\Contoso\browser.exe -url %1' }
            $key
        }
        InModuleScope HelpdeskToolkit { Get-ProgramIdPath -ProgId 'ContosoHTML' } | Should -Be 'C:\Contoso\browser.exe'
    }

    It 'looks at the registration of the user first and then at the one for everybody' {
        Mock -ModuleName HelpdeskToolkit Get-Item { throw 'Key not found' } -ParameterFilter { $LiteralPath -like 'HKCU:*' }
        Mock -ModuleName HelpdeskToolkit Get-Item {
            $key = [PSCustomObject]@{}
            $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value { '"C:\Everybody\browser.exe" %1' }
            $key
        } -ParameterFilter { $LiteralPath -like 'HKLM:*' }

        InModuleScope HelpdeskToolkit { Get-ProgramIdPath -ProgId 'ContosoHTML' } | Should -Be 'C:\Everybody\browser.exe'
        Should -Invoke -ModuleName HelpdeskToolkit Get-Item -Times 1 -Exactly -Scope It -ParameterFilter { $LiteralPath -eq 'HKCU:\Software\Classes\ContosoHTML\shell\open\command' }
    }

    It 'returns an empty text for a ProgId that is not registered, and for none' {
        Mock -ModuleName HelpdeskToolkit Get-Item { throw 'Key not found' }
        InModuleScope HelpdeskToolkit { Get-ProgramIdPath -ProgId 'NoSuchHTML' } | Should -Be ''
        InModuleScope HelpdeskToolkit { Get-ProgramIdPath -ProgId '' } | Should -Be ''
    }
}

Describe 'Get-DefaultBrowser' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-ProgramIdPath { [string]$script:paths[$ProgId] }
        Mock -ModuleName HelpdeskToolkit Get-InstalledBrowserPath { $edge }
    }

    It 'follows the choice of the user to a browser that exists' {
        Mock -ModuleName HelpdeskToolkit Get-BrowserAssociation { [PSCustomObject]@{ Latest = ''; Chosen = 'ContosoHTML' } }
        $browser = InModuleScope HelpdeskToolkit { Get-DefaultBrowser }

        $browser.ProgId | Should -Be 'ContosoHTML'
        $browser.Path | Should -Be $contoso
        $browser.Exists | Should -BeTrue
        $browser.IsBroken | Should -BeFalse
        $browser.Usable | Should -Be $contoso
    }

    It 'lets the newer setting of Windows count when both are there' {
        Mock -ModuleName HelpdeskToolkit Get-BrowserAssociation { [PSCustomObject]@{ Latest = 'FabrikamHTML'; Chosen = 'ContosoHTML' } }
        $browser = InModuleScope HelpdeskToolkit { Get-DefaultBrowser }
        $browser.ProgId | Should -Be 'FabrikamHTML'
        $browser.Usable | Should -Be $fabrikam
    }

    It 'notices a default browser whose program is gone, and falls back to the one the older setting names' {
        Mock -ModuleName HelpdeskToolkit Get-BrowserAssociation { [PSCustomObject]@{ Latest = 'RemovedHTML'; Chosen = 'ContosoHTML' } }
        $browser = InModuleScope HelpdeskToolkit { Get-DefaultBrowser }

        $browser.ProgId | Should -Be 'RemovedHTML'
        $browser.Path | Should -Be $gone
        $browser.Exists | Should -BeFalse
        $browser.IsBroken | Should -BeTrue
        $browser.Usable | Should -Be $contoso
    }

    It 'falls back to an installed browser when the older setting leads nowhere either' {
        Mock -ModuleName HelpdeskToolkit Get-BrowserAssociation { [PSCustomObject]@{ Latest = ''; Chosen = 'RemovedHTML' } }
        $browser = InModuleScope HelpdeskToolkit { Get-DefaultBrowser }
        $browser.IsBroken | Should -BeTrue
        $browser.Usable | Should -Be $edge
    }

    It 'is not broken, only unset, when no browser was ever chosen' {
        Mock -ModuleName HelpdeskToolkit Get-BrowserAssociation { [PSCustomObject]@{ Latest = ''; Chosen = '' } }
        $browser = InModuleScope HelpdeskToolkit { Get-DefaultBrowser }
        $browser.ProgId | Should -Be ''
        $browser.Exists | Should -BeFalse
        $browser.IsBroken | Should -BeFalse
        $browser.Usable | Should -Be $edge
    }

    It 'has nothing to use when no browser is found at all' {
        Mock -ModuleName HelpdeskToolkit Get-BrowserAssociation { [PSCustomObject]@{ Latest = 'RemovedHTML'; Chosen = '' } }
        Mock -ModuleName HelpdeskToolkit Get-InstalledBrowserPath { }
        (InModuleScope HelpdeskToolkit { Get-DefaultBrowser }).Usable | Should -Be ''
    }
}

Describe 'Get-DefaultBrowserPath' {
    It 'returns the browser to open things with' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'RemovedHTML'; Path = 'C:\Gone\browser.exe'; Exists = $false; IsBroken = $true; Usable = 'C:\Contoso\browser.exe' } }
        InModuleScope HelpdeskToolkit { Get-DefaultBrowserPath } | Should -Be 'C:\Contoso\browser.exe'
    }

    It 'returns nothing when there is no browser' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = ''; Path = ''; Exists = $false; IsBroken = $false; Usable = '' } }
        InModuleScope HelpdeskToolkit { Get-DefaultBrowserPath } | Should -BeNullOrEmpty
    }
}

Describe 'Open-WebAddress' {
    BeforeAll {
        $url = 'https://www.example.test/search?q=Windows%20event%20ID%2010016'
        # Whatever a test forgets to say: nothing is opened.
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        Mock -ModuleName HelpdeskToolkit Invoke-DesktopShell { }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'ContosoHTML'; Path = 'C:\Contoso\browser.exe'; Exists = $true; IsBroken = $false; Usable = 'C:\Contoso\browser.exe' } }

        function Open-TestAddress {
            param([string]$Address = $url)
            InModuleScope HelpdeskToolkit -Parameters @{ Address = $Address } { Open-WebAddress -Url $Address }
        }
    }

    It 'hands the address to Windows when the default browser exists' {
        Open-TestAddress | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq $url }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-DesktopShell -Times 0 -Exactly -Scope It
    }

    It 'gives the address to a browser that exists when the default browser is gone' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'RemovedHTML'; Path = 'C:\Gone\browser.exe'; Exists = $false; IsBroken = $true; Usable = 'C:\Other\browser.exe' } }
        Open-TestAddress | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'C:\Other\browser.exe' -and $ArgumentList -eq ('"{0}"' -f $url) }
        # Windows is not asked: it would answer "Application not found".
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It -ParameterFilter { $FilePath -eq $url }
    }

    It 'falls back to the browser itself when Windows fails to open the address' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'Application not found' } -ParameterFilter { $FilePath -like 'https://*' }
        Open-TestAddress | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'C:\Contoso\browser.exe' }
    }

    It 'goes through the desktop of the user from a window with administrator rights, so the browser does not get them' {
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        Open-TestAddress | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-DesktopShell -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq $url }
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
    }

    It 'starts the other browser through the desktop too, with the address as its argument' {
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'RemovedHTML'; Path = 'C:\Gone\browser.exe'; Exists = $false; IsBroken = $true; Usable = 'C:\Other\browser.exe' } }
        Open-TestAddress | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-DesktopShell -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'C:\Other\browser.exe' -and $Arguments -eq ('"{0}"' -f $url) }
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
    }

    It 'starts it directly when the desktop cannot be reached' {
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        Mock -ModuleName HelpdeskToolkit Invoke-DesktopShell { throw 'The desktop of the signed-in user was not found.' }
        Open-TestAddress | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq $url }
    }

    It 'still asks Windows when no browser is known at all' {
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = ''; Path = ''; Exists = $false; IsBroken = $false; Usable = '' } }
        Open-TestAddress | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq $url }
    }

    It 'throws the error of Windows when no way works' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'Application not found' }
        { Open-TestAddress } | Should -Throw '*Application not found*'
    }

    It 'opens nothing that is not a plain https address: <_>' -ForEach @(
        'http://example.test/page', 'file:///C:/Windows/System32/calc.exe', 'C:\Windows\System32\calc.exe', 'https://example.test/a b', 'https://example.test/"x', ''
    ) {
        Open-TestAddress -Address $_ | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-DesktopShell -Times 0 -Exactly -Scope It
    }
}

Describe 'Get-SoftwareHealth: a default browser that is gone' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-InstalledProgram { }
        Mock -ModuleName HelpdeskToolkit Get-UnsupportedProgram { }
        Mock -ModuleName HelpdeskToolkit Get-ProgramUpdate { [PSCustomObject]@{ Available = $false; Updates = @(); Error = '' } }
        Mock -ModuleName HelpdeskToolkit Get-OfficeInstallation { }
        Mock -ModuleName HelpdeskToolkit Get-OutlookDataFile { }
        Mock -ModuleName HelpdeskToolkit Get-WinEvent { }
        Mock -ModuleName HelpdeskToolkit Get-BrowserExtension { }
        Mock -ModuleName HelpdeskToolkit Get-DefaultBrowser { [PSCustomObject]@{ ProgId = 'RemovedHTML'; Path = 'C:\Gone\browser.exe'; Exists = $false; IsBroken = $true; Usable = 'C:\Other\browser.exe' } }
        $result = Get-SoftwareHealth -SkipUpdateCheck | Where-Object Check -eq 'Default browser'
    }

    It 'is a warning that names what Windows still points to' {
        $result.Status | Should -Be 'Warning'
        $result.Value | Should -Be 'Set to a program that is no longer installed (RemovedHTML)'
    }

    It 'says what happens and where it is fixed' {
        $result.Recommendation | Should -Match 'Application not found'
        $result.Recommendation | Should -Match 'Settings > Apps > Default apps'
    }

    It 'has a button for the page of Windows, a reason and Croatian texts' {
        (InModuleScope HelpdeskToolkit { Get-CheckAction -Check 'Default browser' -Category 'Software' }).Target | Should -Be 'ms-settings:defaultapps'
        InModuleScope HelpdeskToolkit { Get-CheckRisk -Check 'Default browser' -Category 'Software' } | Should -Match 'Links in e-mails'

        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        $texts['Set to a program that is no longer installed ({0})'] | Should -Not -BeNullOrEmpty
        $texts[$result.Recommendation] | Should -Not -BeNullOrEmpty
        $texts['The page was opened in another browser: the default browser of Windows is no longer installed. Choose one under Settings > Apps > Default apps.'] | Should -Not -BeNullOrEmpty
    }
}
