function Set-WindowTheme {
    <#
    .SYNOPSIS
        Gives the open window the colors of the light or of the dark theme, at once.
    .DESCRIPTION
        Every color of the window is a named brush in the resources of the window, and
        the layout looks the brushes up dynamically ("DynamicResource"). Putting a
        brush with another color under the same name therefore recolors everything
        that uses it, without building the window again.

        The brushes themselves cannot simply be given a new color: WPF locks
        ("freezes") a brush once a style uses it, so each one is replaced.

        The colors of both themes are kept in $Gui.Palette, which New-HealthCheckWindow
        fills from the layout (light) and from Assets\DarkTheme.psd1 (dark).

        Only the window changes. Storing the choice is done by Switch-WindowTheme.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only changes the colors of the application window; no system state is changed.')]
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [ValidateSet('Light', 'Dark')]
        [string]$Theme
    )

    $palette = $Gui.Palette[$Theme]
    foreach ($key in @($palette.Keys)) {
        $brush = New-Object -TypeName System.Windows.Media.SolidColorBrush -ArgumentList ([System.Windows.Media.ColorConverter]::ConvertFromString($palette[$key]))
        $brush.Freeze()
        # The plain .NET object: wrapped by PowerShell, WPF would not accept it as a brush.
        $Gui.Window.Resources[$key] = $brush.PSObject.BaseObject
    }
    $Gui.Theme = $Theme

    # The switch in the header shows the theme that is on.
    $toggle = $Gui.Controls.ThemeToggle
    $toggle.IsChecked = $Theme -eq 'Dark'
    $toggle.ToolTip = if ($Theme -eq 'Dark') {
        Get-LocalizedText 'Switch to the light theme (Ctrl+T)'
    }
    else {
        Get-LocalizedText 'Switch to the dark theme (Ctrl+T)'
    }
}
