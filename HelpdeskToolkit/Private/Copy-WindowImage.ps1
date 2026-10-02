function Copy-WindowImage {
    <#
    .SYNOPSIS
        Puts a picture of the window on the clipboard (the Print Screen key).
    .DESCRIPTION
        The application usually runs with administrator rights. Windows then keeps the
        keys pressed in its window away from programs that run without those rights,
        and most screenshot tools do: with the window in front, their Print Screen
        shortcut does nothing. The window therefore takes the picture itself (see
        Get-WindowImage) and puts it on the clipboard, ready to be pasted into a chat,
        an e-mail or a ticket with Ctrl+V.

        Another program can hold the clipboard for a moment, in which case Windows
        refuses the copy; that is reported in the status bar instead of stopping the
        window.

        Returns $true when the picture was copied.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    try {
        $image = Get-WindowImage -Gui $Gui
        if (-not $image) {
            return $false
        }
        Set-ClipboardImage -Image $image
        $Gui.Controls.StatusText.Text = Get-LocalizedText 'A picture of the window was copied. Paste it with Ctrl+V.'
        $true
    }
    catch {
        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'The picture of the window could not be copied: {0}') -f $_.Exception.Message
        $false
    }
}
