function Get-ReportFileName {
    <#
    .SYNOPSIS
        Returns the file name (without extension) under which a report is saved.
    .DESCRIPTION
        The name contains the computer name and the time of the run, for example
        PCHealth_FIN-LT-014_20260930-091452, so reports of several computers and runs
        can be kept in one folder and sort by time.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report
    )

    # GeneratedAt is "yyyy-MM-dd HH:mm:ss"; the file name uses the same moment without separators.
    $stamp = $Report.GeneratedAt -replace '[-:]', '' -replace ' ', '-'
    'PCHealth_{0}_{1}' -f $Report.ComputerName, $stamp
}
