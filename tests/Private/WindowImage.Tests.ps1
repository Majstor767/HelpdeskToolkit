# Tests for the Print Screen key: a picture of the window on the clipboard. The clipboard
# itself is always replaced by a mock, so the tests leave the real one alone.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'

    # A window that was never shown has no size. This gives its content one, the way
    # Windows does when the window appears.
    function Get-TestWindow {
        param([int]$Width = 800, [int]$Height = 600)

        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        if ($Width -gt 0) {
            $size = New-Object -TypeName System.Windows.Size -ArgumentList $Width, $Height
            $gui.Window.Content.Measure($size)
            $gui.Window.Content.Arrange((New-Object -TypeName System.Windows.Rect -ArgumentList 0, 0, $Width, $Height))
        }
        $gui
    }
}

Describe 'Get-WindowImage' -Skip:(-not $isSta) {
    It 'returns a picture as large as the content of the window' {
        $gui = Get-TestWindow -Width 800 -Height 600
        $image = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Get-WindowImage -Gui $Gui }

        $image | Should -BeOfType [System.Windows.Media.Imaging.BitmapSource]
        $image.PixelWidth | Should -Be 800
        $image.PixelHeight | Should -Be 600
        $image.IsFrozen | Should -BeTrue
    }

    It 'draws the background of the window, so the picture is not transparent' {
        $gui = Get-TestWindow -Width 400 -Height 300
        $image = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Get-WindowImage -Gui $Gui }

        # Blue, green, red and opacity of every pixel
        $pixels = New-Object -TypeName 'byte[]' -ArgumentList (400 * 300 * 4)
        $image.CopyPixels($pixels, 400 * 4, 0)
        $transparent = 0
        for ($index = 3; $index -lt $pixels.Length; $index += 4) {
            if ($pixels[$index] -ne 255) { $transparent++ }
        }
        $transparent | Should -Be 0
    }

    It 'shows the window as it is when something is drawn outside of it, instead of squeezing everything into the picture' {
        $gui = Get-TestWindow -Width 400 -Height 300
        $arrange = {
            $gui.Window.Content.Measure((New-Object -TypeName System.Windows.Size -ArgumentList 400, 300))
            $gui.Window.Content.Arrange((New-Object -TypeName System.Windows.Rect -ArgumentList 0, 0, 400, 300))
            $gui.Window.Content.UpdateLayout()
        }
        # The size of the picture, then blue, green, red and opacity of every pixel
        $read = {
            $image = InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Get-WindowImage -Gui $Gui }
            $pixels = New-Object -TypeName 'byte[]' -ArgumentList ($image.PixelWidth * $image.PixelHeight * 4)
            $image.CopyPixels($pixels, $image.PixelWidth * 4, 0)
            , @($image.PixelWidth, $image.PixelHeight, $pixels)
        }
        # Drawing a window for the first time settles its layout; compare what comes after.
        [void](& $read)
        & $arrange
        $before = & $read

        # Like a graph that reaches past its frame: a shape far below the content,
        # which the window itself would cut off.
        $canvas = New-Object -TypeName System.Windows.Controls.Canvas
        $shape = New-Object -TypeName System.Windows.Shapes.Rectangle
        $shape.Width = 50
        $shape.Height = 50
        $shape.Fill = [System.Windows.Media.Brushes]::Red
        [System.Windows.Controls.Canvas]::SetTop($shape, 700)
        [void]$canvas.Children.Add($shape)
        [void]$gui.Window.Content.Children.Add($canvas)
        & $arrange

        $after = & $read
        $after[0] | Should -Be $before[0]
        $after[1] | Should -Be $before[1]
        [System.Linq.Enumerable]::SequenceEqual([byte[]]$before[2], [byte[]]$after[2]) | Should -BeTrue
    }

    It 'returns nothing while the window has no size yet' {
        $gui = Get-TestWindow -Width 0
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Get-WindowImage -Gui $Gui } | Should -BeNullOrEmpty
    }
}

Describe 'Copy-WindowImage' -Skip:(-not $isSta) {
    It 'puts the picture on the clipboard and says so' {
        Mock -ModuleName HelpdeskToolkit Set-ClipboardImage { }
        $gui = Get-TestWindow

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Copy-WindowImage -Gui $Gui } | Should -BeTrue

        $gui.Controls.StatusText.Text | Should -Be 'A picture of the window was copied. Paste it with Ctrl+V.'
        Should -Invoke -ModuleName HelpdeskToolkit Set-ClipboardImage -Times 1 -Exactly -ParameterFilter { $Image.PixelWidth -eq 800 -and $Image.PixelHeight -eq 600 }
    }

    It 'reports a clipboard that is in use instead of failing' {
        Mock -ModuleName HelpdeskToolkit Set-ClipboardImage { throw 'The clipboard is in use' }
        $gui = Get-TestWindow

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Copy-WindowImage -Gui $Gui } | Should -BeFalse
        $gui.Controls.StatusText.Text | Should -Be 'The picture of the window could not be copied: The clipboard is in use'
    }

    It 'does nothing while there is no picture to copy' {
        Mock -ModuleName HelpdeskToolkit Set-ClipboardImage { }
        $gui = Get-TestWindow -Width 0

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Copy-WindowImage -Gui $Gui } | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Set-ClipboardImage -Times 0 -Exactly
    }
}

Describe 'The Print Screen key' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Set-ClipboardImage { }
    }

    It 'copies the picture of the window' {
        $gui = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Snapshot' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Set-ClipboardImage -Times 1 -Exactly -Scope It
    }

    It 'also works while the question at the start is open' {
        $gui = Get-TestWindow
        $gui.Controls.StartupOverlay.Visibility = [System.Windows.Visibility]::Visible
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowShortcut -Gui $Gui -Key 'Snapshot' } | Should -BeTrue
        Should -Invoke -ModuleName HelpdeskToolkit Set-ClipboardImage -Times 1 -Exactly -Scope It
    }

    It 'is listened for when the key is released, because Windows does not report it being pressed' {
        $source = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Public\Show-PCHealthCheck.ps1'))
        $source | Should -Match 'Add_PreviewKeyUp'
        $source | Should -Match '\[System\.Windows\.Input\.Key\]::Snapshot'
    }

    It 'is listed among the keyboard shortcuts of the Settings page' {
        $gui = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowSetting -Gui $Gui }
        $shortcut = @($gui.Controls.ShortcutItems.ItemsSource) | Where-Object Name -eq 'PrtSc'
        $shortcut.Text | Should -Be 'Copy a picture of the window'
    }

    It 'has its texts in Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'Copy a picture of the window', 'A picture of the window was copied. Paste it with Ctrl+V.', 'The picture of the window could not be copied: {0}') {
            $texts[$text] | Should -Not -BeNullOrEmpty
        }
    }
}
