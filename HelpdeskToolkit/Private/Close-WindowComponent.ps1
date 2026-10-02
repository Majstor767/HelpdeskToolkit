function Close-WindowComponent {
    <#
    .SYNOPSIS
        Leaves the detail page of a component and shows the Live monitor again.
    .DESCRIPTION
        The action of the "Back" button of the detail page and of the Esc key. What
        was read about the component is kept, so opening its page again shows it at once.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls

    $Gui.MonitorComponent = ''
    $controls.PageTitle.Text = Get-LocalizedText 'Live monitor'
    $controls.ComponentPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $controls.MonitorPanel.Visibility = [System.Windows.Visibility]::Visible
}
