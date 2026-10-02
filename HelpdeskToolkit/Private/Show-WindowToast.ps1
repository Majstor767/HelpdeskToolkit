function Show-WindowToast {
    <#
    .SYNOPSIS
        Shows a Windows notification about new problems.
    .DESCRIPTION
        Used when an automatic check finds a problem while the window is not in
        front. The notification is the "balloon" of an icon in the notification area
        of the taskbar, which Windows 10 and 11 display as an ordinary notification.
        This needs nothing but what Windows has: no registration of the application
        and nothing to install.

        The icon is created with the first notification and stays until the window is
        closed. A click on the notification or on the icon brings the window to the
        front and opens the result (Open-WindowNotice).

        Windows decides whether a notification is displayed: with "Do not disturb"
        turned on it only goes to the notification center.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Text
    )

    if (-not $Gui.TrayIcon) {
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
        $icon.Visible = $true

        # The handlers run later; they reach the window through the module-level variable.
        $open = {
            if ($script:HealthCheckWindow) {
                [void](Open-WindowNotice -Gui $script:HealthCheckWindow)
            }
        }
        $icon.Add_BalloonTipClicked($open)
        $icon.Add_Click($open)

        $Gui.TrayIcon = $icon
    }

    # Windows cuts the title after 63 and the text after 255 characters.
    $shortTitle = if ($Title.Length -gt 63) { $Title.Substring(0, 60) + '...' } else { $Title }
    $shortText = if ($Text.Length -gt 255) { $Text.Substring(0, 252) + '...' } else { $Text }

    $Gui.TrayIcon.ShowBalloonTip(10000, $shortTitle, $shortText, [System.Windows.Forms.ToolTipIcon]::Warning)
}
