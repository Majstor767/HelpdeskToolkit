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

    # Installed and portable copies have the launcher script next to the module folder.
    # A module loaded from somewhere else is started through its manifest instead.
    $launcher = Join-Path -Path (Split-Path -Path $script:ModuleRoot -Parent) -ChildPath 'Start-HelpdeskToolkit.ps1'
    if (Test-Path -LiteralPath $launcher) {
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $launcher
    }
    else {
        $manifest = (Join-Path -Path $script:ModuleRoot -ChildPath 'HelpdeskToolkit.psd1').Replace("'", "''")
        $arguments = '-NoProfile -ExecutionPolicy Bypass -Command "Import-Module ''{0}''; Show-PCHealthCheck"' -f $manifest
    }

    try {
        Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -ErrorAction Stop
    }
    catch {
        # Thrown when the user answers "No" in the User Account Control prompt.
        $Gui.Controls.StatusText.Text = 'Administrator rights were not granted; the window keeps running with standard rights.'
        return $false
    }

    $Gui.Window.Close()
    $true
}
