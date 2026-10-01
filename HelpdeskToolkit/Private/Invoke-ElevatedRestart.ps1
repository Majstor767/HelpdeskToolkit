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

        Returns $true when the elevated instance was started.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $powershell = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

    try {
        Start-Process -FilePath $powershell -ArgumentList (Get-LauncherArgument) -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
    }
    catch {
        # Thrown when the user answers "No" in the User Account Control prompt.
        $Gui.Controls.StatusText.Text = Get-LocalizedText 'Administrator rights were not granted; the window keeps running with standard rights.'
        return $false
    }

    $Gui.Window.Close()
    $true
}
