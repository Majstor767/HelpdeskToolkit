function Invoke-CheckAction {
    <#
    .SYNOPSIS
        Opens the place in Windows where the problem of a check is fixed.
    .DESCRIPTION
        Starts what Get-CheckAction found for the check: a page of the Settings app
        ("ms-settings:..."), a management console (".msc"), a system tool, or the
        support page of the maker of the computer in the default browser. The
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

        [string]$Category = '',

        # The value of the result, for places that depend on it (see Get-CheckAction).
        [string]$Value = ''
    )

    $action = Get-CheckAction -Check $Check -Category $Category -Value $Value
    if (-not $action) {
        return $false
    }

    try {
        if ($action.Target -match '^https://') {
            # A web page, such as the support page of the maker of the computer
            return (Open-WebAddress -Url $action.Target)
        }
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
