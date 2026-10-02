function Switch-WindowAdvice {
    <#
    .SYNOPSIS
        Opens the advice of a tile of the Live monitor, or closes it when it is open.
    .DESCRIPTION
        The action of the warning triangle on a tile. Only one advice is open at a
        time: opening another one replaces it.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The tile the triangle belongs to.
        [Parameter(Mandatory)]
        [ValidateSet('Cpu', 'Memory', 'Gpu')]
        [string]$Name
    )

    $Gui.MonitorAdvice = if ($Gui.MonitorAdvice -eq $Name) { '' } else { $Name }
    Show-WindowAdvice -Gui $Gui
}
