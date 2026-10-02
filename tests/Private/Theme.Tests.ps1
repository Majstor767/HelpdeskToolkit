# Tests for switching between the light and the dark theme while the window is open.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'

    function New-TestWindow {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param([string]$Theme = 'Light')

        $gui = InModuleScope HelpdeskToolkit -Parameters @{ Theme = $Theme } { New-HealthCheckWindow -Theme $Theme }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }

    function Get-TestColor {
        param($Gui, [string]$Brush)
        [string]$Gui.Window.FindResource($Brush).Color
    }

    function Switch-TestTheme {
        param($Gui, [string]$Setting = '')
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui; Setting = $Setting } { Switch-WindowTheme -Gui $Gui -Setting $Setting }
    }
}

Describe 'The window layout and the themes' {
    BeforeAll {
        $layout = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml'))
    }

    It 'looks every brush up dynamically, so a brush can be replaced while the window is open' {
        [regex]::Matches($layout, '\{StaticResource \w+Brush\}').Count | Should -Be 0
        $layout | Should -Not -Match '<StaticResource ResourceKey="\w+Brush"'
        [regex]::Matches($layout, '\{DynamicResource \w+Brush\}').Count | Should -BeGreaterThan 200
    }

    It 'never asks the window for a brush in the code, which would keep the color of the old theme' {
        $files = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private'), (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1'
        $files | Select-String -Pattern 'FindResource\(' | ForEach-Object { '{0}:{1}' -f $_.Filename, $_.LineNumber } | Should -BeNullOrEmpty
    }
}

Describe 'Set-WindowTheme' -Skip:(-not $isSta) {
    It 'keeps the colors of both themes for every brush of the layout' {
        $gui = New-TestWindow
        $gui.Palette.Light.Count | Should -BeGreaterThan 30
        $gui.Palette.Dark.Count | Should -Be $gui.Palette.Light.Count
        $gui.Palette.Light.SurfaceBrush | Should -Be '#FFFFFF'
        $gui.Palette.Dark.SurfaceBrush | Should -Be '#1A212B'
        # A brush the dark theme does not list has the same color in both.
        $gui.Palette.Dark.PrimaryBrush | Should -Be $gui.Palette.Light.PrimaryBrush
    }

    It 'keeps the light colors in the palette of a window that was built dark' {
        $gui = New-TestWindow -Theme Dark
        $gui.Palette.Light.SurfaceBrush | Should -Be '#FFFFFF'
        Get-TestColor -Gui $gui -Brush 'SurfaceBrush' | Should -Be '#FF1A212B'
    }

    It 'gives the open window the dark colors, and the light ones again' {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Set-WindowTheme -Gui $Gui -Theme Dark }

        $gui.Theme | Should -Be 'Dark'
        Get-TestColor -Gui $gui -Brush 'SurfaceBrush' | Should -Be '#FF1A212B'
        Get-TestColor -Gui $gui -Brush 'TextBrush' | Should -Be '#FFE6EBF2'
        Get-TestColor -Gui $gui -Brush 'WindowBrush' | Should -Be '#FF0F141B'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Set-WindowTheme -Gui $Gui -Theme Light }
        $gui.Theme | Should -Be 'Light'
        Get-TestColor -Gui $gui -Brush 'SurfaceBrush' | Should -Be '#FFFFFFFF'
        Get-TestColor -Gui $gui -Brush 'WindowBrush' | Should -Be '#FFF3F5F8'
    }

    It 'recolors the window itself and what the layout draws' {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Set-WindowTheme -Gui $Gui -Theme Dark }

        [string]$gui.Window.Background.Color | Should -Be '#FF0F141B'
        [string]$gui.Controls.PageTitle.Foreground.Color | Should -Be '#FFE6EBF2'
        [string]$gui.Controls.RunPanel.Background.Color | Should -Be '#FF1A212B'
    }

    It 'recolors what the code has colored: the verdict, the score and the status dots' {
        $gui = New-TestWindow
        $report = New-TestReport -Result @(New-TestResult -Category 'Hardware' -Check 'Disk (C:)' -Status Critical -Value '2 % free')
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Report = $report } {
            Mock Enable-WindowMonitor { }
            Mock Disable-WindowMonitor { }
            Show-WindowReport -Gui $Gui -Report $Report
        }
        # Light theme: the red of a critical verdict
        [string]$gui.Controls.VerdictText.Foreground.Color | Should -Be '#FFB3261E'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Set-WindowTheme -Gui $Gui -Theme Dark }
        [string]$gui.Controls.VerdictText.Foreground.Color | Should -Be '#FFFF6B61'
        [string]$gui.Controls.VerdictBorder.Background.Color | Should -Be '#FF3D1A18'
        [string]$gui.Controls.ScoreBorder.BorderBrush.Color | Should -Be '#FFF0B429'
        [string]$gui.Controls.MonitorCpuDot.Fill.Color | Should -Be '#FF4A5666'
    }

    It 'puts the switch of the header on the side of the theme that is on' {
        $gui = New-TestWindow
        $gui.Controls.ThemeToggle.IsChecked | Should -BeFalse
        $gui.Controls.ThemeToggle.ToolTip | Should -Be 'Switch to the dark theme (Ctrl+T)'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Set-WindowTheme -Gui $Gui -Theme Dark }
        $gui.Controls.ThemeToggle.IsChecked | Should -BeTrue
        $gui.Controls.ThemeToggle.ToolTip | Should -Be 'Switch to the light theme (Ctrl+T)'
    }

    It 'starts with the switch on the dark side in a window that was built dark' {
        $gui = New-TestWindow -Theme Dark
        $gui.Controls.ThemeToggle.IsChecked | Should -BeTrue
        $gui.Controls.ThemeToggle.ToolTip | Should -Be 'Switch to the light theme (Ctrl+T)'
    }
}

