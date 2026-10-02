function Receive-WindowComponentDetail {
    <#
    .SYNOPSIS
        Picks up what was read about the components, and has the open one read again when it is time.
    .DESCRIPTION
        Called by the timer of the Live monitor a few times per second.

        - For every component whose background reading (see Invoke-WindowComponentDetail)
          has ended, the result is stored and the runspace is released. A reading that
          failed keeps the sections of the one before and is reported on the page.
        - The component whose page is open is read again when its last reading ended
          longer ago than DetailRefreshSeconds (Config\Thresholds.psd1), so counters
          such as "page faults per second" stay current. Not while the user has paused
          the monitor: a paused page must not change.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $open = $Gui.MonitorComponent
    $changed = $false

    foreach ($name in @($Gui.ComponentDetail.Keys)) {
        $state = $Gui.ComponentDetail[$name]
        if (-not $state.Worker -or -not $state.Handle.IsCompleted) {
            continue
        }

        try {
            $detail = @($state.Worker.EndInvoke($state.Handle)) | Where-Object { $_ -and $_.PSObject.Properties['Sections'] } | Select-Object -Last 1
            if (-not $detail) {
                $reason = if ($state.Worker.Streams.Error.Count -gt 0) { $state.Worker.Streams.Error[0].ToString() } else { 'Nothing was returned.' }
                throw $reason
            }
            $state.Detail = $detail
            $state.Error = ''
            $state.State = 'Done'
        }
        catch {
            $state.Error = $_.Exception.Message
            $state.State = 'Failed'
        }
        finally {
            $state.Worker.Dispose()
            $state.Worker = $null
            $state.Handle = $null
            $state.FinishedAt = Get-Date
        }

        if ($name -eq $open) {
            $changed = $true
        }
    }

    if ($changed) {
        Show-WindowComponentDetail -Gui $Gui
    }

    # Time to read the open component again?
    if ($open -and -not $Gui.MonitorUserPaused) {
        $state = $Gui.ComponentDetail[$open]
        if ($state -and $state.State -in 'Done', 'Failed' -and -not $state.Worker -and $state.FinishedAt) {
            $seconds = [int](Get-HealthThreshold).Monitor.DetailRefreshSeconds
            if (((Get-Date) - $state.FinishedAt).TotalSeconds -ge $seconds) {
                Invoke-WindowComponentDetail -Gui $Gui -Name $open
            }
        }
    }
}
