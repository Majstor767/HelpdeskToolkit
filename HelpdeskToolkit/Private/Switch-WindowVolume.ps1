function Switch-WindowVolume {
    <#
    .SYNOPSIS
        Opens or closes "What takes up the space" of a drive in the Live monitor.
    .DESCRIPTION
        The action of the line below the meter of a drive. Opening it for the first
        time starts the measurement in the background (see Invoke-WindowDiskUsage);
        the result is kept, so closing and opening the line again shows it at once.
        With -Refresh (the button "Measure again") the drive is measured anew.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Drive letter with colon, for example "C:".
        [Parameter(Mandatory)]
        [string]$Drive,

        [switch]$Refresh
    )

    $usage = $Gui.DiskUsage[$Drive]
    if (-not $usage) {
        $usage = @{ Expanded = $false; State = 'None'; Detail = $null; Error = ''; Worker = $null; Handle = $null }
        $Gui.DiskUsage[$Drive] = $usage
    }

    if ($Refresh) {
        # A measurement that is under way is simply waited for.
        if ($usage.State -ne 'Loading') {
            $usage.State = 'None'
        }
    }
    else {
        $usage.Expanded = -not $usage.Expanded
    }

    if ($usage.Expanded -and $usage.State -in 'None', 'Failed') {
        Invoke-WindowDiskUsage -Gui $Gui -Drive $Drive
    }

    Show-WindowVolume -Gui $Gui
}
