function Get-DefenderThreat {
    <#
    .SYNOPSIS
        Returns the threats Microsoft Defender has found on this computer.
    .DESCRIPTION
        A thin wrapper around Get-MpThreat, so the tests can replace it without the
        Defender module. Returns one object per threat with Name and IsActive; nothing
        when Defender has never found anything.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    foreach ($threat in Get-MpThreat -ErrorAction Stop) {
        [PSCustomObject]@{
            Name     = [string]$threat.ThreatName
            IsActive = [bool]$threat.IsActive
        }
    }
}
