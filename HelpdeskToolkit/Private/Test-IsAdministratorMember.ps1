function Test-IsAdministratorMember {
    <#
    .SYNOPSIS
        Returns $true when the current user belongs to the local Administrators group.
    .DESCRIPTION
        This is not the same as Test-IsAdministrator. With User Account Control on, an
        administrator works with a restricted token until a program is started "as
        administrator": the session is not elevated, yet the account is still an
        administrator. In that restricted token the group is present but marked
        "deny only", so both the normal groups and the claims of the identity are checked.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Well-known security identifier of the local Administrators group.
    $administrators = 'S-1-5-32-544'
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()

    $inGroups = [bool]($identity.Groups | Where-Object { $_.Value -eq $administrators })
    $inClaims = [bool]($identity.Claims | Where-Object { $_.Value -eq $administrators })

    $inGroups -or $inClaims
}
