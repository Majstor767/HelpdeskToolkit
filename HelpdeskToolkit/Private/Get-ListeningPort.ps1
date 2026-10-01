function Get-ListeningPort {
    <#
    .SYNOPSIS
        Returns the TCP ports on which programs of this computer wait for connections.
    .DESCRIPTION
        A program that "listens" on a port can be reached by other computers, unless
        the firewall blocks it or the program only listens on the loopback address
        (127.0.0.1 or ::1), which is reachable from this computer alone.

        Returns one object per port with Port, Process and LocalOnly, sorted by port.
        A port that is open on several addresses is returned once. No administrator
        rights are needed; nothing is sent over the network.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $connections = @(Get-NetTCPConnection -State Listen -ErrorAction Stop)

    # Process names by process id, read once
    $names = @{}
    foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
        $names[[int]$process.Id] = $process.ProcessName
    }

    foreach ($group in ($connections | Group-Object -Property LocalPort | Sort-Object -Property { [int]$_.Name })) {
        $first = $group.Group | Select-Object -First 1
        $name = $names[[int]$first.OwningProcess]
        $loopback = @($group.Group | Where-Object { $_.LocalAddress -in '127.0.0.1', '::1' })

        [PSCustomObject]@{
            Port      = [int]$group.Name
            Process   = if ($name) { $name } else { 'unknown' }
            LocalOnly = $loopback.Count -eq $group.Count
        }
    }
}
