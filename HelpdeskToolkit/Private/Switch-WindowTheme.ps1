function Switch-WindowTheme {
    <#
    .SYNOPSIS
        Changes the theme of the window as the user asked for it, and remembers the choice.
    .DESCRIPTION
        Called by the switch in the header (and its shortcut Ctrl+T) and by the theme
        list of the Settings page.

        - Without -Setting the theme is turned over: light becomes dark and dark
          becomes light. The setting then names that theme, so the next start uses it
          whatever Windows is set to.
        - With -Setting the given choice is applied: "Light", "Dark", or "System",
          which follows the app mode of Windows (see Get-WindowTheme).

        The window is recolored at once (Set-WindowTheme), the setting is saved, and
        the theme list of the Settings page is set to the same choice.

        Returns the theme that is on now.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [ValidateSet('', 'System', 'Light', 'Dark')]
        [string]$Setting = ''
    )

    if (-not $Setting) {
        $Setting = if ($Gui.Theme -eq 'Dark') { 'Light' } else { 'Dark' }
    }

    $theme = Get-WindowTheme -Setting $Setting
    Set-WindowTheme -Gui $Gui -Theme $theme

    $Gui.Settings.Theme = $Setting
    [void](Save-AppSetting -Setting $Gui.Settings)

    # The list of the Settings page follows; its handler must not answer to that.
    $wasLoading = $Gui.Loading
    $Gui.Loading = $true
    try {
        foreach ($item in $Gui.Controls.ThemeBox.Items) {
            if ([string]$item.Tag -eq $Setting) {
                $Gui.Controls.ThemeBox.SelectedItem = $item
            }
        }
    }
    finally {
        $Gui.Loading = $wasLoading
    }

    $theme
}
