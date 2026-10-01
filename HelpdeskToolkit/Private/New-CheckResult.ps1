function New-CheckResult {
    <#
    .SYNOPSIS
        Creates the standard result object returned by every health check.
    .DESCRIPTION
        Every check in the module reports through this function, so the console
        summary, the JSON export and the HTML report can all rely on the same shape.

        Allowed and Typical are only filled in for measurements (CPU load, free disk
        space, ping time and so on). They give the reader something to compare the
        measured value with: the range that still counts as OK and the value that is
        usual for a healthy computer.
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

        # Range of values that is reported as OK, for example "0 - 85 %".
        [AllowEmptyString()]
        [string]$Allowed = '',

        # Usual value on a healthy computer, for comparison only.
        [AllowEmptyString()]
        [string]$Typical = '',

        [AllowEmptyString()]
        [string]$Recommendation = ''
    )

    [PSCustomObject]@{
        PSTypeName     = 'HelpdeskToolkit.CheckResult'
        Category       = $Category
        Check          = $Check
        Status         = $Status
        Value          = $Value
        Allowed        = $Allowed
        Typical        = $Typical
        Recommendation = $Recommendation
    }
}
