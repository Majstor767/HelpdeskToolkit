function Open-WindowUninstall {
    <#
    .SYNOPSIS
        Opens the page of Windows where a program is removed, and helps to find the program there.
    .DESCRIPTION
        The action of a click on a program in "What takes up the space" of a drive.
        Windows offers no way to open its "Installed apps" page at one particular
        program, so the page is opened as it is and the name of the program is put on
        the clipboard: pasted into the search field of the page (Ctrl+V), it shows the
        program at once. The status bar says so.

        The application itself removes nothing; the user chooses "Uninstall" on the
        page of Windows.

        Returns $true when the page was opened.
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

    if (-not (Invoke-CheckAction -Check 'Installed programs' -Category 'Software')) {
        $controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
        return $false
    }

    try {
        Set-Clipboard -Value $Name -ErrorAction Stop
        $controls.StatusText.Text = (Get-LocalizedText 'Installed apps is open. The name "{0}" was copied: paste it into the search field there (Ctrl+V), then choose Uninstall.') -f $Name
    }
    catch {
        # Another program can hold the clipboard for a moment; the page is open all the same.
        $controls.StatusText.Text = (Get-LocalizedText 'Installed apps is open. Look for "{0}" there and choose Uninstall.') -f $Name
    }

    $true
}
