function Format-Gigabyte {
    <#
    .SYNOPSIS
        Formats a number of bytes as gigabytes with one decimal, for example "465.1 GB".
    .DESCRIPTION
        The cast to [string] always uses a dot as the decimal separator, so reports
        look the same regardless of the regional settings of the computer.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Bytes
    )

    '{0} GB' -f [string][math]::Round($Bytes / 1GB, 1)
}
