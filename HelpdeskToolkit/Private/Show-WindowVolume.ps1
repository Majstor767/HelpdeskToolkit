function Show-WindowVolume {
    <#
    .SYNOPSIS
        Draws the drive letters of the Live monitor: used space and, when opened, what takes it up.
    .DESCRIPTION
        Every drive letter is a line with a meter. The meter takes the colors of the
        disk space check: the same limits from Config\Thresholds.psd1 decide between
        normal, warning and critical.

        Below the meter is the line "What takes up the space", which opens a list of
        the largest programs and folders of the drive (see Switch-WindowVolume and
        Get-DiskUsageDetail). The list comes with buttons that open the pages of
        Windows where a program is removed and where files are cleaned up; the
        application itself removes nothing.

        With -Volume the drives of a new measurement are stored and shown; without it
        the stored ones are drawn again (after a click, or when a measurement of the
        space has ended).

        The list is only rebuilt when something in it has changed. Rebuilding it with
        every measurement would close a tooltip and interrupt a click.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The Volumes of a snapshot, as returned by Get-PerformanceSnapshot.
        [AllowEmptyCollection()]
        [object[]]$Volume
    )

    if ($PSBoundParameters.ContainsKey('Volume')) {
        $Gui.MonitorVolumes = @($Volume | Where-Object { $_ })
    }

    $separator = '  |  '
    $diskLimits = (Get-HealthThreshold).Disk

    # Megabytes below one gigabyte; "or more" when the measuring was cut short.
    $toSize = {
        param($Entry)
        $text = if ([double]$Entry.Bytes -ge 1GB) { Format-Gigabyte -Bytes $Entry.Bytes } else { '{0} MB' -f [string][math]::Round([double]$Entry.Bytes / 1MB) }
        if ($Entry.Complete) { $text } else { (Get-LocalizedText '{0} or more') -f $text }
    }

    $signature = @()
    $items = foreach ($entry in @($Gui.MonitorVolumes)) {
        $drive = [string]$entry.Name
        $freePercent = 100 - $entry.Percent
        $level = if ($freePercent -lt $diskLimits.CriticalFreePercent) { 'Critical' } elseif ($freePercent -lt $diskLimits.WarningFreePercent) { 'Warning' } else { 'Normal' }
        $text = ((Get-LocalizedText '{0} % used') -f $entry.Percent) + $separator +
            ((Get-LocalizedText '{0} free of {1}') -f (Format-Gigabyte -Bytes $entry.FreeBytes), (Format-Gigabyte -Bytes $entry.TotalBytes))

        $usage = $Gui.DiskUsage[$drive]
        $expanded = [bool]($usage -and $usage.Expanded)
        $state = ''
        $note = ''
        $programs = @()
        $folders = @()
        $lists = ''

        if ($expanded) {
            switch ($usage.State) {
                'Done' {
                    $detail = $usage.Detail
                    $state = (Get-LocalizedText 'Measured at {0:HH:mm}. The {1} programs installed on this drive take up {2}.') -f
                        $detail.MeasuredAt, $detail.ProgramCount, (Format-Gigabyte -Bytes $detail.ProgramBytes)
                    $programs = @($detail.Programs | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Text = & $toSize $_ } })
                    $folders = @($detail.Folders | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Text = & $toSize $_ } })
                    $lists = 'Show'

                    $notes = @(Get-LocalizedText 'To remove a program, open Installed apps, choose it there and click Uninstall. This application itself removes nothing.')
                    if ($detail.UnknownCount -gt 0) {
                        $notes += (Get-LocalizedText 'Programs that do not say how large they are: {0}.') -f $detail.UnknownCount
                    }
                    if (-not $detail.IsElevated) {
                        $notes += Get-LocalizedText 'Without administrator rights, the folders of Windows and of other users are only measured as far as they can be read.'
                    }
                    $note = $notes -join ' '
                }
                'Failed' {
                    $state = (Get-LocalizedText 'The space could not be measured: {0}') -f $usage.Error
                }
                default {
                    $state = Get-LocalizedText 'Measuring ... this can take up to half a minute.'
                }
            }
        }

        $signature += $drive, $text, $expanded, $state, $programs.Count, $folders.Count -join '|'

        [PSCustomObject]@{
            Drive      = $drive
            Name       = if ($entry.Label) { '{0} {1}' -f $drive, $entry.Label } else { $drive }
            Percent    = [double]$entry.Percent
            Level      = $level
            Text       = $text
            ToggleText = (Get-LocalizedText 'What takes up the space on {0}') -f $drive
            Expanded   = $expanded
            # Empty hides the box below the line.
            Details    = if ($expanded) { 'Open' } else { '' }
            State      = $state
            # Empty hides the two lists while there is nothing to list.
            Lists      = $lists
            Programs   = $programs
            Folders    = $folders
            Note       = $note
        }
    }

    $signature = $signature -join "`n"
    if ($signature -ne $Gui.VolumeSignature -or $null -eq $Gui.Controls.MonitorVolumes.ItemsSource) {
        $Gui.Controls.MonitorVolumes.ItemsSource = @($items)
        $Gui.VolumeSignature = $signature
    }
}
