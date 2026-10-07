function Get-BatteryCapacity {
    <#
    .SYNOPSIS
        Returns how much charge the battery could hold when it was new and how much it holds now.
    .DESCRIPTION
        A battery loses capacity with every charge. The firmware of a laptop reports
        both numbers in mWh, and often also how many times the battery was charged.

        Returns one object per battery with DesignedCapacity, FullChargedCapacity and
        CycleCount ($null when the battery does not count cycles), or nothing on a
        computer without a battery. A battery that reports no usable capacity is
        left out. No administrator rights are needed.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $static = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryStaticData -ErrorAction SilentlyContinue)
    $full = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue)
    $cycles = @(Get-CimInstance -Namespace 'root/wmi' -ClassName BatteryCycleCount -ErrorAction SilentlyContinue)

    for ($i = 0; $i -lt $static.Count; $i++) {
        if ($i -ge $full.Count) {
            continue
        }
        # A battery that does not know a capacity reports 0 or the largest number there
        # is (0xFFFFFFFF). Neither says anything about its health.
        $designed = [double]$static[$i].DesignedCapacity
        $charged = [double]$full[$i].FullChargedCapacity
        if ($designed -le 0 -or $charged -le 0 -or $designed -ge 4294967000 -or $charged -ge 4294967000) {
            continue
        }

        $cycleCount = if ($i -lt $cycles.Count -and $cycles[$i].CycleCount -gt 0) { [int]$cycles[$i].CycleCount } else { $null }
        [PSCustomObject]@{
            DesignedCapacity    = [long]$static[$i].DesignedCapacity
            FullChargedCapacity = [long]$full[$i].FullChargedCapacity
            CycleCount          = $cycleCount
        }
    }
}
