function Open-WindowUninstall {
    <#
    .SYNOPSIS
        Starts the uninstaller of a program, after asking; or opens the page of Windows where it is removed.
    .DESCRIPTION
        The action of a click on a program in "What takes up the space" of a drive.

        The window asks whether to start the uninstaller of the program. With "Yes" it
        starts the program's own uninstaller: the command the installer wrote down,
        the same one Windows runs when "Uninstall" is chosen under Installed apps (see
        Get-UninstallCommand). From there on the uninstaller is in charge: it shows
        its own window, asks its own questions and, where it needs them, asks Windows
        for administrator rights. The application removes nothing by itself and starts
        nothing without the "Yes".

        The page "Installed apps" of Windows is opened instead, with the name of the
        program on the clipboard for its search field, when

        - the program has no uninstaller that can be started (apps from the Microsoft
          Store, or a file that is gone),
        - the uninstaller did not start, or
        - the window runs with administrator rights and the program is installed for
          one user only. Its entry lies in the part of the registry that user can
          write to, and what is written there is not started with more rights than
          that user has.

        Returns $true when the uninstaller was started or the page was opened.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Name of the program as "Installed apps" lists it.
        [Parameter(Mandatory)]
        [string]$Name
    )

    $controls = $Gui.Controls

    # Read at the moment of the click: the list on the screen can be minutes old.
    $program = Get-InstalledProgram | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    $command = Get-UninstallCommand -Program $program
    $perUser = $program -and $program.PSObject.Properties['Scope'] -and $program.Scope -eq 'User'
    $reason = ''
    if ($command -and $perUser -and (Test-IsAdministrator)) {
        $command = $null
        $reason = (Get-LocalizedText '"{0}" is installed for one user only, so its uninstaller is not started with administrator rights.') -f $Name
    }

    if ($command) {
        $question = ((Get-LocalizedText 'Start the uninstaller of "{0}"?') -f $Name) + "`n`n" +
            (Get-LocalizedText 'The uninstaller of the program opens, the same one Windows starts from Installed apps. Follow its window; it can ask for administrator rights.')
        if (-not (Confirm-WindowChoice -Gui $Gui -Title (Get-LocalizedText 'Uninstall a program') -Text $question)) {
            $controls.StatusText.Text = Get-LocalizedText 'Nothing was started.'
            return $false
        }

        try {
            $start = @{ FilePath = $command.FilePath; ErrorAction = 'Stop' }
            if ($command.Arguments) {
                $start.ArgumentList = $command.Arguments
            }
            Start-Process @start
            $controls.StatusText.Text = (Get-LocalizedText 'The uninstaller of "{0}" was started. Follow its window, and measure the drive again when it is done.') -f $Name
            return $true
        }
        catch {
            $reason = (Get-LocalizedText 'The uninstaller of "{0}" did not start.') -f $Name
            Write-Verbose "The uninstaller could not be started: $($_.Exception.Message)"
        }
    }

    if (-not (Invoke-CheckAction -Check 'Installed programs' -Category 'Software')) {
        $controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
        return $false
    }

    try {
        Set-Clipboard -Value $Name -ErrorAction Stop
        $text = (Get-LocalizedText 'Installed apps is open. The name "{0}" was copied: paste it into the search field there (Ctrl+V), then choose Uninstall.') -f $Name
    }
    catch {
        # Another program can hold the clipboard for a moment; the page is open all the same.
        $text = (Get-LocalizedText 'Installed apps is open. Look for "{0}" there and choose Uninstall.') -f $Name
    }
    $controls.StatusText.Text = (@($reason, $text) | Where-Object { $_ }) -join ' '
    $true
}
