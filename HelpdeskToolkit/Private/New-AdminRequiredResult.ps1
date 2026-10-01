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
        -Recommendation 'Windows only shows this to administrators. Start the tool as administrator to include it: in the window use "Restart as administrator", in a console open PowerShell with "Run as administrator".'
}
