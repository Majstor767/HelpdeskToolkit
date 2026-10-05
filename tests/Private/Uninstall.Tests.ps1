# Tests for removing a program from "What takes up the space": how the uninstaller of a
# program is found, and what a click on the program does. Nothing is ever started and
# nobody is asked: Start-Process and the question are replaced in every test.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $productCode = '{11111111-2222-3333-4444-555555555555}'

    function Get-TestCommand {
        param($Program)
        InModuleScope HelpdeskToolkit -Parameters @{ Program = $Program } { Get-UninstallCommand -Program $Program }
    }

    # A program as Get-InstalledProgram returns it.
    function Get-TestProgram {
        param([string]$Name = 'Contoso Office', [string]$UninstallString = '', [string]$ProductCode = '', [string]$Scope = 'Machine')
        [PSCustomObject]@{
            Name = $Name; Version = '16.0'; InstallDate = $null; SizeBytes = 3GB; Location = ''
            UninstallString = $UninstallString; ProductCode = $ProductCode; Scope = $Scope
        }
    }
}

Describe 'Get-InstalledProgram: how a program is removed' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-ItemProperty {
            [PSCustomObject]@{
                DisplayName = 'Contoso Office'; DisplayVersion = '16.0'; WindowsInstaller = 1; UninstallString = 'MsiExec.exe /I{11111111-2222-3333-4444-555555555555}'
                PSChildName = '{11111111-2222-3333-4444-555555555555}'; PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{11111111-2222-3333-4444-555555555555}'
            }
            [PSCustomObject]@{
                DisplayName = 'Contoso Chat'; DisplayVersion = '2.1'; UninstallString = '"C:\Users\m.horvat\AppData\Local\ContosoChat\Update.exe" --uninstall'
                PSChildName = 'ContosoChat'; PSPath = 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ContosoChat'
            }
            [PSCustomObject]@{ DisplayName = 'Contoso Viewer'; PSChildName = 'ContosoViewer' }
        }
        $programs = InModuleScope HelpdeskToolkit { Get-InstalledProgram }
    }

    It 'returns the product code of a program installed by Windows Installer' {
        ($programs | Where-Object Name -eq 'Contoso Office').ProductCode | Should -Be '{11111111-2222-3333-4444-555555555555}'
        ($programs | Where-Object Name -eq 'Contoso Chat').ProductCode | Should -Be ''
    }

    It 'returns the command the installer wrote down' {
        ($programs | Where-Object Name -eq 'Contoso Chat').UninstallString | Should -Be '"C:\Users\m.horvat\AppData\Local\ContosoChat\Update.exe" --uninstall'
        ($programs | Where-Object Name -eq 'Contoso Viewer').UninstallString | Should -Be ''
    }

    It 'tells a program of one user from a program installed for everybody' {
        ($programs | Where-Object Name -eq 'Contoso Office').Scope | Should -Be 'Machine'
        ($programs | Where-Object Name -eq 'Contoso Chat').Scope | Should -Be 'User'
        ($programs | Where-Object Name -eq 'Contoso Viewer').Scope | Should -Be 'Machine'
    }
}

Describe 'Get-UninstallCommand' {
    BeforeAll {
        $folder = Join-Path -Path $TestDrive -ChildPath 'Contoso App'
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        $uninstaller = Join-Path -Path $folder -ChildPath 'unins000.exe'
        [System.IO.File]::WriteAllBytes($uninstaller, (New-Object byte[] 10))
    }

    It 'removes a Windows Installer package with msiexec /x and its product code' {
        $command = Get-TestCommand -Program (Get-TestProgram -ProductCode $productCode -UninstallString "MsiExec.exe /I$productCode")
        $command.FilePath | Should -BeLike '*\System32\msiexec.exe'
        $command.Arguments | Should -Be "/x $productCode"
    }

    It 'reads the product code from the command when the entry does not say it is a package' {
        (Get-TestCommand -Program (Get-TestProgram -UninstallString "MsiExec.exe /X$productCode")).Arguments | Should -Be "/x $productCode"
        (Get-TestCommand -Program (Get-TestProgram -UninstallString "msiexec /i $productCode")).Arguments | Should -Be "/x $productCode"
    }

    It 'splits a quoted file from its arguments' {
        $command = Get-TestCommand -Program (Get-TestProgram -UninstallString ('"{0}" /allusers' -f $uninstaller))
        $command.FilePath | Should -Be $uninstaller
        $command.Arguments | Should -Be '/allusers'
    }

    It 'takes a quoted file without arguments' {
        $command = Get-TestCommand -Program (Get-TestProgram -UninstallString ('"{0}"' -f $uninstaller))
        $command.FilePath | Should -Be $uninstaller
        $command.Arguments | Should -Be ''
    }

    It 'takes everything up to .exe as the file when nothing is quoted, spaces in the folder included' {
        $command = Get-TestCommand -Program (Get-TestProgram -UninstallString ('{0} /S' -f $uninstaller))
        $command.FilePath | Should -Be $uninstaller
        $command.Arguments | Should -Be '/S'
    }

    It 'leaves a bare program name to Windows to find' {
        $command = Get-TestCommand -Program (Get-TestProgram -UninstallString 'RunDll32.EXE setupapi,InstallHinfSection DefaultUninstall 132 contoso.inf')
        $command.FilePath | Should -Be 'RunDll32.EXE'
        $command.Arguments | Should -Be 'setupapi,InstallHinfSection DefaultUninstall 132 contoso.inf'
    }

    It 'puts the folder in place of a variable such as %ProgramFiles%' {
        $previous = $env:HDT_TEST_FOLDER
        $env:HDT_TEST_FOLDER = $folder
        try {
            (Get-TestCommand -Program (Get-TestProgram -UninstallString '"%HDT_TEST_FOLDER%\unins000.exe"')).FilePath | Should -Be $uninstaller
        }
        finally {
            $env:HDT_TEST_FOLDER = $previous
        }
    }

    It 'returns nothing for <Name>' -ForEach @(
        @{ Name = 'an uninstaller that is no longer there'; Text = '"C:\No such folder\unins000.exe" /S' }
        @{ Name = 'a program without an uninstaller, like an app from the Store'; Text = '' }
        @{ Name = 'a text that is no command line'; Text = 'see the manual' }
    ) {
        Get-TestCommand -Program (Get-TestProgram -UninstallString $Text) | Should -BeNullOrEmpty
    }

    It 'returns nothing when there is no program' {
        Get-TestCommand -Program $null | Should -BeNullOrEmpty
    }
}

