function Invoke-WindowAutoCheck {
    <#
    .SYNOPSIS
        Repeats the health check in the background when it is time for it.
    .DESCRIPTION
        Called by a timer of the window every few seconds. After the first check,
        which the user starts, the application keeps the results up to date by itself:
        when the last check ended longer ago than the setting AutoCheckMinutes says, a
        new one is started in the background (Invoke-WindowCheck -Background). The
        results on the screen stay in place until the new ones are there. While the
        window is hidden or the computer runs on its battery, the check is repeated
        less often (see Get-AutoCheckInterval).

        Nothing is started while there is no report yet, while a check is running, or
        when the setting is 0 ("Never").

        Returns $true when a check was started.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $minutes = Get-AutoCheckInterval -Gui $Gui
    if ($minutes -le 0 -or -not $Gui.Report -or $Gui.Worker -or -not $Gui.LastCheckAt) {
        return $false
    }
    if (((Get-Date) - $Gui.LastCheckAt).TotalMinutes -lt $minutes) {
        return $false
    }

    Invoke-WindowCheck -Gui $Gui -Background
    $true
}
