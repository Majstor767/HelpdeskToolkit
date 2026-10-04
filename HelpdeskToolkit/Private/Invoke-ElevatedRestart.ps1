function Invoke-ElevatedRestart {
    <#
    .SYNOPSIS
        Starts the application again with administrator rights and closes this window.
    .DESCRIPTION
        Windows decides about elevation, not the application: the "RunAs" verb makes
        Windows show its User Account Control prompt, and the new window only starts
        when the user confirms it (or enters an administrator password). If the user
        declines, this window stays open and says so.

        The new instance is started hidden through Start-Process, so no console window
        appears next to it. Nothing about the computer is changed; the application
        stays read-only with administrator rights too.

        With -RunCheck the new instance starts the check as soon as it is open, so
        the user does not have to click again after confirming.

        Returns $true when the elevated instance was started.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$RunCheck
    )

    $powershell = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

    # The new copy must find the place of the one running window free (see
    # Lock-AppInstance); this copy takes it back when the new one does not start.
    $hadLock = [bool]$Gui.InstanceLock
    if ($Gui.InstanceLock) {
        $Gui.InstanceLock.Dispose()
        $Gui.InstanceLock = $null
    }
    try {
        Start-Process -FilePath $powershell -ArgumentList (Get-LauncherArgument -RunCheck:$RunCheck) -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
    }
    catch {
        # Thrown when the user answers "No" in the User Account Control prompt.
        if ($hadLock) {
            $Gui.InstanceLock = Lock-AppInstance
        }
        $Gui.Controls.StatusText.Text = Get-LocalizedText 'Administrator rights were not granted; the window keeps running with standard rights.'
        return $false
    }

    # Closes for good, also when the window is set to stay in the background.
    Exit-WindowApplication -Gui $Gui
    $true
}
