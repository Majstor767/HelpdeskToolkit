function Get-ThresholdStatus {
    <#
    .SYNOPSIS
        Compares a measured value with its limits and returns OK, Warning or Critical.
    .DESCRIPTION
        By default a higher value is worse (CPU load, uptime, error count): the status
        is Warning above -Warning and Critical above -Critical.

        With -LowerIsWorse the comparison is reversed (free disk space, battery charge):
        Warning below -Warning and Critical below -Critical.

        -Critical is optional for checks that only have a warning level.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Value,

        [Parameter(Mandatory)]
        [double]$Warning,

        [Nullable[double]]$Critical,

        [switch]$LowerIsWorse
    )

    if ($LowerIsWorse) {
        if ($null -ne $Critical -and $Value -lt $Critical) { return 'Critical' }
        if ($Value -lt $Warning) { return 'Warning' }
    }
    else {
        if ($null -ne $Critical -and $Value -gt $Critical) { return 'Critical' }
        if ($Value -gt $Warning) { return 'Warning' }
    }

    'OK'
}
