function Get-DefenderStatus {
    <#
    .SYNOPSIS
        Returns the Microsoft Defender status object.
    .DESCRIPTION
        A thin wrapper around Get-MpComputerStatus. The cmdlet belongs to the Defender
        module, which is not present on every Windows installation; keeping the call
        in one place lets the tests replace it without needing that module.
    #>
    [CmdletBinding()]
    param()

    Get-MpComputerStatus -ErrorAction Stop
}
