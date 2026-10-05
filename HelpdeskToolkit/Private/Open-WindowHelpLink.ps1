function Open-WindowHelpLink {
    <#
    .SYNOPSIS
        Opens the page that explains a problem in the browser.
    .DESCRIPTION
        The action of a click on one of the links below a recommended fix (see
        Get-CheckHelpLink). The address is opened in the default browser of the user
        (see Open-WebAddress, which also knows how to do that from a window that runs
        with administrator rights, and when the default browser of Windows is gone).
        Only "https://" addresses are opened.

        When the page had to be opened in another browser because Windows names one
        that is no longer installed, the status bar says so and where that is set.

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

    try {
        if (-not (Open-WebAddress -Url $Url)) {
            return $false
        }
        $Gui.Controls.StatusText.Text = if ((Get-DefaultBrowser).IsBroken) {
            Get-LocalizedText 'The page was opened in another browser: the default browser of Windows is no longer installed. Choose one under Settings > Apps > Default apps.'
        }
        else {
            Get-LocalizedText 'The page was opened in the browser.'
        }
        $true
    }
    catch {
        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'The page could not be opened: {0}') -f $_.Exception.Message
        $false
    }
}
