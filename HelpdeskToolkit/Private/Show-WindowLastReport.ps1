function Show-WindowLastReport {
    <#
    .SYNOPSIS
        Shows the report of the last check in the window that has just opened.
    .DESCRIPTION
        A check takes a while. Instead of an empty window, the application shows what
        the last check of this computer found (see Get-LastHealthReport), so the pages
        can be read at once; the new results take its place when they are there.

        That the report is an older one is said in the status bar, and the header shows
        when it was made. $Gui.StaleReport is set, so the check that follows knows that
        its results replace a report somebody may be reading (see Receive-WindowCheck).

        Returns $true when a report was shown.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    # A report is on the screen already.
    if ($Gui.Report) {
        return $false
    }

    $report = Get-LastHealthReport
    if (-not $report) {
        return $false
    }

    Show-WindowReport -Gui $Gui -Report $report
    $Gui.StaleReport = $true
    $Gui.Controls.StatusText.Text = (Get-LocalizedText 'These are the results of the last check ({0}). They are replaced as soon as a new check has finished.') -f $report.GeneratedAt
    $true
}
