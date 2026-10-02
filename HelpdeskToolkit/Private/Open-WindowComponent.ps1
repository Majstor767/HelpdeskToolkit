function Open-WindowComponent {
    <#
    .SYNOPSIS
        Opens the detail page of the processor, the memory or the graphics card.
    .DESCRIPTION
        The action of a click on one of the three tiles of the Live monitor. The
        detail page takes the place of the monitor and shows everything that can be
        read about the component:

        - at the top the value right now, its status dot with the reason, a large
          history graph and, while the value is close to its limit or above it, what
          to do about it (see Show-WindowComponent)
        - below it the values of the newest measurement
        - and then everything else Windows reports, read in the background the first
          time the page is opened and again every few seconds while it is open (see
          Invoke-WindowComponentDetail and Show-WindowComponentDetail)

        The measurements of the monitor go on while the page is open. Close-WindowComponent
        returns to the monitor.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [ValidateSet('Cpu', 'Memory', 'Gpu')]
        [string]$Name
    )

    $controls = $Gui.Controls
    $titles = @{ Cpu = 'Processor'; Memory = 'Memory'; Gpu = 'Graphics card' }

    $Gui.MonitorComponent = $Name

    # The graph and the large number take the color of the component.
    # (A reference to the brush, not the brush itself, so the color follows the theme.)
    $brush = "${Name}Brush"
    $controls.ComponentLine.SetResourceReference([System.Windows.Shapes.Shape]::StrokeProperty, $brush)
    $controls.ComponentArea.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $brush)
    $controls.ComponentValue.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $brush)

    $controls.PageTitle.Text = Get-LocalizedText $titles[$Name]
    $controls.MonitorPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $controls.ComponentPanel.Visibility = [System.Windows.Visibility]::Visible
    $controls.ComponentPanel.ScrollToTop()

    $state = $Gui.ComponentDetail[$Name]
    if (-not $state) {
        $state = @{ State = 'None'; Detail = $null; Error = ''; Worker = $null; Handle = $null; FinishedAt = $null }
        $Gui.ComponentDetail[$Name] = $state
    }
    if ($state.State -in 'None', 'Failed') {
        Invoke-WindowComponentDetail -Gui $Gui -Name $Name
    }

    Show-WindowComponent -Gui $Gui
    Show-WindowComponentDetail -Gui $Gui
}
