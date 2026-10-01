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
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    # A check is already running.
    if ($Gui.Worker) {
        return
    }

    $controls = $Gui.Controls
    $days = [int]$controls.DaysComboBox.SelectedItem.Tag
    $skipNetwork = $controls.SkipNetworkCheckBox.IsChecked -eq $true

    $controls.RunButton.IsEnabled = $false
    $controls.RunButton.Content = 'Checking ...'
    $controls.ProgressBar.Value = 0
    $controls.ProgressBar.Visibility = [System.Windows.Visibility]::Visible
    $controls.StatusText.Text = 'Starting the check ...'

    # The background runspace knows nothing about this session, so it imports the
    # module itself and then calls the same public command as the console version.
    $work = {
        param($ManifestPath, $Days, $SkipNetwork)
        Import-Module -Name $ManifestPath
        Get-PCHealthReport -Days $Days -SkipNetwork:$SkipNetwork
    }

    $worker = [powershell]::Create()
    [void]$worker.AddScript($work.ToString()).AddArgument($Gui.ManifestPath).AddArgument($days).AddArgument($skipNetwork)

    $Gui.Worker = $worker
    $Gui.Handle = $worker.BeginInvoke()
    $Gui.Timer.Start()
}
