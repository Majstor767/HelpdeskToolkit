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

Describe 'Split-UninstallString' {
    It 'takes a quoted file apart from its arguments' {
        $command = InModuleScope HelpdeskToolkit { Split-UninstallString -Text '"C:\Program Files\Contoso\unins000.exe" /SILENT /NORESTART' }
        $command.FilePath | Should -Be 'C:\Program Files\Contoso\unins000.exe'
        $command.Arguments | Should -Be '/SILENT /NORESTART'
    }

    It 'ends an unquoted file at the first .exe' {
        $command = InModuleScope HelpdeskToolkit { Split-UninstallString -Text 'C:\Program Files\Contoso\uninstall.exe /S' }
        $command.FilePath | Should -Be 'C:\Program Files\Contoso\uninstall.exe'
        $command.Arguments | Should -Be '/S'
    }

    It 'puts the folder in place of a variable' {
        $command = InModuleScope HelpdeskToolkit { Split-UninstallString -Text '"%WINDIR%\Contoso\remove.exe"' }
        $command.FilePath | Should -Be (Join-Path -Path $env:WINDIR -ChildPath 'Contoso\remove.exe')
        $command.Arguments | Should -Be ''
    }

    It 'returns nothing for <Name>' -ForEach @(
        @{ Name = 'no text'; Text = '' }
        @{ Name = 'spaces only'; Text = '   ' }
        @{ Name = 'a text that names no program'; Text = 'ask the administrator' }
    ) {
        InModuleScope HelpdeskToolkit -Parameters @{ Text = $Text } { Split-UninstallString -Text $Text } | Should -BeNullOrEmpty
    }
}

