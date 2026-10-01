function Invoke-CheckAction {
    <#
    .SYNOPSIS
        Opens the place in Windows where the problem of a check is fixed.
    .DESCRIPTION
        Starts what Get-CheckAction found for the check: a page of the Settings app
        ("ms-settings:..."), a management console (".msc") or a system tool. The
        application itself still changes nothing; it only brings the user to the right
        place, where the user decides what to do.

        Returns $true when something was opened and $false when the check has no such
        place or Windows could not open it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Category = ''
    )

    $action = Get-CheckAction -Check $Check -Category $Category
    if (-not $action) {
        return $false
    }

    try {
        if ($action.Arguments) {
            Start-Process -FilePath $action.Target -ArgumentList $action.Arguments -ErrorAction Stop
        }
        else {
            Start-Process -FilePath $action.Target -ErrorAction Stop
        }
        $true
    }
    catch {
        Write-Verbose "Could not open $($action.Target): $($_.Exception.Message)"
        $false
    }
}
