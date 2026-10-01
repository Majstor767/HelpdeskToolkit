function Test-HttpsEndpoint {
    <#
    .SYNOPSIS
        Tests whether a web address can be reached over HTTPS.
    .DESCRIPTION
        Sends a HEAD request, so only the headers are transferred. Any HTTP answer,
        including an error status such as 403, proves that DNS, routing and TLS all
        work; only "no answer at all" counts as a failure.
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
        [PSCustomObject]@{
            Success = $true
            Detail  = 'HTTP {0}' -f [int]$response.StatusCode
        }
    }
    catch {
        # The exception type differs between 5.1 and 7, but both expose the server
        # answer in a Response property when there was one.
        $responseProperty = $_.Exception.PSObject.Properties['Response']
        if ($responseProperty -and $responseProperty.Value) {
            [PSCustomObject]@{
                Success = $true
                Detail  = 'HTTP {0}' -f [int]$responseProperty.Value.StatusCode
            }
        }
        else {
            [PSCustomObject]@{
                Success = $false
                Detail  = $_.Exception.Message
            }
        }
    }
}
