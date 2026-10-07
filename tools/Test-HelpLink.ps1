<#
.SYNOPSIS
    Asks every address in HelpdeskToolkit\Config\Help.psd1 whether its page still exists.
.DESCRIPTION
    The window links problems to the pages that explain them. Pages move; this script
    requests each address once and lists the ones that are gone, so a dead link is
    found here and not by a user. It needs an internet connection and changes nothing:
    it only reads the pages.

    The script says who it is ("HelpdeskToolkit-LinkCheck") and does not pretend to be
    a browser. A site that refuses a script anyway ("403 Forbidden") tells nothing
    about its page, so such an address comes back as "Refused": it could not be
    checked this way and has to be opened in a browser. "Gone" (404 or 410) is the
    answer that means a page was moved.

    Run it before a release, and after adding an address.
.EXAMPLE
    .\tools\Test-HelpLink.ps1

    Prints one line per address and ends with the number of addresses that failed.
.OUTPUTS
    Objects with Url, Status (the HTTP status code, or 0 when there was no answer),
    Result ("OK", "Gone", "Refused" or "No answer") and Checks (the checks that use the
    address). The exit code is 1 when an address is gone.
#>
[CmdletBinding()]
param(
    # Seconds to wait for one page.
    [ValidateRange(1, 120)]
    [int]$TimeoutSeconds = 20
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Path $PSScriptRoot -Parent
$help = Import-PowerShellDataFile -Path (Join-Path -Path $root -ChildPath 'HelpdeskToolkit\Config\Help.psd1')

# Address -> the checks that use it; an entry that depends on the Windows version has two.
$addresses = @{}
foreach ($key in $help.Pages.Keys) {
    $entry = $help.Pages[$key]
    $urls = if ($entry -is [hashtable]) { @($entry.Values) } else { @($entry) }
    foreach ($url in $urls) {
        if (-not $addresses.ContainsKey($url)) {
            $addresses[$url] = New-Object -TypeName 'System.Collections.Generic.List[string]'
        }
        $addresses[$url].Add($key)
    }
}

# The two addresses that are completed while the application runs, with an example:
# the article of an update that exists, and a search.
$addresses[([string]$help.ArticleUrl -f '5050009')] = [System.Collections.Generic.List[string]]@('ArticleUrl (example: KB5050009)')
$addresses[(([string]$help.SearchUrl) -f 'Windows%20event%20ID%2041')] = [System.Collections.Generic.List[string]]@('SearchUrl (example)')

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$results = foreach ($url in ($addresses.Keys | Sort-Object)) {
    $status = 0
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec $TimeoutSeconds -MaximumRedirection 5 -UserAgent 'HelpdeskToolkit-LinkCheck'
        $status = [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.PSObject.Properties['Response'] -and $_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        Write-Verbose "$url : $($_.Exception.Message)"
    }

    [PSCustomObject]@{
        Url    = $url
        Status = $status
        Result = switch ($status) {
            200 { 'OK' }
            404 { 'Gone' }
            410 { 'Gone' }
            0 { 'No answer' }
            default { 'Refused' }
        }
        Checks = ($addresses[$url] | Sort-Object) -join ', '
    }
}

$results
$gone = @($results | Where-Object { $_.Result -eq 'Gone' })
$unchecked = @($results | Where-Object { $_.Result -in 'Refused', 'No answer' })
Write-Information -MessageData ('{0} addresses asked: {1} gone, {2} could not be checked by a script.' -f @($results).Count, $gone.Count, $unchecked.Count) -InformationAction Continue
if ($gone.Count -gt 0) {
    exit 1
}
