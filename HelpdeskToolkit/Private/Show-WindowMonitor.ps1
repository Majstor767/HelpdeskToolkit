function Show-WindowMonitor {
    <#
    .SYNOPSIS
        Displays one performance snapshot on the Live monitor page of the window.
    .DESCRIPTION
        Takes the object returned by Get-PerformanceSnapshot and fills the meters and
        texts of the page. Like the result cards, the lists of the page only show text
        and a percentage; this function prepares exactly those for every row.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The object returned by Get-PerformanceSnapshot.
        [Parameter(Mandatory)]
        [PSCustomObject]$Snapshot
    )

    $controls = $Gui.Controls

    # Clock speed in GHz with one decimal, for example "2.5 GHz"
    $toGigahertz = { param($Megahertz) '{0} GHz' -f [string][math]::Round([double]$Megahertz / 1000, 1) }

    # The meters of the lists are bound to the Percent property of each row. WPF needs a
    # plain number there; a value that came out of a script block is wrapped by PowerShell
    # and would leave the meter empty, hence the [double] casts below.
    # Processor
    if ($Snapshot.Cpu) {
        $controls.MonitorCpuText.Text = '{0} % at {1}' -f $Snapshot.Cpu.Percent, (& $toGigahertz $Snapshot.Cpu.FrequencyMHz)
        $controls.MonitorCpuBar.Value = $Snapshot.Cpu.Percent
        $controls.MonitorProcessors.ItemsSource = @(
            $Snapshot.Cpu.Processors | ForEach-Object {
                [PSCustomObject]@{ Name = $_.Name; Percent = [double]$_.Percent; Text = '{0} %' -f $_.Percent }
            }
        )
    }
    else {
        $controls.MonitorCpuText.Text = 'Not available'
        $controls.MonitorCpuBar.Value = 0
        $controls.MonitorProcessors.ItemsSource = @()
    }

    # Memory
    if ($Snapshot.Memory) {
        $controls.MonitorMemoryText.Text = '{0} % ({1} of {2} in use)' -f $Snapshot.Memory.Percent,
            (Format-Gigabyte -Bytes $Snapshot.Memory.UsedBytes), (Format-Gigabyte -Bytes $Snapshot.Memory.TotalBytes)
        $controls.MonitorMemoryBar.Value = $Snapshot.Memory.Percent
        $controls.MonitorCommitText.Text = 'Committed (RAM plus page file): {0} of {1}' -f
            (Format-Gigabyte -Bytes $Snapshot.Memory.CommittedBytes), (Format-Gigabyte -Bytes $Snapshot.Memory.CommitLimitBytes)
    }
    else {
        $controls.MonitorMemoryText.Text = 'Not available'
        $controls.MonitorMemoryBar.Value = 0
        $controls.MonitorCommitText.Text = ''
    }

    # Graphics
    $gpus = @(
        $Snapshot.Gpu | Where-Object { $_ } | ForEach-Object {
            $memoryText = if ($_.DedicatedTotalBytes -gt 0) {
                '{0} of {1} memory' -f (Format-Gigabyte -Bytes $_.DedicatedUsedBytes), (Format-Gigabyte -Bytes $_.DedicatedTotalBytes)
            }
            else {
                '{0} memory in use' -f (Format-Gigabyte -Bytes $_.DedicatedUsedBytes)
            }
            [PSCustomObject]@{ Name = $_.Name; Percent = [double]$_.Percent; Text = '{0} %  |  {1}' -f $_.Percent, $memoryText }
        }
    )
    $controls.MonitorGpus.ItemsSource = $gpus
    $controls.MonitorGpuEmpty.Visibility = if ($gpus.Count -eq 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }

    # Disks
    $controls.MonitorDisks.ItemsSource = @(
        $Snapshot.Disks | Where-Object { $_ } | ForEach-Object {
            [PSCustomObject]@{
                Name    = $_.Name
                Percent = [double]$_.Percent
                Text    = 'active {0} %  |  read {1}  |  write {2}' -f $_.Percent,
                    (Format-DataRate -BytesPerSecond $_.ReadBytesPerSecond), (Format-DataRate -BytesPerSecond $_.WriteBytesPerSecond)
            }
        }
    )

    # Network
    $controls.MonitorNetwork.ItemsSource = @(
        $Snapshot.Network | Where-Object { $_ } | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Text = 'down {0}  |  up {1}' -f (Format-DataRate -BytesPerSecond $_.ReceivedBytesPerSecond -AsBits),
                    (Format-DataRate -BytesPerSecond $_.SentBytesPerSecond -AsBits)
            }
        }
    )

    # Busiest programs
    $controls.MonitorProcesses.ItemsSource = @(
        $Snapshot.Processes | Where-Object { $_ } | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Text = '{0} %  |  {1}' -f $_.Percent, (Format-Gigabyte -Bytes $_.MemoryBytes)
            }
        }
    )

    $controls.PageSubtitle.Text = 'What the computer is doing right now. Updated {0:HH:mm:ss}; refreshes about every 2 seconds.' -f $Snapshot.TakenAt
}
