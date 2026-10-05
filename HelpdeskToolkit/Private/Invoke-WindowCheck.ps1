function Invoke-WindowCheck {
    <#
    .SYNOPSIS
        Starts the health check for the application window in the background.
    .DESCRIPTION
        A window stays responsive only while its own thread is free. The checks take
        several seconds (longer when the network is down and the tests wait for
        timeouts), so the window thread only starts the work here; Receive-WindowCheck
        picks up the progress and the result.

        The check runs in a process of its own (Invoke-CheckWorker.ps1 in the module
        folder), which ends with the check. A check loads a dozen Windows modules and
        reads a lot of data, and PowerShell never gives that memory back while the
        process lives: a window that checked the computer inside its own process grew
        by several hundred megabytes with the first check and stayed that large. This
        way Windows gets the memory back every time, and the window stays small.

        A second PowerShell runspace of the window (a separate thread) starts that
        process, passes its progress on and reads the report it leaves behind as a
        JSON file. The process has the rights of the window: started from an elevated
        window it is elevated too, without another question.

        With -Background the check is one the application repeats by itself (see
        Invoke-WindowAutoCheck). It runs the same way but stays out of the way: no
        progress panel, and the results on the screen stay until the new ones arrive.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Background
    )

    # A check is already running.
    if ($Gui.Worker) {
        return
    }

    $controls = $Gui.Controls
    $days = [int]$controls.DaysComboBox.SelectedItem.Tag
    $skipNetwork = $controls.SkipNetworkCheckBox.IsChecked -eq $true

    $controls.RunButton.IsEnabled = $false
    if ($Background) {
        $controls.RunButton.Content = Get-LocalizedText 'Updating ...'
        $controls.StatusText.Text = Get-LocalizedText 'Checking again in the background; the results stay in place until the new ones are there ...'
    }
    else {
        $controls.RunButton.Content = Get-LocalizedText 'Checking ...'
        $controls.StatusText.Text = Get-LocalizedText 'The check is running ...'

        # Progress panel: empty the bar and show it. An animation of the previous run would
        # otherwise keep holding the old value, so it is removed first.
        $controls.ProgressBar.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $null)
        $controls.ProgressBar.Value = 0
        $controls.RunTitle.Text = Get-LocalizedText 'Starting the check ...'
        $controls.RunStep.Text = ''
        $controls.RunPercent.Text = '0 %'
        $controls.RunPanel.Visibility = [System.Windows.Visibility]::Visible
    }

    # What the runspace does: start the process of the check, turn its lines into
    # progress records, and return the report it wrote. It does not need the module.
    # A check the application repeats by itself may reuse the measurements that take
    # long and change slowly; a check the user asked for measures everything anew.
    $work = {
        param($ScriptPath, $PowerShellPath, $WorkFolder, $Activity, $State, $Days, $SkipNetwork, $AllowCached)

        if (-not (Test-Path -LiteralPath $ScriptPath)) {
            throw "The script of the check was not found: $ScriptPath"
        }
        if (-not (Test-Path -LiteralPath $WorkFolder)) {
            [void](New-Item -Path $WorkFolder -ItemType Directory -Force)
        }
        $reportPath = Join-Path -Path $WorkFolder -ChildPath 'check-report.json'
        if (Test-Path -LiteralPath $reportPath) {
            Remove-Item -LiteralPath $reportPath -Force
        }

        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -OutputPath "{1}" -CachePath "{2}" -Activity "{3}" -Days {4}' -f
            $ScriptPath, $reportPath, $WorkFolder, $Activity, [int]$Days
        if ($SkipNetwork) {
            $arguments += ' -SkipNetwork'
        }
        if ($AllowCached) {
            $arguments += ' -AllowCached'
        }

        $start = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $start.FileName = $PowerShellPath
        $start.Arguments = $arguments
        # No window, and the output comes to this runspace instead of a console.
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $start.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $process = [System.Diagnostics.Process]::Start($start)
        # The window ends the process when it is closed in the middle of a check.
        $State.Process = $process
        try {
            # Read at the same time: a process that fills one of the two channels
            # while nobody reads it would wait forever.
            $errorText = $process.StandardError.ReadToEndAsync()
            $failure = ''
            while ($null -ne ($line = $process.StandardOutput.ReadLine())) {
                $part = $line.Split('|')
                if ($part[0] -eq 'P' -and $part.Count -ge 4 -and $part[2]) {
                    Write-Progress -Activity $Activity -Status $part[2] -CurrentOperation $part[3] -PercentComplete ([int]$part[1])
                }
                elseif ($part[0] -eq 'E') {
                    $failure = $line.Substring(2)
                }
            }
            $process.WaitForExit()

            if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $reportPath)) {
                if (-not $failure) {
                    $failure = ([string]$errorText.Result).Trim()
                }
                if (-not $failure) {
                    $failure = 'The check ended without a report (exit code {0}).' -f $process.ExitCode
                }
                throw $failure
            }

            # Plain data; Receive-WindowCheck turns it back into a report.
            [System.IO.File]::ReadAllText($reportPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        }
        finally {
            $State.Process = $null
            if (-not $process.HasExited) {
                try {
                    $process.Kill()
                }
                catch {
                    Write-Verbose "The process of the check had already ended: $($_.Exception.Message)"
                }
            }
            $process.Dispose()
            if (Test-Path -LiteralPath $reportPath) {
                Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # The check runs in the edition of PowerShell the window runs in, from the folder
    # of the module. The program is taken from the folder of PowerShell, not from the
    # process: the module may have been loaded by another host (the ISE, an editor).
    $scriptPath = Join-Path -Path (Split-Path -Path $Gui.ManifestPath -Parent) -ChildPath 'Invoke-CheckWorker.ps1'
    $program = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $powershell = Join-Path -Path $PSHOME -ChildPath $program
    $state = [hashtable]::Synchronized(@{ Process = $null })

    $worker = [powershell]::Create()
    [void]$worker.AddScript($work.ToString()).AddArgument($scriptPath).AddArgument($powershell).
        AddArgument((Get-AppDataPath -ChildPath 'Cache')).AddArgument($script:ProgressActivity).AddArgument($state).
        AddArgument($days).AddArgument($skipNetwork).AddArgument([bool]$Background)

    $Gui.Background = [bool]$Background
    $Gui.RunStep = ''
    $Gui.CheckState = $state
    $Gui.Worker = $worker
    $Gui.Handle = $worker.BeginInvoke()
    $Gui.Timer.Start()

    # While the first check runs, the empty Overview says so instead of "No results yet".
    if (-not $Gui.Report -and $Gui.Page -notin 'Live monitor', 'Settings') {
        Show-WindowPage -Gui $Gui -Name 'Overview'
    }
}
