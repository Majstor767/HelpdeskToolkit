function Invoke-WindowElevationChoice {
    <#
    .SYNOPSIS
        Carries out the answer to the question at the start: with administrator rights or without.
    .DESCRIPTION
        The action of the two buttons of the question (see Invoke-WindowStartup).

        - With -Elevate the application is started again with administrator rights
          and told to run the check at once (Invoke-ElevatedRestart -RunCheck); this
          window then closes. Windows shows its own confirmation first. When the
          user declines it there, this window stays and runs the check with standard
          rights, so an answer always leads to results.
        - Without -Elevate the check starts in this window with standard rights: the
          checks that need administrator rights are marked "Requires admin".

        When "Remember my answer" is ticked, the answer becomes the setting
        StartupElevation ("Always" or "Never") and the question is not asked again;
        the Settings page can change it back.

        Returns $true when the check was started in this window.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Elevate
    )

    $controls = $Gui.Controls

    $controls.StartupOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $controls.MainLayout.IsEnabled = $true

    if ($controls.StartupRememberBox.IsChecked -eq $true) {
        $Gui.Settings.StartupElevation = if ($Elevate) { 'Always' } else { 'Never' }
        [void](Save-AppSetting -Setting $Gui.Settings)
    }

    $declined = $false
    if ($Elevate) {
        if (Invoke-ElevatedRestart -Gui $Gui -RunCheck) {
            # The elevated copy takes over; this window is closing.
            return $false
        }
        $declined = $true
    }

    Invoke-WindowCheck -Gui $Gui
    if ($declined) {
        $controls.StatusText.Text = Get-LocalizedText 'Administrator rights were not granted; the check runs with standard rights.'
    }
    $true
}
