function New-CheckResult {
    <#
    .SYNOPSIS
        Creates the standard result object returned by every health check.
    .DESCRIPTION
        Every check in the module reports through this function, so the console
        summary, the JSON export and the HTML report can all rely on the same shape.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds an in-memory object; no system state is changed.')]
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Check,

        [Parameter(Mandatory)]
        [ValidateSet('OK', 'Warning', 'Critical', 'Info')]
        [string]$Status,

        [AllowEmptyString()]
        [string]$Value = '',

        [AllowEmptyString()]
        [string]$Recommendation = ''
    )

    [PSCustomObject]@{
        PSTypeName     = 'HelpdeskToolkit.CheckResult'
        Category       = $Category
        Check          = $Check
        Status         = $Status
        Value          = $Value
        Recommendation = $Recommendation
    }
}
