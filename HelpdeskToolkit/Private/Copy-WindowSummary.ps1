function Copy-WindowSummary {
    <#
    .SYNOPSIS
        Puts a short text summary of the report on the clipboard.
    .DESCRIPTION
        The text (see ConvertTo-HealthSummaryText) is meant to be pasted into a ticket
        or an e-mail. Another program can hold the clipboard for a moment, in which
        case Windows refuses the copy; that is reported in the status bar instead of
        stopping the window.

        Returns $true when the text was copied.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    if (-not $Gui.Report) {
        return $false
    }

    try {
        Set-Clipboard -Value (ConvertTo-HealthSummaryText -Report $Gui.Report) -ErrorAction Stop
        $Gui.Controls.StatusText.Text = Get-LocalizedText 'The summary was copied. Paste it into the ticket or the e-mail with Ctrl+V.'
        $true
    }
    catch {
        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'The summary could not be copied: {0}') -f $_.Exception.Message
        $false
    }
}
