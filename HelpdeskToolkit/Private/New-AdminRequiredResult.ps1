function New-AdminRequiredResult {
    <#
    .SYNOPSIS
        Creates the result for a check that was skipped because it needs administrator rights.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds an in-memory object; no system state is changed.')]
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Check
    )

    New-CheckResult -Category $Category -Check $Check -Status Info -Value 'Requires admin' `
        -Recommendation 'Run PowerShell as administrator to include this check.'
}
