function Receive-WindowDiskUsage {
    <#
    .SYNOPSIS
        Picks up the finished measurements of what takes up the space of the drives.
    .DESCRIPTION
        Called by the timer of the Live monitor a few times per second. For every
        drive whose background measurement (see Invoke-WindowDiskUsage) has ended, the
        result is stored, the runspace is released and the list of the drives is
        drawn again. A measurement that failed is reported in the list of that drive.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $changed = $false

    foreach ($drive in @($Gui.DiskUsage.Keys)) {
        $usage = $Gui.DiskUsage[$drive]
        if (-not $usage.Worker -or -not $usage.Handle.IsCompleted) {
            continue
        }

        try {
            $detail = @($usage.Worker.EndInvoke($usage.Handle)) | Where-Object { $_ -and $_.PSObject.Properties['Programs'] } | Select-Object -Last 1
            if (-not $detail) {
                $reason = if ($usage.Worker.Streams.Error.Count -gt 0) { $usage.Worker.Streams.Error[0].ToString() } else { 'Nothing was returned.' }
                throw $reason
            }
            $usage.Detail = $detail
            $usage.State = 'Done'
        }
        catch {
            $usage.Error = $_.Exception.Message
            $usage.State = 'Failed'
        }
        finally {
            $usage.Worker.Dispose()
            $usage.Worker = $null
            $usage.Handle = $null
        }
        $changed = $true
    }

    if ($changed) {
        Show-WindowVolume -Gui $Gui
    }
}
