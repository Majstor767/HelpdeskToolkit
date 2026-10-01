function Get-AdministratorGroupMember {
    <#
    .SYNOPSIS
        Returns the names of the accounts in the local Administrators group.
    .DESCRIPTION
        The group is looked up by its security identifier (S-1-5-32-544), because its
        name is translated on non-English Windows. The members are then read through
        the WMI association between a group and its accounts. Works without
        administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $group = Get-CimInstance -ClassName Win32_Group -Filter "SID = 'S-1-5-32-544'" -ErrorAction Stop | Select-Object -First 1
    if (-not $group) {
        return
    }

    # Members can be user accounts and, on domain computers, groups.
    foreach ($class in 'Win32_UserAccount', 'Win32_Group') {
        Get-CimAssociatedInstance -InputObject $group -ResultClassName $class -ErrorAction SilentlyContinue |
            ForEach-Object { [string]$_.Name }
    }
}
