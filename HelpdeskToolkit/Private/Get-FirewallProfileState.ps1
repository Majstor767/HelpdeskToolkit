function Get-FirewallProfileState {
    <#
    .SYNOPSIS
        Returns the name and state of every Windows firewall profile.
    .DESCRIPTION
        A thin wrapper around Get-NetFirewallProfile that reduces its output to the
        two things the security check needs. Enabled is an enum on Windows PowerShell
        5.1, so it is converted to a plain boolean here; comparing it as text works
        on every PowerShell version.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    foreach ($firewallProfile in Get-NetFirewallProfile -ErrorAction Stop) {
        [PSCustomObject]@{
            Name    = [string]$firewallProfile.Name
            Enabled = ([string]$firewallProfile.Enabled -eq 'True')
        }
    }
}
