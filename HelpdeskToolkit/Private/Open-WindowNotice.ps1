function Open-WindowNotice {
    <#
    .SYNOPSIS
        Brings the window to the front and opens the result of the newest notice.
    .DESCRIPTION
        The action of a click on the Windows notification (see Show-WindowToast) and
        on the icon in the notification area. A minimized window is restored first.
        Without notices the window is only brought to the front.

        Returns $true when a result was opened.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $window = $Gui.Window
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
    }
    [void]$window.Activate()

    $newest = @($Gui.Notices.Values) | Select-Object -Last 1
    if (-not $newest) {
        return $false
    }

    Show-WindowResult -Gui $Gui -Category $newest.Category -Check $newest.Check
}
