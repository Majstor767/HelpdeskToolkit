function New-FailureResult {
    <#
    .SYNOPSIS
        Turns an error caught inside a check into a result object.
    .DESCRIPTION
        Keeps error handling identical in every check: a permission problem becomes
        "Requires admin", anything else becomes a Warning that carries the error text.
        The report is then still produced even when a single data source is broken.
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
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    if (Test-AccessDenied -ErrorRecord $ErrorRecord) {
        New-AdminRequiredResult -Category $Category -Check $Check
        return
    }

    New-CheckResult -Category $Category -Check $Check -Status Warning -Value 'Unavailable' `
        -Recommendation ('The information could not be read: {0}' -f $ErrorRecord.Exception.Message.Trim())
}
