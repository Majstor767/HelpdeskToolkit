function Invoke-WindowStartup {
    <#
    .SYNOPSIS
        Decides what the window does the moment it has opened: ask about administrator rights, or start the check.
    .DESCRIPTION
        Called once, when the window has been drawn for the first time. The check
        always starts by itself; the only question is with which rights:

        - The window already runs with administrator rights, or was started to run
          the check at once (-RunCheck, used after a restart): the check starts.
        - The setting StartupElevation decides otherwise:
          "Ask" (the default) shows the question over the window; the answer is
          carried out by Invoke-WindowElevationChoice.
          "Always" restarts the application with administrator rights straight away;
          Windows still shows its own confirmation.
          "Never" starts the check with standard rights.
        - With -NoQuestion and without -RunCheck nothing happens: the window opens the
          way it used to and waits for "Run check".

        The two switches are in $Gui.Startup. Returns what was done: "Check", "Ask",
        "Elevate" or "None".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $mode = $Gui.Startup
    $controls = $Gui.Controls

    if ($mode.NoQuestion -and -not $mode.RunCheck) {
        return 'None'
    }

    if ($mode.RunCheck -or (Test-IsAdministrator)) {
        Invoke-WindowCheck -Gui $Gui
        return 'Check'
    }

    switch ([string]$Gui.Settings.StartupElevation) {
        'Never' {
            Invoke-WindowCheck -Gui $Gui
            return 'Check'
        }
        'Always' {
            Invoke-WindowElevationChoice -Gui $Gui -Elevate
            return 'Elevate'
        }
        default {
            # The window behind the question cannot be used until it is answered.
            $controls.MainLayout.IsEnabled = $false
            $controls.StartupOverlay.Visibility = [System.Windows.Visibility]::Visible
            [void]$controls.StartupYesButton.Focus()
            return 'Ask'
        }
    }
}
