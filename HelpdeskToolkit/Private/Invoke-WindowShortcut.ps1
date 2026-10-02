function Invoke-WindowShortcut {
    <#
    .SYNOPSIS
        Carries out the keyboard shortcut that belongs to a key, if there is one.
    .DESCRIPTION
        Called for every key that is pressed in the window. The shortcuts:

        F5            run the check
        Ctrl+F        go to the search field (on the Overview when the open page has none)
        Esc           clear the search; on the detail page of a component, go back to
                      the Live monitor
        Ctrl+S        save the report ("Save as...")
        Ctrl+O        open the HTML report in the browser
        Ctrl+Shift+C  copy the summary
        Ctrl+M        open the Live monitor
        Ctrl+,        open the settings

        A shortcut does what the button with the same purpose does, by "clicking" that
        button, and does nothing while the button is disabled.

        Returns $true when the key was a shortcut, so the caller can stop Windows from
        handling the key a second time.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Name of the key, for example "F5" or "S".
        [Parameter(Mandatory)]
        [string]$Key,

        [switch]$Control,

        [switch]$Shift
    )

    $controls = $Gui.Controls

    # Raises the Click event of a button, exactly as a mouse click would.
    $click = {
        param($Button)
        if ($Button.IsEnabled -and $Button.Visibility -eq [System.Windows.Visibility]::Visible) {
            $Button.RaiseEvent((New-Object -TypeName System.Windows.RoutedEventArgs -ArgumentList ([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
        }
    }

    # Selects a page of the list by its name.
    $open = {
        param([string]$Name)
        foreach ($entry in $controls.CategoryList.Items) {
            if ($entry.Name -eq $Name) {
                $controls.CategoryList.SelectedItem = $entry
            }
        }
    }

    if (-not $Control) {
        switch ($Key) {
            'F5' {
                & $click $controls.RunButton
                return $true
            }
            'Escape' {
                if ($controls.SearchBox.Text) {
                    $controls.SearchBox.Text = ''
                    return $true
                }
                if ($Gui.MonitorComponent) {
                    Close-WindowComponent -Gui $Gui
                    return $true
                }
            }
        }
        return $false
    }

    switch ($Key) {
        'F' {
            if ($controls.FilterPanel.Visibility -ne [System.Windows.Visibility]::Visible) {
                & $open 'Overview'
            }
            [void]$controls.SearchBox.Focus()
            $controls.SearchBox.SelectAll()
            return $true
        }
        'S' {
            & $click $controls.SaveAsButton
            return $true
        }
        'O' {
            & $click $controls.OpenReportButton
            return $true
        }
        'M' {
            & $open 'Live monitor'
            return $true
        }
        'OemComma' {
            & $click $controls.SettingsButton
            return $true
        }
        'C' {
            # Plain Ctrl+C keeps its usual meaning: copy the selected text.
            if ($Shift) {
                & $click $controls.CopySummaryButton
                return $true
            }
        }
    }

    $false
}
