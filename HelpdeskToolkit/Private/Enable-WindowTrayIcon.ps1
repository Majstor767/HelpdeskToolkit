function Enable-WindowTrayIcon {
    <#
    .SYNOPSIS
        Puts the icon of the application into the notification area, next to the clock.
    .DESCRIPTION
        The icon is what is left of the application while its window is closed and it
        keeps running in the background, and it is where Windows notifications about
        new problems come from (Show-WindowToast).

        - A click on the icon, or on a notification, opens the window; when there is
          a notice, at the result it is about (Open-WindowNotice).
        - A right click opens a menu: open the window, run the check now, exit.
          "Exit" is the way to really end an application that stays in the background.

        The icon is created once per window and removed when the window is closed for
        good. Calling the function again does nothing.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    if ($Gui.TrayIcon) {
        return
    }

    Add-Type -AssemblyName System.Windows.Forms, System.Drawing

    $icon = New-Object -TypeName System.Windows.Forms.NotifyIcon
    $iconPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\HelpdeskToolkit.ico'
    $icon.Icon = if (Test-Path -LiteralPath $iconPath) {
        New-Object -TypeName System.Drawing.Icon -ArgumentList $iconPath
    }
    else {
        [System.Drawing.SystemIcons]::Information
    }
    $icon.Text = 'HelpdeskToolkit'

    # The handlers run later; they reach the window through the module-level variable.
    # They belong to Windows Forms, which the error handler of the window does not
    # hear: each one catches its own errors and writes them to the log.
    $menu = New-Object -TypeName System.Windows.Forms.ContextMenuStrip
    $openItem = $menu.Items.Add((Get-LocalizedText 'Open HelpdeskToolkit'))
    $openItem.Add_Click({
            try {
                if ($script:HealthCheckWindow) {
                    Show-WindowFromTray -Gui $script:HealthCheckWindow -Force
                }
            }
            catch {
                [void](Write-WindowError -Gui $script:HealthCheckWindow -ErrorRecord $_)
            }
        })
    $runItem = $menu.Items.Add((Get-LocalizedText 'Run check now'))
    $runItem.Add_Click({
            try {
                $state = $script:HealthCheckWindow
                if ($state -and -not $state.Worker) {
                    Invoke-WindowCheck -Gui $state
                }
            }
            catch {
                [void](Write-WindowError -Gui $script:HealthCheckWindow -ErrorRecord $_)
            }
        })
    [void]$menu.Items.Add((New-Object -TypeName System.Windows.Forms.ToolStripSeparator))
    $exitItem = $menu.Items.Add((Get-LocalizedText 'Exit'))
    $exitItem.Add_Click({
            try {
                if ($script:HealthCheckWindow) {
                    Exit-WindowApplication -Gui $script:HealthCheckWindow
                }
            }
            catch {
                [void](Write-WindowError -Gui $script:HealthCheckWindow -ErrorRecord $_)
            }
        })
    $icon.ContextMenuStrip = $menu

    $open = {
        try {
            if ($script:HealthCheckWindow) {
                [void](Open-WindowNotice -Gui $script:HealthCheckWindow)
            }
        }
        catch {
            [void](Write-WindowError -Gui $script:HealthCheckWindow -ErrorRecord $_)
        }
    }
    $icon.Add_BalloonTipClicked($open)
    # The right button belongs to the menu.
    $icon.Add_MouseClick({
            try {
                if ($args[1].Button -eq [System.Windows.Forms.MouseButtons]::Left -and $script:HealthCheckWindow) {
                    [void](Open-WindowNotice -Gui $script:HealthCheckWindow)
                }
            }
            catch {
                [void](Write-WindowError -Gui $script:HealthCheckWindow -ErrorRecord $_)
            }
        })

    $icon.Visible = $true
    $Gui.TrayIcon = $icon
}