Describe 'Test-UninstallerMissing' {
    BeforeAll {
        $folder = Join-Path -Path $TestDrive -ChildPath 'Contoso App'
        [void](New-Item -Path $folder -ItemType Directory -Force)
        $present = Join-Path -Path $folder -ChildPath 'unins000.exe'
        Set-Content -LiteralPath $present -Value 'x'
        $gone = Join-Path -Path $folder -ChildPath 'deleted\unins000.exe'

        function Test-Missing {
            param($Program)
            InModuleScope HelpdeskToolkit -Parameters @{ Program = $Program } { Test-UninstallerMissing -Program $Program }
        }

        # A drive letter no drive has at the moment
        $used = [System.IO.DriveInfo]::GetDrives().Name
        $freeDrive = 'ZYXWVUTSRQPONMLKJIHGFED'.ToCharArray() | ForEach-Object { "${_}:\" } | Where-Object { $used -notcontains $_ } | Select-Object -First 1
    }

    It 'is true when the file that removes the program no longer exists' {
        Test-Missing (Get-TestProgram -UninstallString ('"{0}" /SILENT' -f $gone)) | Should -BeTrue
        Test-Missing (Get-TestProgram -UninstallString ('{0} /S' -f $gone)) | Should -BeTrue
    }

    It 'is false while the file is there' {
        Test-Missing (Get-TestProgram -UninstallString ('"{0}" /SILENT' -f $present)) | Should -BeFalse
    }

    It 'never reports a program of Windows Installer, which is removed through its product code' {
        Test-Missing (Get-TestProgram -ProductCode $productCode -UninstallString ('"{0}"' -f $gone)) | Should -BeFalse
        Test-Missing (Get-TestProgram -UninstallString ('MsiExec.exe /X{0}' -f $productCode)) | Should -BeFalse
    }

    It 'leaves <Name> alone' -ForEach @(
        @{ Name = 'a program without an uninstall command'; Text = '' }
        @{ Name = 'a bare program name, which Windows finds itself'; Text = 'rundll32.exe contoso.dll,Remove' }
        @{ Name = 'a network path, which may just not be reachable'; Text = '"\\fs01\apps\Contoso\remove.exe"' }
        @{ Name = 'a text that names no program'; Text = 'ask the administrator' }
    ) {
        Test-Missing (Get-TestProgram -UninstallString $Text) | Should -BeFalse
    }

    It 'does not call a program on a drive that is not connected a leftover' {
        if (-not $freeDrive) {
            Set-ItResult -Skipped -Because 'every drive letter is in use on this computer'
            return
        }
        Test-Missing (Get-TestProgram -UninstallString ('"{0}Games\Contoso\unins000.exe"' -f $freeDrive)) | Should -BeFalse
    }

    It 'is false for no program and for a program without the properties' {
        Test-Missing $null | Should -BeFalse
        Test-Missing ([PSCustomObject]@{ Name = 'Driver Pack'; Version = '' }) | Should -BeFalse
    }
}

Describe 'A click on a program: Open-WindowUninstall' -Skip:(-not $isSta) {
    BeforeAll {
        # Whatever a test forgets to say: nobody is asked and nothing is started.
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $false }
        Mock -ModuleName HelpdeskToolkit Start-Process { }
        Mock -ModuleName HelpdeskToolkit Invoke-DesktopShell { }
        Mock -ModuleName HelpdeskToolkit Invoke-CheckAction { $true }
        Mock -ModuleName HelpdeskToolkit Set-Clipboard { }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
        Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
            [PSCustomObject]@{ Name = 'Contoso Office'; Version = '16.0'; UninstallString = ''; ProductCode = '{11111111-2222-3333-4444-555555555555}'; Scope = 'Machine' }
            [PSCustomObject]@{ Name = 'Contoso Chat'; Version = '2.1'; UninstallString = 'RunDll32.EXE contoso,Uninstall'; ProductCode = ''; Scope = 'User' }
            [PSCustomObject]@{ Name = 'Contoso Store App'; Version = '1.0'; UninstallString = ''; ProductCode = ''; Scope = 'Machine' }
            # What is left of a program whose folder was deleted by hand
            [PSCustomObject]@{ Name = 'Contoso Old Game'; Version = '1.0'; UninstallString = ('"{0}" /S' -f (Join-Path -Path $TestDrive -ChildPath 'Old Game\unins000.exe')); ProductCode = ''; Scope = 'Machine' }
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
            $FilePath -like '*\System32\msiexec.exe' -and $ArgumentList -eq '/x {11111111-2222-3333-4444-555555555555}' -and
            # From the folder the uninstaller is in, as when Windows starts it
            $WorkingDirectory -like '*\System32'
        }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-DesktopShell -Times 0 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -Be 'The uninstaller of "Contoso Office" was started. Follow its window, and measure the drive again when it is done.'
    }

    It 'starts the uninstaller of a program of one user while the window has standard rights' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Chat' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'RunDll32.EXE' -and $ArgumentList -eq 'contoso,Uninstall' }
    }

    It 'hands the start to the desktop of the user when the window has administrator rights, as Windows would start it' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-DesktopShell -Times 1 -Exactly -Scope It -ParameterFilter {
            $FilePath -like '*\System32\msiexec.exe' -and $Arguments -eq '/x {11111111-2222-3333-4444-555555555555}' -and $WorkingDirectory -like '*\System32'
        }
        # Never by itself: what it starts would have administrator rights too.
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -BeLike 'The uninstaller of "Contoso Office" was started.*'
    }

    It 'starts the uninstaller of a program of one user the same way, so it never gets more rights than that user has' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Chat' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-DesktopShell -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -eq 'RunDll32.EXE' -and $Arguments -eq 'contoso,Uninstall' }
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
    }

    It 'starts nothing with administrator rights when the desktop cannot be reached, and opens Installed apps' {
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $true }
        Mock -ModuleName HelpdeskToolkit Invoke-DesktopShell { throw 'The desktop of the signed-in user was not found.' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -Scope It -ParameterFilter { $Check -eq 'Installed programs' }
        $gui.Controls.StatusText.Text | Should -BeLike 'The uninstaller of "Contoso Office" did not start. Installed apps is open.*'
    }

    It 'writes down what it started, and what did not start' {
        $log = InModuleScope HelpdeskToolkit { Get-AppDataPath -ChildPath 'app.log' }
        if (Test-Path -LiteralPath $log) {
            Remove-Item -LiteralPath $log -Force
        }
        Mock -ModuleName HelpdeskToolkit Confirm-WindowChoice { $true }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeTrue
        (Get-Content -LiteralPath $log) -join "`n" | Should -Match '\[Info\] The uninstaller of "Contoso Office" was started as the user: \S+msiexec\.exe /x \{11111111-'

        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'The system cannot find the file specified' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Office' } | Should -BeTrue
        (Get-Content -LiteralPath $log) -join "`n" | Should -Match '\[Error\] The uninstaller of "Contoso Office" did not start'
    }

    It 'says that a program whose uninstaller is gone cannot be uninstalled, and opens the place where Windows removes the entry' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Old Game' } | Should -BeTrue

        # Nothing to ask: there is nothing that could be started.
        Should -Invoke -ModuleName HelpdeskToolkit Confirm-WindowChoice -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Start-Process -Times 1 -Exactly -Scope It -ParameterFilter { $FilePath -like '*\System32\control.exe' -and $ArgumentList -eq 'appwiz.cpl' }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 0 -Exactly -Scope It
        Should -Invoke -ModuleName HelpdeskToolkit Set-Clipboard -Times 1 -Exactly -Scope It -ParameterFilter { $Value -eq 'Contoso Old Game' }
        $gui.Controls.StatusText.Text | Should -BeLike '"Contoso Old Game" cannot be uninstalled: its uninstaller no longer exists, only the entry in the list is left. "Programs and Features" is open;*'
    }

    It 'falls back to Installed apps when Programs and Features does not open' {
        Mock -ModuleName HelpdeskToolkit Start-Process { throw 'The system cannot find the file specified' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Open-WindowUninstall -Gui $Gui -Name 'Contoso Old Game' } | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-CheckAction -Times 1 -Exactly -Scope It
        $gui.Controls.StatusText.Text | Should -BeLike '"Contoso Old Game" cannot be uninstalled: its uninstaller no longer exists, only the entry in the list is left. Installed apps is open.*'
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
            '"{0}" cannot be uninstalled: its uninstaller no longer exists, only the entry in the list is left.',
            '"{0}" cannot be uninstalled: its uninstaller no longer exists, only the entry in the list is left. "Programs and Features" is open; choose the entry there and Uninstall, and Windows offers to remove it from the list.') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
    }
}
