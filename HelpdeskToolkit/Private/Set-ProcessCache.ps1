function Set-ProcessCache {
    <#
    .SYNOPSIS
        Remembers a value in the memory of this process, with the time it was measured.
    .DESCRIPTION
        The counterpart of Get-ProcessCache, which explains what the cache is for and
        where it lives. Only the memory of the application changes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only keeps a value in the memory of the process; no system state is changed.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Value
    )

    [System.AppDomain]::CurrentDomain.SetData("HelpdeskToolkit:$Key", @{ At = Get-Date; Value = $Value })
}
