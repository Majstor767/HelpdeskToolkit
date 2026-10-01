function Test-PingHost {
    <#
    .SYNOPSIS
        Pings a host and returns whether it answered and the average response time.
    .DESCRIPTION
        Test-Connection has different parameters and output on Windows PowerShell 5.1
        and PowerShell 7. The .NET Ping class behaves the same on both, so it is used
        directly.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Target,

        [ValidateRange(1, 10)]
        [int]$Count = 2,

        [int]$TimeoutMs = 2000
    )

    $times = @()
    $ping = New-Object -TypeName System.Net.NetworkInformation.Ping
    try {
        for ($i = 0; $i -lt $Count; $i++) {
            try {
                $reply = $ping.Send($Target, $TimeoutMs)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $times += $reply.RoundtripTime
                }
            }
            catch {
                Write-Verbose "Ping to $Target failed: $($_.Exception.Message)"
            }
        }
    }
    finally {
        $ping.Dispose()
    }

    $average = if ($times.Count -gt 0) { [int][math]::Round(($times | Measure-Object -Average).Average) } else { $null }

    # Replies on a local network often take less than a millisecond.
    $text = if ($null -eq $average) { '' } elseif ($average -lt 1) { 'under 1 ms' } else { '{0} ms' -f $average }

    [PSCustomObject]@{
        Success   = $times.Count -gt 0
        AverageMs = $average
        Text      = $text
    }
}
