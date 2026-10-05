function Get-AutoCheckInterval {
    <#
    .SYNOPSIS
        Returns after how many minutes the application repeats the health check by itself.
    .DESCRIPTION
        The setting AutoCheckMinutes says how often the check is repeated while
        somebody looks at the window. A check keeps the processor and the drives busy
        for a few seconds, so it is repeated less often where that costs more than it
        brings:

        - window on the screen, on mains power:  as the setting says
        - window on the screen, on battery:      every 15 minutes at most
        - window hidden next to the clock:       every 30 minutes at most
        - hidden and on battery:                 every 60 minutes at most

        A setting that is already slower than that stays as it is, and 0 ("Never")
        stays 0. "Run check" in the window and "Run check now" in the menu of the icon
        next to the clock check at once in every case.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $minutes = [int]$Gui.Settings.AutoCheckMinutes
    if ($minutes -le 0) {
        return 0
    }

    $hidden = [bool]$Gui['Hidden']
    $battery = Test-OnBattery
    $least = if ($hidden -and $battery) {
        60
    }
    elseif ($hidden) {
        30
    }
    elseif ($battery) {
        15
    }
    else {
        0
    }

    [math]::Max($minutes, $least)
}
