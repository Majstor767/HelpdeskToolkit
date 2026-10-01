function Export-HealthReportHtml {
    <#
    .SYNOPSIS
        Saves a health report as an HTML file and returns the file path.
    .DESCRIPTION
        The file is written as UTF-8 without a byte order mark, the same way on
        Windows PowerShell 5.1 and PowerShell 7.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        # Full path of the file to create.
        [Parameter(Mandatory)]
        [string]$Path
    )

    $html = ConvertTo-HealthReportHtml -Report $Report
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $html, $encoding)

    $Path
}
