function Switch-WindowStartupProgram {
    <#
    .SYNOPSIS
        Switches a startup program off or on after asking, when its line in the result "Startup programs" is clicked.
    .DESCRIPTION
        The result "Startup programs" lists every program that is set to start with
        Windows. A click on one of them asks whether to stop it from starting (or,
        for a program that is switched off, whether to let it start again) and, with
        "Yes", turns its switch (Set-StartupProgramState). That is the switch of
        Task Manager > Startup apps: the program stays installed, nothing is deleted,
        and the next click turns it back.

        The state is read at the moment of the click, because the list on the screen
        can be minutes old. Afterwards a check is started in the background, so the
        list and the count show the new state.

        Nothing is changed, and the window says why, when
        - the program is no longer among the startup programs of this computer (the
          report on the screen may be old, or from another computer),
        - the program starts for every user and the window has no administrator
          rights: its switch lies where only administrators can write, or
        - the answer is "No".

        What was switched is written to the log of the application. Returns $true
        when the switch was turned.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Name of the program as the result lists it.
        [Parameter(Mandatory)]
        [string]$Name
    )

    $controls = $Gui.Controls

    $program = Get-StartupProgram | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (-not $program) {
        $controls.StatusText.Text = (Get-LocalizedText '"{0}" is not among the startup programs of this computer. Run the check again to see the current list.') -f $Name
        return $false
    }

    if ($program.Scope -eq 'Machine' -and -not (Test-IsAdministrator)) {
        $controls.StatusText.Text = (Get-LocalizedText '"{0}" starts for every user of this computer, so switching it needs administrator rights. Choose "Restart as administrator" first, or use Task Manager > Startup apps.') -f $Name
        return $false
    }

    $enable = -not $program.Enabled
    $question = if ($enable) {
        ((Get-LocalizedText 'Let "{0}" start with Windows again?') -f $Name) + "`n`n" +
            (Get-LocalizedText 'It was switched off. From the next sign-in on it starts by itself again.')
    }
    else {
        ((Get-LocalizedText 'Stop "{0}" from starting with Windows?') -f $Name) + "`n`n" +
            (Get-LocalizedText 'The program stays installed and can still be started by hand; only its automatic start is switched off, the same switch as in Task Manager > Startup apps. A click on it here switches it on again.')
    }
    if (-not (Confirm-WindowChoice -Gui $Gui -Title (Get-LocalizedText 'Startup programs') -Text $question)) {
        $controls.StatusText.Text = Get-LocalizedText 'Nothing was changed.'
        return $false
    }

    try {
        Set-StartupProgramState -Program $program -Enabled $enable -Confirm:$false
    }
    catch {
        $controls.StatusText.Text = (Get-LocalizedText 'The startup of "{0}" could not be switched: {1}') -f $Name, $_.Exception.Message
        [void](Write-AppLog -Message ('The startup of "{0}" could not be switched ({1}, {2})' -f $Name, $program.Scope, $program.Source) -ErrorRecord $_)
        return $false
    }

    $state = if ($enable) { 'on' } else { 'off' }
    [void](Write-AppLog -Level Info -Message ('The startup of "{0}" was switched {1} ({2}, {3}, entry "{4}")' -f $Name, $state, $program.Scope, $program.Source, $program.Entry))
    # The result on the screen is from before the click; a check brings the new state.
    if ($Gui.Report -and -not $Gui.Worker) {
        Invoke-WindowCheck -Gui $Gui -Background
    }
    $controls.StatusText.Text = if ($enable) {
        (Get-LocalizedText '"{0}" starts with Windows again. The list is being updated.') -f $Name
    }
    else {
        (Get-LocalizedText '"{0}" no longer starts with Windows. The list is being updated.') -f $Name
    }
    $true
}
