function Export-HealthReportJson {
    <#
    .SYNOPSIS
        Saves a health report as a JSON file and returns the file path.
    .DESCRIPTION
        The file is written as UTF-8 without a byte order mark. Windows PowerShell 5.1
        adds a BOM with Out-File/Set-Content, and some JSON parsers reject it, so the
        .NET method is used to get identical output on 5.1 and 7.
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

    $json = $Report | ConvertTo-Json -Depth 5
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $json, $encoding)

    $Path
}
