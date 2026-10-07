function Get-MonitorStatus {
    <#
    .SYNOPSIS
        Judges the processor, the memory and the graphics card for the status dots of the Live monitor.
    .DESCRIPTION
        Returns one object each for "Cpu", "Memory" and "Gpu" with:

        - Level:   "Ok" (green dot), "Near" (orange), "Over" (red) or "None" (no
                   measurement yet)
        - Summary: one sentence that says why, shown when the mouse rests on the dot
        - Title, Advice: what to do about it, shown when the warning triangle of a red
                   dot is opened. The advice names the program that causes the most
                   load at this moment.
        - ActionCheck: the check whose place in Windows the button below the advice
                   opens (see Get-CheckAction)

        How the level is decided:

        - A single measurement means little, so the average of the last few
          measurements is judged (StatusSamples).
        - Over: that average is above the limit. For processor and memory the limit is
          the Warning limit of their health checks, so the dot and the check agree.
        - Near: the average is within NearMarginPercent of the limit, or the value
          keeps rising. Rising means that a straight line through the last
          TrendSamples measurements (least squares) reaches the limit within the next
          TrendAheadSamples measurements.
        - The graphics card is also judged by its temperature, when it has a sensor.

        All numbers are in Config\Thresholds.psd1.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # The histories kept by the window: tables of percentages, oldest first.
        [Parameter(Mandatory)]
        [hashtable]$History,

        # The newest snapshot, as returned by Get-PerformanceSnapshot.
        [Parameter(Mandatory)]
        [PSCustomObject]$Snapshot
    )

    $limits = Get-HealthThreshold
    $monitor = $limits.Monitor
    $degree = [string][char]176

    # Level of a history of percentages against a limit.
    $judge = {
        param($Values, [double]$Limit)

        $all = @($Values)
        if ($all.Count -eq 0) {
            return [PSCustomObject]@{ Level = 'None'; Average = 0; Rising = $false }
        }

        $recent = @($all | Select-Object -Last ([int]$monitor.StatusSamples))
        $average = [math]::Round(($recent | Measure-Object -Average).Average)
        $level = 'Ok'
        $rising = $false

        if ($average -ge $Limit) {
            $level = 'Over'
        }
        elseif ($average -ge $Limit - $monitor.NearMarginPercent) {
            $level = 'Near'
        }
        elseif ($all.Count -ge $monitor.TrendSamples -and $average -ge $monitor.TrendMinimumPercent) {
            # Slope of the straight line that fits the last measurements best
            $window = @($all | Select-Object -Last ([int]$monitor.TrendSamples))
            $middle = ($window.Count - 1) / 2
            $mean = ($window | Measure-Object -Average).Average
            $above = 0.0
            $below = 0.0
            for ($index = 0; $index -lt $window.Count; $index++) {
                $above += ($index - $middle) * ($window[$index] - $mean)
                $below += ($index - $middle) * ($index - $middle)
            }
            $slope = if ($below -gt 0) { $above / $below } else { 0 }

            if ($slope -gt 0 -and $average + $slope * $monitor.TrendAheadSamples -ge $Limit) {
                $level = 'Near'
                $rising = $true
            }
        }

        [PSCustomObject]@{ Level = $level; Average = $average; Rising = $rising }
    }

    # The sentence behind the dot
    $describe = {
        param($Judgement, [double]$Limit)
        switch ($Judgement.Level) {
            'Over' { (Get-LocalizedText 'Above the limit: {0} % on average, up to {1} % is fine. Click the triangle to see what to do.') -f $Judgement.Average, $Limit }
            'Near' {
                if ($Judgement.Rising) {
                    (Get-LocalizedText 'Rising: {0} % on average and on the way to the limit of {1} %.') -f $Judgement.Average, $Limit
                }
                else {
                    (Get-LocalizedText 'Close to the limit: {0} % on average, up to {1} % is fine.') -f $Judgement.Average, $Limit
                }
            }
            'Ok' { (Get-LocalizedText 'Fine: {0} % on average, up to {1} % is fine.') -f $Judgement.Average, $Limit }
            default { Get-LocalizedText 'No measurement yet.' }
        }
    }

    $first = { param($List) @($List | Where-Object { $_ }) | Select-Object -First 1 }

    # --- Processor -----------------------------------------------------------------
    $limit = $limits.Cpu.WarningPercent
    $judgement = & $judge $History.Cpu $limit
    $advice = @((Get-LocalizedText 'The processor has been at {0} % on average over the last measurements; up to {1} % is fine.') -f $judgement.Average, $limit)
    $program = & $first $Snapshot.Processes
    if ($program) {
        $advice += (Get-LocalizedText 'The program that uses the processor most right now is {0} ({1} %). Close it, or what it has open, if you do not need it.') -f $program.Name, $program.Percent
    }
    $advice += Get-LocalizedText 'Programs that start with Windows keep working in the background. Turn off the ones you do not need in Settings > Apps > Startup.'
    $advice += Get-LocalizedText 'A virus scan or the installation of Windows updates keeps the processor busy for a while. That passes by itself.'
    $advice += Get-LocalizedText 'If the load stays high with nothing open, restart the computer. If it comes back, find the program in Task Manager, sorted by the CPU column.'

    [PSCustomObject]@{
        Name        = 'Cpu'
        Level       = $judgement.Level
        Summary     = & $describe $judgement $limit
        Title       = Get-LocalizedText 'Processor: how to bring the load down'
        Advice      = $advice
        ActionCheck = 'CPU load'
    }

    # --- Memory --------------------------------------------------------------------
    $limit = $limits.Memory.WarningPercent
    $judgement = & $judge $History.Memory $limit
    $advice = @((Get-LocalizedText 'The memory has been {0} % full on average over the last measurements; up to {1} % is fine.') -f $judgement.Average, $limit)
    # Parts of Windows itself appear among the programs and can use the most memory
    # ("Memory Compression" is where Windows keeps memory it has squeezed). Nobody can
    # close them, so the advice names the first program that can be closed.
    $ownOfWindows = 'Memory Compression', 'System', 'Registry', 'Secure System', 'Idle', 'System Idle Process'
    $program = & $first @($Snapshot.MemoryProcesses | Where-Object { $_ -and $ownOfWindows -notcontains [string]$_.Name })
    if ($program) {
        $advice += (Get-LocalizedText 'The program that uses the most memory right now is {0} ({1}). Close it, or some of its tabs and documents.') -f $program.Name, (Format-Gigabyte -Bytes $program.MemoryBytes)
    }
    $advice += Get-LocalizedText 'Browsers are the usual cause: every open tab and every extension takes memory. Close the tabs you do not need.'
    $advice += Get-LocalizedText 'A program that has been open for days can hold on to memory it no longer needs. Close it and start it again.'
    $advice += Get-LocalizedText 'If the memory is full every day with only the programs you need, the computer needs more RAM.'

    [PSCustomObject]@{
        Name        = 'Memory'
        Level       = $judgement.Level
        Summary     = & $describe $judgement $limit
        Title       = Get-LocalizedText 'Memory: how to free it'
        Advice      = $advice
        ActionCheck = 'Memory usage'
    }

    # --- Graphics card ---------------------------------------------------------------
    $limit = $monitor.GpuWarningPercent
    $judgement = & $judge $History.Gpu $limit
    $level = $judgement.Level
    $summary = & $describe $judgement $limit
    $advice = @()
    if ($level -ne 'None') {
        $advice += (Get-LocalizedText 'The graphics card has been at {0} % on average over the last measurements; up to {1} % is fine.') -f $judgement.Average, $limit
    }

    # The hottest card decides; a temperature can only make the level worse.
    $hottest = @($Snapshot.GpuSensors | Where-Object { $_ -and $null -ne $_.TemperatureC } | Sort-Object -Property TemperatureC -Descending) | Select-Object -First 1
    if ($hottest) {
        if ($hottest.TemperatureC -ge $monitor.GpuTemperatureAlert) {
            $level = 'Over'
            $summary = (Get-LocalizedText 'Too hot: {0} {2}C, up to {1} {2}C is fine. Click the triangle to see what to do.') -f $hottest.TemperatureC, $monitor.GpuTemperatureAlert, $degree
        }
        elseif ($hottest.TemperatureC -ge $monitor.GpuTemperatureNear -and $level -ne 'Over') {
            $level = 'Near'
            $summary = (Get-LocalizedText 'Getting hot: {0} {2}C; the limit is {1} {2}C.') -f $hottest.TemperatureC, $monitor.GpuTemperatureAlert, $degree
        }
        if ($hottest.TemperatureC -ge $monitor.GpuTemperatureNear) {
            $advice += (Get-LocalizedText 'The graphics card is at {0} {1}C. Clean the dust from its fans and make sure the air can flow through the case.') -f $hottest.TemperatureC, $degree
        }
    }
    $advice += Get-LocalizedText 'A game, a video or a 3D program uses the graphics card fully while it runs; that is normal. To bring it down, lower the graphics quality or the resolution in its settings, or limit the frames per second.'
    $advice += Get-LocalizedText 'If nothing like that is open, find the program in Task Manager, sorted by the GPU column, and close it.'
    $advice += Get-LocalizedText 'Browsers and chat programs use the graphics card for video and animations. Close the tabs that play video.'
    $advice += Get-LocalizedText 'An old driver can cause a high load: install the current driver from the maker of the graphics card.'

    [PSCustomObject]@{
        Name        = 'Gpu'
        Level       = $level
        Summary     = $summary
        Title       = Get-LocalizedText 'Graphics card: how to bring the load down'
        Advice      = $advice
        ActionCheck = 'CPU load'
    }
}
