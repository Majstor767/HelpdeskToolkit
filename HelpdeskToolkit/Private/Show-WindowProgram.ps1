function Show-WindowProgram {
    <#
    .SYNOPSIS
        Shows the details of a program below the program lists of the Live monitor.
    .DESCRIPTION
        Called when a program in one of the three lists is clicked. The details come
        from Get-ProgramDetail and are read once, at the moment of the click. A
        program that has ended in the meantime is reported as such.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Name of the program as shown in the list.
        [Parameter(Mandatory)]
        [string]$Name
    )

    $controls = $Gui.Controls
    $details = @(Get-ProgramDetail -Name $Name)

    $controls.MonitorProgramTitle.Text = $Name
    $controls.MonitorProgramDetails.ItemsSource = if ($details.Count -gt 0) {
        $details
    }
    else {
        @([PSCustomObject]@{ Name = Get-LocalizedText 'Processes'; Text = Get-LocalizedText 'The program is no longer running.' })
    }

    $controls.MonitorProgramCard.Visibility = [System.Windows.Visibility]::Visible
    $controls.MonitorProgramHint.Visibility = [System.Windows.Visibility]::Collapsed
}
