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

        The icon is created with the first notification, unless it is there already
        (Enable-WindowTrayIcon), and stays until the window is closed for good. A
        click on the notification or on the icon brings the window to the front and
        opens the result (Open-WindowNotice).

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

    Enable-WindowTrayIcon -Gui $Gui

    # Windows cuts the title after 63 and the text after 255 characters.
    $shortTitle = if ($Title.Length -gt 63) { $Title.Substring(0, 60) + '...' } else { $Title }
    $shortText = if ($Text.Length -gt 255) { $Text.Substring(0, 252) + '...' } else { $Text }

    $Gui.TrayIcon.ShowBalloonTip(10000, $shortTitle, $shortText, [System.Windows.Forms.ToolTipIcon]::Warning)
}
