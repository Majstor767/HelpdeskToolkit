function Invoke-AppRestart {
    <#
    .SYNOPSIS
        Starts the application again and closes this window.
    .DESCRIPTION
        The language and the theme are applied when the window is created. After the
        user changed one of them on the Settings page, this function starts a new copy
        of the application, which reads the new settings, and closes the old one.

        The new copy runs with the same rights as this one: started from an elevated
        window it is elevated too, without another prompt. It does not ask about
        administrator rights again and runs the check at once, so the results are back
        without a click.

        Returns $true when the new copy was started.
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
        Start-Process -FilePath $powershell -ArgumentList (Get-LauncherArgument -RunCheck) -WindowStyle Hidden -ErrorAction Stop
    }
    catch {
        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'The application could not be restarted: {0}') -f $_.Exception.Message
        return $false
    }

    $Gui.Window.Close()
    $true
}
