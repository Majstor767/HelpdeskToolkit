function New-CheckResult {
    <#
    .SYNOPSIS
        Creates the standard result object returned by every health check.
    .DESCRIPTION
        Every check in the module reports through this function, so the console
        summary, the JSON export and the HTML report can all rely on the same shape.

        Description explains what the checked thing is. It is looked up by check name
        in Config\Descriptions.psd1 unless it is passed explicitly.

        Details holds the items that do not fit into Value (for example the rest of a
        long list); the HTML report shows them in an expandable section.

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

        # What the checked thing is and what it does. Looked up by check name when omitted.
        [AllowEmptyString()]
        [string]$Description = '',

        # Additional items shown on demand, for example the rest of a long list.
        [AllowEmptyCollection()]
        [string[]]$Details = @(),

        # Range of values that is reported as OK, for example "0 - 85 %".
        [AllowEmptyString()]
        [string]$Allowed = '',

        # Usual value on a healthy computer, for comparison only.
        [AllowEmptyString()]
        [string]$Typical = '',

        [AllowEmptyString()]
        [string]$Recommendation = ''
    )

    if (-not $Description) {
        $Description = Get-CheckDescription -Key $Check
    }

    [PSCustomObject]@{
        PSTypeName     = 'HelpdeskToolkit.CheckResult'
        Category       = $Category
        Check          = $Check
        Description    = $Description
        Status         = $Status
        Value          = $Value
        # Empty entries are dropped so a null or blank item never counts as a detail.
        Details        = @($Details | Where-Object { $_ })
        Allowed        = $Allowed
        Typical        = $Typical
        Recommendation = $Recommendation
    }
}
