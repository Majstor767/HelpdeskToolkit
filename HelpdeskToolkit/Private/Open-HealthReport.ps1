function Open-HealthReport {
    <#
    .SYNOPSIS
        Opens a saved HTML report in the web browser.
    .DESCRIPTION
        The report is opened with the default web browser. That is deliberately not
        the same as "the program associated with .html files": that association can
        point to an editor, or be broken, while the default browser is what the user
        expects a report to open in.

        If the browser cannot be determined, the file association is used as a
        fallback. If that fails as well, a warning tells the user where the file is.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $browser = Get-DefaultBrowserPath
    if ($browser) {
        try {
            # A file URI (file:///C:/...) is understood by every browser and survives spaces in the path.
            $uri = ([System.Uri]$Path).AbsoluteUri
            Start-Process -FilePath $browser -ArgumentList ('"{0}"' -f $uri) -ErrorAction Stop
            return
        }
        catch {
            Write-Verbose "Could not start the default browser: $($_.Exception.Message)"
        }
    }

    try {
        Invoke-Item -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        Write-Warning ('The report was saved but could not be opened automatically. Open it manually: {0}' -f $Path)
    }
}
