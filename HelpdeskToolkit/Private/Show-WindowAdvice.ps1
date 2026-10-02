function Show-WindowAdvice {
    <#
    .SYNOPSIS
        Draws the status dots of the Live monitor tiles and the advice that belongs to them.
    .DESCRIPTION
        Every one of the three tiles (processor, memory, graphics) has a dot: green
        while the value is fine, orange when it comes close to its limit or keeps
        rising, red when it is above the limit (see Get-MonitorStatus). A red dot is
        joined by a warning triangle. A click on the triangle opens a card below the
        tiles that says what to do, with a button that opens Task Manager.

        The card closes by itself when the value is no longer above its limit.

        With -Status the judgements of a new measurement are stored and shown;
        without it the stored ones are drawn again (after a click on a triangle).
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The objects returned by Get-MonitorStatus.
        [object[]]$Status
    )

    $controls = $Gui.Controls
    $visible = [System.Windows.Visibility]::Visible
    $collapsed = [System.Windows.Visibility]::Collapsed

    if ($PSBoundParameters.ContainsKey('Status')) {
        $Gui.MonitorStatus = @($Status | Where-Object { $_ })
    }

    $brushes = @{ Ok = 'OkBrush'; Near = 'WarningDotBrush'; Over = 'CriticalBrush'; None = 'NeutralBrush' }
    $open = $null

    foreach ($entry in @($Gui.MonitorStatus)) {
        $dot = $controls["Monitor$($entry.Name)Dot"]
        $button = $controls["Monitor$($entry.Name)AdviceButton"]

        $dot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $brushes[$entry.Level])
        $dot.ToolTip = $entry.Summary

        if ($entry.Level -eq 'Over') {
            $button.Visibility = $visible
        }
        else {
            $button.Visibility = $collapsed
            if ($Gui.MonitorAdvice -eq $entry.Name) {
                $Gui.MonitorAdvice = ''
            }
        }

        $button.IsChecked = $Gui.MonitorAdvice -eq $entry.Name
        if ($Gui.MonitorAdvice -eq $entry.Name) {
            $open = $entry
        }
    }

    if ($open) {
        $controls.MonitorAdviceTitle.Text = $open.Title
        $controls.MonitorAdviceItems.ItemsSource = @($open.Advice | ForEach-Object { [PSCustomObject]@{ Text = $_ } })

        $action = Get-CheckAction -Check $open.ActionCheck -Category 'Hardware'
        if ($action) {
            $controls.MonitorAdviceAction.Content = Get-LocalizedText $action.Label
            $controls.MonitorAdviceAction.Visibility = $visible
        }
        else {
            $controls.MonitorAdviceAction.Visibility = $collapsed
        }
        $controls.MonitorAdviceCard.Visibility = $visible
    }
    else {
        $controls.MonitorAdviceCard.Visibility = $collapsed
    }
}
