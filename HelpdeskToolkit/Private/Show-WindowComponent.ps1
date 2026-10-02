function Show-WindowComponent {
    <#
    .SYNOPSIS
        Draws the live part of the detail page of a component.
    .DESCRIPTION
        Called when the page is opened and with every measurement of the Live monitor
        while it is open. From the newest measurement, the history and the judgement
        of the status dot (see Get-MonitorStatus) it fills:

        - the large number, the dot with its reason and the large history graph
        - what to do, while the value is close to its limit (orange) or above it (red)
        - the values of the measurement as sections: the load of every logical
          processor, the breakdown of the memory, the engines and sensors of the
          graphics card, and the programs that use the component most

        Everything that does not come with a measurement is drawn by
        Show-WindowComponentDetail.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $name = $Gui.MonitorComponent
    if (-not $name) {
        return
    }

    $controls = $Gui.Controls
    $snapshot = $Gui.MonitorSnapshot
    $visible = [System.Windows.Visibility]::Visible
    $collapsed = [System.Windows.Visibility]::Collapsed
    $separator = '  |  '
    $degree = '{0}C' -f [char]176

    $toGigahertz = { param($Megahertz) '{0} GHz' -f [string][math]::Round([double]$Megahertz / 1000, 1) }
    $toCount = { param($Number) ([long]$Number).ToString('N0', [cultureinfo]::InvariantCulture) }

    # One line of a section; with a percentage it gets a meter. (WPF needs a plain
    # number for the meter, hence the cast.)
    $row = {
        param([string]$Label, [string]$Text, $Percent = $null)
        [PSCustomObject]@{
            Name    = $Label
            Text    = $Text
            Percent = if ($null -ne $Percent) { [double]$Percent } else { [double]0 }
            Meter   = if ($null -ne $Percent) { 'Show' } else { '' }
        }
    }
    $section = {
        param([string]$Title, [object[]]$Rows)
        $lines = @($Rows | Where-Object { $_ })
        if ($lines.Count -gt 0) {
            [PSCustomObject]@{ Title = $Title; Rows = $lines }
        }
    }

    # --- Status dot, its reason and the advice -----------------------------------------
    $status = @($Gui.MonitorStatus) | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    $level = if ($status) { $status.Level } else { 'None' }
    $brushes = @{ Ok = 'OkBrush'; Near = 'WarningDotBrush'; Over = 'CriticalBrush'; None = 'NeutralBrush' }
    $controls.ComponentDot.SetResourceReference([System.Windows.Shapes.Shape]::FillProperty, $brushes[$level])
    $controls.ComponentSummary.Text = if ($status) { $status.Summary } else { Get-LocalizedText 'No measurement yet.' }

    if ($level -in 'Near', 'Over') {
        $kind = if ($level -eq 'Over') { 'Critical' } else { 'Warning' }
        $controls.ComponentAdviceCard.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "${kind}BackBrush")
        $controls.ComponentAdviceCard.SetResourceReference([System.Windows.Controls.Border]::BorderBrushProperty, $brushes[$level])
        $controls.ComponentAdviceTitle.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "${kind}Brush")
        $controls.ComponentAdviceTitle.Text = $status.Title
        $controls.ComponentAdviceItems.ItemsSource = @($status.Advice | ForEach-Object { [PSCustomObject]@{ Text = $_ } })

        $action = Get-CheckAction -Check $status.ActionCheck -Category 'Hardware'
        if ($action) {
            $controls.ComponentAdviceAction.Content = Get-LocalizedText $action.Label
            $controls.ComponentAdviceAction.Visibility = $visible
        }
        else {
            $controls.ComponentAdviceAction.Visibility = $collapsed
        }
        $controls.ComponentAdviceCard.Visibility = $visible
    }
    else {
        $controls.ComponentAdviceCard.Visibility = $collapsed
    }

    # --- History graph -------------------------------------------------------------------
    $canvas = $controls.ComponentGraph
    $width = if ($canvas.ActualWidth -gt 0) { $canvas.ActualWidth } else { 800 }
    $height = if ($canvas.ActualHeight -gt 0) { $canvas.ActualHeight } else { 148 }
    $graph = ConvertTo-WindowGraph -Value $Gui.MonitorHistory[$name].ToArray() -Width $width -Height $height -Capacity 60
    $controls.ComponentLine.Points = $graph.Line
    $controls.ComponentArea.Points = $graph.Area

    # --- The values of the newest measurement --------------------------------------------
    $value = '-'
    $sections = @()

    if ($snapshot) {
        switch ($name) {
            'Cpu' {
                $cpu = $snapshot.Cpu
                if ($cpu) {
                    $value = '{0} %' -f $cpu.Percent
                    $sections += & $section (Get-LocalizedText 'Right now') @(
                        & $row (Get-LocalizedText 'Load') ('{0} %' -f $cpu.Percent) $cpu.Percent
                        & $row (Get-LocalizedText 'Speed') (& $toGigahertz $cpu.FrequencyMHz)
                        & $row (Get-LocalizedText 'Base speed') (& $toGigahertz $cpu.BaseFrequencyMHz)
                        & $row (Get-LocalizedText 'Logical processors') ([string]@($cpu.Processors).Count)
                        if ($snapshot.System) {
                            & $row (Get-LocalizedText 'Processes') (& $toCount $snapshot.System.Processes)
                            if ($null -ne $snapshot.System.Threads) {
                                & $row (Get-LocalizedText 'Threads') (& $toCount $snapshot.System.Threads)
                                & $row (Get-LocalizedText 'Handles') (& $toCount $snapshot.System.Handles)
                            }
                            if ($null -ne $snapshot.System.UptimeSeconds) {
                                & $row (Get-LocalizedText 'Running for') (Format-Duration -Seconds $snapshot.System.UptimeSeconds)
                            }
                        }
                    )

                    $parked = Get-LocalizedText '{0}, parked by Windows to save power'
                    $sections += & $section (Get-LocalizedText 'Load of every logical processor') @(
                        $cpu.Processors | Where-Object { $_ } | ForEach-Object {
                            $speed = & $toGigahertz $_.FrequencyMHz
                            if ($_.Parked) {
                                $speed = $parked -f $speed
                            }
                            & $row $_.Name ('{0} %{1}{2}' -f $_.Percent, $separator, $speed) $_.Percent
                        }
                    )
                }
                $sections += & $section (Get-LocalizedText 'Busiest programs') @(
                    $snapshot.Processes | Where-Object { $_ } | ForEach-Object {
                        & $row $_.Name ('{0} %{1}{2}' -f $_.Percent, $separator, (Format-ByteSize -Bytes $_.MemoryBytes)) $_.Percent
                    }
                )
            }

            'Memory' {
                $memory = $snapshot.Memory
                if ($memory) {
                    $value = '{0} %' -f $memory.Percent
                    $of = Get-LocalizedText '{0} of {1}'
                    $sections += & $section (Get-LocalizedText 'Right now') @(
                        & $row (Get-LocalizedText 'In use') ($of -f (Format-Gigabyte -Bytes $memory.UsedBytes), (Format-Gigabyte -Bytes $memory.TotalBytes)) $memory.Percent
                        & $row (Get-LocalizedText 'Available') (Format-Gigabyte -Bytes $memory.AvailableBytes)
                        if ($null -ne $memory.CachedBytes) {
                            & $row (Get-LocalizedText 'Cached') (Format-Gigabyte -Bytes $memory.CachedBytes)
                        }
                        & $row (Get-LocalizedText 'Committed (RAM plus page file)') ($of -f (Format-Gigabyte -Bytes $memory.CommittedBytes), (Format-Gigabyte -Bytes $memory.CommitLimitBytes))
                        if ($null -ne $memory.PagedPoolBytes) {
                            & $row (Get-LocalizedText 'Paged pool') (Format-ByteSize -Bytes $memory.PagedPoolBytes)
                            & $row (Get-LocalizedText 'Non-paged pool') (Format-ByteSize -Bytes $memory.NonPagedPoolBytes)
                        }
                        if ($null -ne $memory.PageFilePercent) {
                            & $row (Get-LocalizedText 'Page file') ((Get-LocalizedText '{0} % used') -f $memory.PageFilePercent) $memory.PageFilePercent
                        }
                    )
                }
                $sections += & $section (Get-LocalizedText 'Programs that use the most memory') @(
                    $snapshot.MemoryProcesses | Where-Object { $_ } | ForEach-Object {
                        & $row $_.Name (Format-ByteSize -Bytes $_.MemoryBytes)
                    }
                )
            }

            'Gpu' {
                $adapters = @($snapshot.Gpu | Where-Object { $_ })
                if ($adapters.Count -gt 0) {
                    $value = '{0} %' -f [int]$adapters[0].Percent
                }
                foreach ($adapter in $adapters) {
                    $memoryText = if ($adapter.DedicatedTotalBytes -gt 0) {
                        (Get-LocalizedText '{0} of {1}') -f (Format-Gigabyte -Bytes $adapter.DedicatedUsedBytes), (Format-Gigabyte -Bytes $adapter.DedicatedTotalBytes)
                    }
                    else {
                        Format-Gigabyte -Bytes $adapter.DedicatedUsedBytes
                    }
                    $memoryPercent = if ($adapter.DedicatedTotalBytes -gt 0) { [math]::Min(100, $adapter.DedicatedUsedBytes / $adapter.DedicatedTotalBytes * 100) } else { $null }

                    $sections += & $section ((Get-LocalizedText 'Right now: {0}') -f $adapter.Name) @(
                        & $row (Get-LocalizedText 'Load') ('{0} %' -f $adapter.Percent) $adapter.Percent
                        $adapter.Engines | Where-Object { $_ } | ForEach-Object {
                            & $row (Get-LocalizedText $_.Name) ('{0} %' -f $_.Percent) $_.Percent
                        }
                        & $row (Get-LocalizedText 'Memory of its own in use') $memoryText $memoryPercent
                        if ($adapter.SharedUsedBytes -gt 0) {
                            & $row (Get-LocalizedText 'Borrowed RAM in use') (Format-ByteSize -Bytes $adapter.SharedUsedBytes)
                        }
                    )
                }

                foreach ($sensor in @($snapshot.GpuSensors | Where-Object { $_ })) {
                    $sections += & $section ((Get-LocalizedText 'Sensors: {0}') -f $sensor.Name) @(
                        if ($null -ne $sensor.TemperatureC) {
                            & $row (Get-LocalizedText 'Temperature') ('{0} {1}' -f $sensor.TemperatureC, $degree)
                        }
                        if ($null -ne $sensor.FanPercent) {
                            & $row (Get-LocalizedText 'Fan') ('{0} %' -f $sensor.FanPercent) $sensor.FanPercent
                        }
                        if ($null -ne $sensor.PowerWatts) {
                            $power = if ($sensor.PowerLimitWatts) { (Get-LocalizedText '{0} W of {1} W') -f $sensor.PowerWatts, $sensor.PowerLimitWatts } else { '{0} W' -f $sensor.PowerWatts }
                            & $row (Get-LocalizedText 'Power draw') $power
                        }
                    )
                }
            }
        }
    }

    $controls.ComponentValue.Text = $value
    $controls.ComponentLiveSections.ItemsSource = @($sections | Where-Object { $_ })
}
