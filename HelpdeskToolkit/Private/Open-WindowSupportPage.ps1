function Open-WindowSupportPage {
    <#
    .SYNOPSIS
        Opens the support page of the maker of the computer and puts the serial number on the clipboard.
    .DESCRIPTION
        The action of the button of the result "Warranty and support". The page is the
        one listed for the maker in Config\Actions.psd1; it opens in the default
        browser. The serial number is not sent anywhere by the application: it is put
        on the clipboard, and the user pastes it into the search field of the page
        (Ctrl+V). The status bar says so.

        The serial number is taken from the report that is shown, so it also fits a
        report that was loaded from another computer.

        Returns $true when the page was opened.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The value of the result, which starts with the name of the maker.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    $controls = $Gui.Controls

    if (-not (Invoke-CheckAction -Check 'Warranty and support' -Category 'Specifications' -Value $Value)) {
        $controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
        return $false
    }

    $serial = ''
    if ($Gui.Report) {
        $serial = [string]($Gui.Report.Results | Where-Object { $_.Check -eq 'Serial number' } | Select-Object -First 1 -ExpandProperty Value)
    }

    # A placeholder ("Not set by the manufacturer") is of no use on the page.
    if (-not $serial -or $serial -match '\s') {
        $controls.StatusText.Text = Get-LocalizedText 'The support page is open. Enter the serial number from the label of the computer there.'
        return $true
    }

    try {
        Set-Clipboard -Value $serial -ErrorAction Stop
        $controls.StatusText.Text = (Get-LocalizedText 'The support page is open. The serial number {0} was copied: paste it into the search field there (Ctrl+V).') -f $serial
    }
    catch {
        # Another program can hold the clipboard for a moment; the page is open all the same.
        $controls.StatusText.Text = (Get-LocalizedText 'The support page is open. Enter the serial number {0} there.') -f $serial
    }

    $true
}
