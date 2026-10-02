function Invoke-WindowCheck {
    <#
    .SYNOPSIS
        Starts the health check for the application window in the background.
    .DESCRIPTION
        A window stays responsive only while its own thread is free. The checks take
        several seconds (longer when the network is down and the tests wait for
        timeouts), so they run in a second PowerShell runspace, which is a separate
        thread with its own copy of the module. The window thread only starts the
        work here; Receive-WindowCheck picks up the progress and the result.

        With -Background the check is one the application repeats by itself (see
        Invoke-WindowAutoCheck). It runs the same way but stays out of the way: no
        progress panel, and the results on the screen stay until the new ones arrive.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Background
    )

    # A check is already running.
    if ($Gui.Worker) {
        return
    }

    $controls = $Gui.Controls
    $days = [int]$controls.DaysComboBox.SelectedItem.Tag
    $skipNetwork = $controls.SkipNetworkCheckBox.IsChecked -eq $true

    $controls.RunButton.IsEnabled = $false
    if ($Background) {
        $controls.RunButton.Content = Get-LocalizedText 'Updating ...'
        $controls.StatusText.Text = Get-LocalizedText 'Checking again in the background; the results stay in place until the new ones are there ...'
    }
    else {
        $controls.RunButton.Content = Get-LocalizedText 'Checking ...'
        $controls.StatusText.Text = Get-LocalizedText 'The check is running ...'

        # Progress panel: empty the bar and show it. An animation of the previous run would
        # otherwise keep holding the old value, so it is removed first.
        $controls.ProgressBar.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
        $controls.ProgressBar.Value = 0
        $controls.RunTitle.Text = Get-LocalizedText 'Starting the check ...'
        $controls.RunStep.Text = ''
        $controls.RunPercent.Text = '0 %'
        $controls.RunPanel.Visibility = [System.Windows.Visibility]::Visible
    }

    # The background runspace knows nothing about this session, so it imports the
    # module itself and then calls the same public command as the console version.
    # A check the application repeats by itself may reuse the measurements that take
    # long and change slowly; a check the user asked for measures everything anew.
    $work = {
        param($ManifestPath, $Days, $SkipNetwork, $AllowCached)
        Import-Module -Name $ManifestPath
        Get-PCHealthReport -Days $Days -SkipNetwork:$SkipNetwork -AllowCached:$AllowCached
    }

    $worker = [powershell]::Create()
    [void]$worker.AddScript($work.ToString()).AddArgument($Gui.ManifestPath).AddArgument($days).AddArgument($skipNetwork).AddArgument([bool]$Background)

    $Gui.Background = [bool]$Background
    $Gui.RunStep = ''
    $Gui.Worker = $worker
    $Gui.Handle = $worker.BeginInvoke()
    $Gui.Timer.Start()

    # While the first check runs, the empty Overview says so instead of "No results yet".
    if (-not $Gui.Report -and $Gui.Page -notin 'Live monitor', 'Settings') {
        Show-WindowPage -Gui $Gui -Name 'Overview'
    }
}
