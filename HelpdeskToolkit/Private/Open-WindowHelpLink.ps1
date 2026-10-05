function Open-WindowHelpLink {
    <#
    .SYNOPSIS
        Opens the page that explains a problem in the browser.
    .DESCRIPTION
        The action of a click on one of the links below a recommended fix (see
        Get-CheckHelpLink). The address is handed to Windows, which opens it in the
        default browser of the user.

        Only addresses that begin with "https://" are opened: the links are built
        from Config\Help.psd1, and anything else in their place would be a mistake in
        that file, not something to hand to Windows.

        Returns $true when the address was handed to Windows.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )

    if ($Url -notmatch '^https://\S+$') {
        return $false
    }

    try {
        Start-Process -FilePath $Url -ErrorAction Stop
        $Gui.Controls.StatusText.Text = Get-LocalizedText 'The page was opened in the browser.'
        $true
    }
    catch {
        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'The page could not be opened: {0}') -f $_.Exception.Message
        $false
    }
}