Describe 'Switch-WindowTheme' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Save-AppSetting { }
    }

    It 'turns the theme over, remembers that choice and saves it' {
        $gui = New-TestWindow
        Switch-TestTheme -Gui $gui | Should -Be 'Dark'

        $gui.Theme | Should -Be 'Dark'
        $gui.Settings.Theme | Should -Be 'Dark'
        Get-TestColor -Gui $gui -Brush 'SurfaceBrush' | Should -Be '#FF1A212B'
        Should -Invoke -ModuleName HelpdeskToolkit Save-AppSetting -Times 1 -Exactly -ParameterFilter { $Setting.Theme -eq 'Dark' }

        Switch-TestTheme -Gui $gui | Should -Be 'Light'
        $gui.Settings.Theme | Should -Be 'Light'
        Get-TestColor -Gui $gui -Brush 'SurfaceBrush' | Should -Be '#FFFFFFFF'
    }

    It 'applies the theme that was chosen in the settings' {
        $gui = New-TestWindow
        Switch-TestTheme -Gui $gui -Setting 'Dark' | Should -Be 'Dark'
        # Choosing the same again changes nothing.
        Switch-TestTheme -Gui $gui -Setting 'Dark' | Should -Be 'Dark'
        $gui.Theme | Should -Be 'Dark'
    }

    It 'follows Windows with "Same as Windows", and stores that choice, not the theme' {
        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { 0 }
        $gui = New-TestWindow
        Switch-TestTheme -Gui $gui -Setting 'System' | Should -Be 'Dark'
        $gui.Settings.Theme | Should -Be 'System'
        $gui.Theme | Should -Be 'Dark'

        Mock -ModuleName HelpdeskToolkit Get-RegistryValue { 1 }
        Switch-TestTheme -Gui $gui -Setting 'System' | Should -Be 'Light'
    }

    It 'sets the theme list of the Settings page to the choice, without reacting to that itself' {
        $gui = New-TestWindow
        Switch-TestTheme -Gui $gui | Out-Null
        $gui.Controls.ThemeBox.SelectedItem.Tag | Should -Be 'Dark'
        $gui.Loading | Should -BeFalse
        # Saved once, by the switch; the list did not trigger a second change.
        Should -Invoke -ModuleName HelpdeskToolkit Save-AppSetting -Times 1 -Exactly
    }

    It 'is what Ctrl+T does' {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'T' -Control } | Should -BeTrue
        $gui.Theme | Should -Be 'Dark'
        # The key alone is an ordinary letter.
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'T' } | Should -BeFalse
        $gui.Theme | Should -Be 'Dark'
    }

    It 'is listed among the keyboard shortcuts of the Settings page' {
        $gui = New-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowSetting -Gui $Gui }
        $shortcut = @($gui.Controls.ShortcutItems.ItemsSource) | Where-Object Name -eq 'Ctrl+T'
        $shortcut.Text | Should -Be 'Switch between the light and the dark theme'
    }
}
