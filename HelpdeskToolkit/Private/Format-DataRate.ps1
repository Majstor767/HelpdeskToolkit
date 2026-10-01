function Format-DataRate {
    <#
    .SYNOPSIS
        Formats a number of bytes per second, for example "1.2 MB/s" or "9.6 Mbps".
    .DESCRIPTION
        Disk activity is usually read in bytes (KB/s, MB/s) and network speed in bits
        (Kbps, Mbps), the way Task Manager shows them. -AsBits selects the second form.
        The cast to [string] always uses a dot as the decimal separator.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$BytesPerSecond,

        [switch]$AsBits
    )

    if ($AsBits) {
        $bits = $BytesPerSecond * 8
        if ($bits -ge 1e9) { return '{0} Gbps' -f [string][math]::Round($bits / 1e9, 1) }
        if ($bits -ge 1e6) { return '{0} Mbps' -f [string][math]::Round($bits / 1e6, 1) }
        return '{0} Kbps' -f [string][math]::Round($bits / 1e3)
    }

    if ($BytesPerSecond -ge 1GB) { return '{0} GB/s' -f [string][math]::Round($BytesPerSecond / 1GB, 1) }
    if ($BytesPerSecond -ge 1MB) { return '{0} MB/s' -f [string][math]::Round($BytesPerSecond / 1MB, 1) }
    '{0} KB/s' -f [string][math]::Round($BytesPerSecond / 1KB)
}
