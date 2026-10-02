function Format-ByteSize {
    <#
    .SYNOPSIS
        Formats a number of bytes in the unit that suits its size, for example "512 KB", "20 MB" or "1.3 GB".
    .DESCRIPTION
        Gigabytes get one decimal (see Format-Gigabyte); megabytes and kilobytes are
        whole numbers. The cast to [string] always uses a dot as the decimal separator.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return Format-Gigabyte -Bytes $Bytes
    }
    if ($Bytes -ge 1MB) {
        return '{0} MB' -f [string][math]::Round($Bytes / 1MB)
    }
    '{0} KB' -f [string][math]::Round($Bytes / 1KB)
}
