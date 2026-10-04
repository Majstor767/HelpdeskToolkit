function Show-WindowSetting {
    <#
    .SYNOPSIS
        Fills the Settings page of the window.
    .DESCRIPTION
        Selects the current language, theme, start behaviour and interval of the
        automatic check in their lists, ticks the two options for running in the
        background, lists the keyboard shortcuts and shows the
        version and the folder in which the application keeps its own files.

        While the lists are set from code, $Gui.Loading is $true, so the handlers that
        react to a choice of the user do not mistake this for one.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls
    $settings = $Gui.Settings

    $select = {
        param($Box, [string]$Value)
        foreach ($item in $Box.Items) {
            if ([string]$item.Tag -eq $Value) {
                $Box.SelectedItem = $item
            }
        }
    }

    $Gui.Loading = $true
    try {
        & $select $controls.LanguageBox ([string]$settings.Language)
        & $select $controls.ThemeBox ([string]$settings.Theme)
        & $select $controls.AutoCheckBox ([string]$settings.AutoCheckMinutes)
        & $select $controls.StartupBox ([string]$settings.StartupElevation)
        $controls.BackgroundBox.IsChecked = $settings['KeepInBackground'] -eq $true
        # The shortcut in the Startup folder is the setting; it may have been removed in Windows.
        $controls.AutoStartBox.IsChecked = Test-AppAutoStart
    }
    finally {
        $Gui.Loading = $false
    }

    $controls.ShortcutItems.ItemsSource = @(
        [PSCustomObject]@{ Name = 'F5'; Text = Get-LocalizedText 'Run the check' }
        [PSCustomObject]@{ Name = 'Ctrl+F'; Text = Get-LocalizedText 'Search the results' }
        [PSCustomObject]@{ Name = 'Esc'; Text = Get-LocalizedText 'Clear the search' }
        [PSCustomObject]@{ Name = 'Ctrl+S'; Text = Get-LocalizedText 'Save the report as HTML, PDF, JSON or CSV' }
        [PSCustomObject]@{ Name = 'Ctrl+O'; Text = Get-LocalizedText 'Open the HTML report in the browser' }
        [PSCustomObject]@{ Name = 'Ctrl+Shift+C'; Text = Get-LocalizedText 'Copy the summary for a ticket' }
        [PSCustomObject]@{ Name = 'Ctrl+M'; Text = Get-LocalizedText 'Open the Live monitor' }
        [PSCustomObject]@{ Name = 'Ctrl+,'; Text = Get-LocalizedText 'Open the settings' }
        [PSCustomObject]@{ Name = 'Ctrl+T'; Text = Get-LocalizedText 'Switch between the light and the dark theme' }
        [PSCustomObject]@{ Name = 'PrtSc'; Text = Get-LocalizedText 'Copy a picture of the window' }
    )

    $controls.AboutText.Text = (Get-LocalizedText 'HelpdeskToolkit {0}  |  PowerShell {1}') -f (Get-ToolVersion), $PSVersionTable.PSVersion
    $controls.DataFolderText.Text = Get-AppDataPath
}
