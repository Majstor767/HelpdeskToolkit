function Get-PdfBrowserPath {
    <#
    .SYNOPSIS
        Returns the path of a browser that can turn an HTML file into a PDF.
    .DESCRIPTION
        Microsoft Edge and Google Chrome can both print a page to a PDF file without
        opening a window. Edge is part of Windows 10 and 11, so it is looked for first;
        Chrome is the fallback. Only the usual installation folders are searched.

        Returns nothing when neither browser is found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $relativePaths = 'Microsoft\Edge\Application\msedge.exe', 'Google\Chrome\Application\chrome.exe'

    foreach ($relative in $relativePaths) {
        foreach ($folder in ${env:ProgramFiles(x86)}, $env:ProgramFiles, $env:LOCALAPPDATA) {
            if (-not $folder) {
                continue
            }
            $candidate = Join-Path -Path $folder -ChildPath $relative
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }
}