Describe 'A click on a program: Open-WindowUninstall' -Skip:(-not $isSta) {
    BeforeAll {
        # Whatever a test forgets to say: nobody is asked and nothing is started.
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $false }
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
            [PSCustomObject]@{ Name = 'Contoso Office'; Version = '16.0'; UninstallString = ''; ProductCode = '{11111111-2222-3333-4444-555555555555}'; Scope = 'Machine' }
            [PSCustomObject]@{ Name = 'Contoso Chat'; Version = '2.1'; UninstallString = 'RunDll32.EXE contoso,Uninstall'; ProductCode = ''; Scope = 'User' }
            [PSCustomObject]@{ Name = 'Contoso Store App'; Version = '1.0'; UninstallString = ''; ProductCode = ''; Scope = 'Machine' }
        }
    }

    BeforeEach {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
    }

    It 'asks first, naming the program' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Out-Null
        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 1 -Exactly -Scope It -ParameterFilter {
            $Title -eq 'Uninstall a program' -and $Text -like 'Start the uninstaller of "Contoso Office"?*'
        }
    }

    It 'starts nothing when the answer is No' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeFalse

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 0 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -Be 'Nothing was started.'
    }

    It 'starts the uninstaller of the program when the answer is Yes' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter {
            $FilePath -like '*\System32\msiexec.exe' -and $ArgumentList -eq '/x {11111111-2222-3333-4444-555555555555}'
        }
        $gui.Controls.StatusText.Text | Should -Be 'The uninstaller of "Contoso Office" was started. Follow its window, and measure the drive again when it is done.'
    }

    It 'starts the uninstaller of a program of one user while the window has standard rights' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Chat' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'RunDll32.EXE' -and $ArgumentList -eq 'contoso,Uninstall' }
    }

    It 'does not start what one user wrote into the registry with administrator rights, and opens Installed apps instead' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Chat' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -Scope It -ParameterFilter { $Check -eq 'Installed programs' }
        $gui.Controls.StatusText.Text | Should -BeLike '"Contoso Chat" is installed for one user only, so its uninstaller is not started with administrator rights. Installed apps is open.*'
    }

    It 'still starts the uninstaller of a program for everybody with administrator rights' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It
    }

    It 'opens Installed apps, with the name copied, for a program without an uninstaller' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Store App' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 1 -Exactly -Scope It -ParameterFilter { $Value -eq 'Contoso Store App' }
        $gui.Controls.StatusText.Text | Should -Be 'Installed apps is open. The name "Contoso Store App" was copied: paste it into the search field there (Ctrl+V), then choose Uninstall.'
    }

    It 'opens Installed apps for a program that is no longer in the list of Windows' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Gone' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -Scope It
    }

    It 'opens Installed apps and says so when the uninstaller does not start' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'The system cannot find the file specified' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -BeLike 'The uninstaller of "Contoso Office" did not start. Installed apps is open.*'
    }
}

Describe 'The texts of uninstalling' {
    It 'are translated into Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'Uninstall a program', 'Start the uninstaller of "{0}"?', 'Nothing was started.', 'The uninstaller of "{0}" did not start.',
            'The uninstaller of "{0}" was started. Follow its window, and measure the drive again when it is done.',
            'Click to uninstall this program: its own uninstaller starts after you confirm',
            '"{0}" is installed for one user only, so its uninstaller is not started with administrator rights.') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
    }
}
