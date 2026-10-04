function Receive-AppShowRequest {
    <#
    .SYNOPSIS
        Shows the window when another copy of the application asked for it.
    .DESCRIPTION
        Called once a second by a timer of the window. When a second copy was started
        and left its request (see Send-AppShowRequest), the request is removed and the
        window is brought back from the notification area and to the front.

        Returns $true when there was a request.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $request = Get-AppDataPath -ChildPath 'show.request'
    if (-not (Test-Path -LiteralPath $request -PathType Leaf)) {
        return $false
    }

    try {
        [System.IO.File]::Delete($request)
    }
    catch {
        Write-Verbose "The request file could not be removed: $($_.Exception.Message)"
    }
    Show-WindowFromTray -Gui $Gui -Force
    $true
}
