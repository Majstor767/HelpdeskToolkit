function Get-HealthSummary {
    <#
    .SYNOPSIS
        Counts check results per status.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Result
    )

    $summary = [ordered]@{
        OK       = 0
        Warning  = 0
        Critical = 0
        Info     = 0
    }

    foreach ($item in $Result) {
        $summary[$item.Status]++
    }

    $summary
}
