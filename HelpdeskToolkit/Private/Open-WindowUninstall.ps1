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

        The uninstaller is started the way Windows starts it: as the user, from the
        folder it is in.

        - A window with administrator rights hands the start to the desktop of the
          user (Invoke-DesktopShell) instead of starting the uninstaller itself. An
          uninstaller that is started with administrator rights often shows its
          window and then does nothing: the uninstallers of game launchers (Steam,
          Battle.net, Riot) only tell their client, which runs as the user and does
          not listen to a program with more rights. It also means that nothing a
          user wrote into the own part of the registry is ever started with more
          rights than that user has.
        - What was started is written to the log of the application, so a start
          that led to nothing can be looked up.

        A program whose uninstaller no longer exists cannot be uninstalled: only its
        entry in the list is left (see Test-UninstallerMissing). The window says so and
        opens "Programs and Features", where Windows offers to remove such an entry.

        The page "Installed apps" of Windows is opened instead, with the name of the
        program on the clipboard for its search field, when the program has no
        uninstall command (apps from the Microsoft Store) or the uninstaller did not
        start.

        Returns $true when the uninstaller was started or a page was opened.
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
    $reason = ''

    # Puts the name on the clipboard for the search field of the page that is opened.
    $copyName = {
        try {
            Set-Clipboard -Value $Name -ErrorAction Stop
            $true
        }
        catch {
            # Another program can hold the clipboard for a moment; the page is open all the same.
            $false
        }
    }

    if ($command) {
        $question = ((Get-LocalizedText 'Start the uninstaller of "{0}"?') -f $Name) + "`n`n" +
            (Get-LocalizedText 'The uninstaller of the program opens, the same one Windows starts from Installed apps. Follow its window; it can ask for administrator rights.')
        if (-not (Confirm-WindowChoice -Gui $Gui -Title (Get-LocalizedText 'Uninstall a program') -Text $question)) {
            $controls.StatusText.Text = Get-LocalizedText 'Nothing was started.'
            return $false
        }

        # The folder of the uninstaller, when the command names one.
        $folder = ''
        if ($command.FilePath -match '[\\/]') {
            $parent = Split-Path -Path $command.FilePath -Parent
            if ($parent -and (Test-Path -LiteralPath $parent -PathType Container)) {
                $folder = $parent
            }
        }

        try {
            if (Test-IsAdministrator) {
                Invoke-DesktopShell -FilePath $command.FilePath -Arguments ([string]$command.Arguments) -WorkingDirectory $folder
                $how = 'as the user, through the desktop'
            }
            else {
                $start = @{ FilePath = $command.FilePath; ErrorAction = 'Stop' }
                if ($command.Arguments) {
                    $start.ArgumentList = $command.Arguments
                }
                if ($folder) {
                    $start.WorkingDirectory = $folder
                }
                Start-Process @start
                $how = 'as the user'
            }
            [void](Write-AppLog -Level Info -Message ('The uninstaller of "{0}" was started {1}: {2} {3}' -f $Name, $how, $command.FilePath, $command.Arguments))
            $controls.StatusText.Text = (Get-LocalizedText 'The uninstaller of "{0}" was started. Follow its window, and measure the drive again when it is done.') -f $Name
            return $true
        }
        catch {
            $reason = (Get-LocalizedText 'The uninstaller of "{0}" did not start.') -f $Name
            [void](Write-AppLog -Message ('The uninstaller of "{0}" did not start: {1} {2}' -f $Name, $command.FilePath, $command.Arguments) -ErrorRecord $_)
        }
    }
    elseif ($program -and (Test-UninstallerMissing -Program $program)) {
        # Only the entry is left. "Programs and Features" is the place where Windows
        # offers to take such an entry out of the list.
        try {
            Start-Process -FilePath (Join-Path -Path ([string]$env:WINDIR) -ChildPath 'System32\control.exe') -ArgumentList 'appwiz.cpl' -ErrorAction Stop
            [void](& $copyName)
            $controls.StatusText.Text = (Get-LocalizedText '"{0}" cannot be uninstalled: its uninstaller no longer exists, only the entry in the list is left. "Programs and Features" is open; choose the entry there and Uninstall, and Windows offers to remove it from the list.') -f $Name
            return $true
        }
        catch {
            $reason = (Get-LocalizedText '"{0}" cannot be uninstalled: its uninstaller no longer exists, only the entry in the list is left.') -f $Name
            Write-Verbose "Programs and Features could not be opened: $($_.Exception.Message)"
        }
    }

    if (-not (Invoke-CheckAction -Check 'Installed programs' -Category 'Software')) {
        $controls.StatusText.Text = (@($reason, (Get-LocalizedText 'Windows could not open that place.')) | Where-Object { $_ }) -join ' '
        return $false
    }

    $text = if (& $copyName) {
        (Get-LocalizedText 'Installed apps is open. The name "{0}" was copied: paste it into the search field there (Ctrl+V), then choose Uninstall.') -f $Name
    }
    else {
        (Get-LocalizedText 'Installed apps is open. Look for "{0}" there and choose Uninstall.') -f $Name
    }
    $controls.StatusText.Text = (@($reason, $text) | Where-Object { $_ }) -join ' '
    $true
}
