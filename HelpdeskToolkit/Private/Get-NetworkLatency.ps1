function Get-NetworkLatency {
    <#
    .SYNOPSIS
        Measures how quickly the router and the internet answer right now.
    .DESCRIPTION
        Sends one ping each to the default gateway (the router) and to the address of
        the internet connectivity test (Network.PingTarget in Config\Thresholds.psd1).
        The two together tell where a slow or broken connection sits:

        router slow or silent       the problem is in the local network (Wi-Fi, cable)
        router fine, internet not   the problem is with the provider or beyond

        Both pings are sent at the same time and waited for together, so a connection
        that is down costs one timeout, not two.

        Returns an object with Gateway and Internet (the addresses; Gateway is empty
        when the computer has none) and GatewayMs and InternetMs (the answer times in
        milliseconds; nothing when no answer came in time).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateRange(100, 10000)]
        [int]$TimeoutMs = 1000
    )

    $gateway = ''
    try {
        $found = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled = True' -ErrorAction Stop |
            ForEach-Object { $_.DefaultIPGateway } | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
        if ($found) {
            $gateway = [string]$found
        }
    }
    catch {
        Write-Verbose "The default gateway could not be read: $($_.Exception.Message)"
    }
    $internet = [string](Get-HealthThreshold).Network.PingTarget

    $pings = @()
    $tasks = @{}
    try {
        foreach ($target in @($gateway, $internet) | Where-Object { $_ } | Select-Object -Unique) {
            $ping = New-Object -TypeName System.Net.NetworkInformation.Ping
            $pings += $ping
            $tasks[$target] = $ping.SendPingAsync($target, $TimeoutMs)
        }

        try {
            [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tasks.Values), $TimeoutMs + 500)
        }
        catch {
            # A ping that cannot even be sent (no network at all) ends as a failed task.
            Write-Verbose "A ping failed: $($_.Exception.Message)"
        }

        $time = {
            param([string]$Target)
            if (-not $Target -or -not $tasks.ContainsKey($Target)) {
                return
            }
            $task = $tasks[$Target]
            if ($task.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion -and
                $task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                [int]$task.Result.RoundtripTime
            }
        }

        [PSCustomObject]@{
            Gateway    = $gateway
            GatewayMs  = & $time $gateway
            Internet   = $internet
            InternetMs = & $time $internet
        }
    }
    finally {
        foreach ($ping in $pings) {
            $ping.Dispose()
        }
    }
}
