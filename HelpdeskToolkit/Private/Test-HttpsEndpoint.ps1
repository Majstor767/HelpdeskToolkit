function Test-HttpsEndpoint {
    <#
    .SYNOPSIS
        Tests whether a web address can be reached over HTTPS.
    .DESCRIPTION
        Sends a HEAD request, so only the headers are transferred. Any HTTP answer,
        including an error status such as 403, proves that DNS, routing and TLS all
        work; only "no answer at all" counts as a failure.

        Returns an object with Success, Detail and ServerTime. ServerTime is the time
        the server put into its "Date" header (in UTC), or nothing when it is not
        available; the network check uses it to judge the clock of the computer.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [int]$TimeoutSec = 10
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop

        # The header is a string on Windows PowerShell 5.1 and a list of strings on
        # PowerShell 7; taking the first element works for both.
        $serverTime = $null
        try {
            $dateHeader = @($response.Headers['Date'])[0]
            if ($dateHeader) {
                $serverTime = [datetime]::Parse($dateHeader, [cultureinfo]::InvariantCulture).ToUniversalTime()
            }
        }
        catch {
            Write-Verbose "Could not read the server time: $($_.Exception.Message)"
        }

        [PSCustomObject]@{
            Success    = $true
            Detail     = 'HTTP {0}' -f [int]$response.StatusCode
            ServerTime = $serverTime
        }
    }
    catch {
        # The exception type differs between 5.1 and 7, but both expose the server
        # answer in a Response property when there was one.
        $responseProperty = $_.Exception.PSObject.Properties['Response']
        if ($responseProperty -and $responseProperty.Value) {
            [PSCustomObject]@{
                Success    = $true
                Detail     = 'HTTP {0}' -f [int]$responseProperty.Value.StatusCode
                ServerTime = $null
            }
        }
        else {
            [PSCustomObject]@{
                Success    = $false
                Detail     = $_.Exception.Message
                ServerTime = $null
            }
        }
    }
}
