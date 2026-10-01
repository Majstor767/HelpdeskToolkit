function Export-WindowReport {
    <#
    .SYNOPSIS
        Saves the report shown in the window to a file; the format follows the file extension.
    .DESCRIPTION
        Used by the "Open HTML report" and "Save as..." buttons. The extension of the
        path decides the format: .json, .csv and .pdf, and HTML for everything else.
        The folder is created when it does not exist.

        The outcome is written into the status bar. Returns the path of the file, or
        nothing when saving failed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Full path of the file to create.
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $folder = Split-Path -Path $Path -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }

        $saved = switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
            '.json' { Export-HealthReportJson -Report $Gui.Report -Path $Path }
            '.csv' { Export-HealthReportCsv -Report $Gui.Report -Path $Path }
            '.pdf' { Export-HealthReportPdf -Report $Gui.Report -Path $Path }
            default { Export-HealthReportHtml -Report $Gui.Report -Path $Path }
        }

        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'Report saved: {0}') -f $saved
        $saved
    }
    catch {
        $Gui.Controls.StatusText.Text = (Get-LocalizedText 'The report could not be saved: {0}') -f $_.Exception.Message
    }
}
