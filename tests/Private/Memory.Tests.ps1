# Tests for what keeps the memory of the application small: the check that runs in a
# process of its own, the measurements that are remembered in a file between two such
# processes, and the memory that is handed back to Windows.
#
# The process of the check is started for real, but with a stand-in for the module that
# sits in the test drive: nothing on this computer is examined. The application folder
# is redirected into the test drive as well.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $workerScript = Join-Path -Path $moduleRoot -ChildPath 'Invoke-CheckWorker.ps1'
    $program = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $powershell = Join-Path -Path $PSHOME -ChildPath $program

    $appData = Join-Path -Path $TestDrive -ChildPath 'AppData'
    InModuleScope HelpdeskToolkit -Parameters @{ AppData = $appData } { $script:AppDataRoot = $AppData }

    # A folder that looks like the module to the script of the check: the script itself
    # and a module with the given body in place of the real one. Returns the manifest.
    function New-TestModuleFolder {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only writes into the test drive.')]
        param([string]$Name, [string]$Body)

        $folder = Join-Path -Path $TestDrive -ChildPath $Name
        [void](New-Item -Path $folder -ItemType Directory -Force)
        Copy-Item -LiteralPath $workerScript -Destination $folder
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'HelpdeskToolkit.psm1') -Value $Body -Encoding ASCII
        $manifest = Join-Path -Path $folder -ChildPath 'HelpdeskToolkit.psd1'
        Set-Content -LiteralPath $manifest -Encoding ASCII -Value "@{ RootModule = 'HelpdeskToolkit.psm1'; ModuleVersion = '0.0.1'; FunctionsToExport = 'Get-PCHealthReport' }"
        $manifest
    }

    # Reports progress like the real command, between progress of "Windows", and returns
    # a report whose only result says what the command was asked for.
    $reportingModule = @'
function Get-PCHealthReport {
    param([int]$Days, [switch]$SkipNetwork, [switch]$AllowCached)
    Write-Progress -Activity 'PC Health Check' -Status 'Hardware, Network' -CurrentOperation '1 of 3 done' -PercentComplete 33
    Write-Progress -Activity 'Something of Windows' -Status 'Noise' -PercentComplete 50
    Write-Progress -Activity 'PC Health Check' -Status 'Network' -CurrentOperation '2 of 3 done' -PercentComplete 66
    Write-Progress -Activity 'PC Health Check' -Completed
    [PSCustomObject]@{
        ToolVersion     = '0.0.1'
        ComputerName    = 'FIN-LT-014'
        GeneratedAt     = '2026-01-15 10:30:00'
        DurationSeconds = 1.5
        IsElevated      = $false
        EventLogDays    = $Days
        Score           = 100
        Results         = @(
            [PSCustomObject]@{
                Category = 'System'; Check = 'Uptime'; Description = ''; Status = 'OK'
                Value = ('days {0}, skip {1}, cached {2}' -f $Days, $SkipNetwork.IsPresent, $AllowCached.IsPresent)
                Details = @($env:HELPDESKTOOLKIT_CACHE); Allowed = ''; Typical = ''; Recommendation = ''
            }
        )
        Timeline        = @()
    }
}
'@
    $failingModule = "function Get-PCHealthReport { throw 'The disk of Contoso`n  is on fire' }"
    $slowModule = 'function Get-PCHealthReport { Start-Sleep -Seconds 120 }'

    function Get-TestWindow {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }
}

AfterAll {
    InModuleScope HelpdeskToolkit { $script:AppDataRoot = $null }
}

Describe 'Invoke-CheckWorker.ps1' {
    It 'passes the progress of the check on, writes the report as JSON and ends with 0' {
        $manifest = New-TestModuleFolder -Name 'Reporting' -Body $reportingModule
        $script = Join-Path -Path (Split-Path -Path $manifest -Parent) -ChildPath 'Invoke-CheckWorker.ps1'
        $output = Join-Path -Path $TestDrive -ChildPath 'worker-report.json'
        $cache = Join-Path -Path $TestDrive -ChildPath 'WorkerCache'

        $lines = @(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -OutputPath $output -CachePath $cache -Days 3 -SkipNetwork)
        $LASTEXITCODE | Should -Be 0

        # Only the progress of the check itself, in the order it was written
        $lines | Should -Be @('P|33|Hardware, Network|1 of 3 done', 'P|66|Network|2 of 3 done')

        $output | Should -Exist
        $bytes = [System.IO.File]::ReadAllBytes($output)
        $bytes[0] | Should -Be ([byte][char]'{') -Because 'the file has no byte order mark'

        $report = InModuleScope HelpdeskToolkit -Parameters @{ Path = $output } { Import-HealthReport -Path $Path }
        $report.ComputerName | Should -Be 'FIN-LT-014'
        $report.EventLogDays | Should -Be 3
        $report.Results[0].Value | Should -Be 'days 3, skip True, cached False'
        # The folder for remembered measurements reaches the check through the environment.
        $report.Results[0].Details | Should -Be @($cache)
    }

    It 'lets the check reuse remembered measurements only when asked to' {
        $manifest = New-TestModuleFolder -Name 'Reporting' -Body $reportingModule
        $script = Join-Path -Path (Split-Path -Path $manifest -Parent) -ChildPath 'Invoke-CheckWorker.ps1'
        $output = Join-Path -Path $TestDrive -ChildPath 'worker-cached.json'

        [void](& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -OutputPath $output -AllowCached)
        $LASTEXITCODE | Should -Be 0
        $report = InModuleScope HelpdeskToolkit -Parameters @{ Path = $output } { Import-HealthReport -Path $Path }
        $report.Results[0].Value | Should -Be 'days 7, skip False, cached True'
    }

    It 'says in one line why a check failed, writes no file and ends with 1' {
        $manifest = New-TestModuleFolder -Name 'Failing' -Body $failingModule
        $script = Join-Path -Path (Split-Path -Path $manifest -Parent) -ChildPath 'Invoke-CheckWorker.ps1'
        $output = Join-Path -Path $TestDrive -ChildPath 'worker-failed.json'

        $lines = @(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -OutputPath $output)
        $LASTEXITCODE | Should -Be 1
        $lines | Should -Be @('E|The disk of Contoso is on fire')
        $output | Should -Not -Exist
    }
}

Describe 'A check of the window, in a process of its own' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Optimize-ProcessMemory { }
    }

    It 'shows the report the process wrote and leaves no file behind' {
        $gui = Get-TestWindow
        $gui.ManifestPath = New-TestModuleFolder -Name 'Reporting' -Body $reportingModule
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }
            $gui.CheckState | Should -Not -BeNullOrEmpty
            $gui.Handle.AsyncWaitHandle.WaitOne(60000) | Should -BeTrue

            # The lines of the process arrive as the progress records the window reads.
            $progress = @($gui.Worker.Streams.Progress | Where-Object { $_.Activity -eq 'PC Health Check' })
            $progress.PercentComplete | Should -Be @(33, 66)
            $progress[0].StatusDescription | Should -Be 'Hardware, Network'
            $progress[0].CurrentOperation | Should -Be '1 of 3 done'

            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

            $gui.Report.PSObject.TypeNames | Should -Contain 'HelpdeskToolkit.HealthReport'
            $gui.Report.ComputerName | Should -Be 'FIN-LT-014'
            $gui.Report.Results[0].PSObject.TypeNames | Should -Contain 'HelpdeskToolkit.CheckResult'
            # A check that was asked for measures everything anew.
            $gui.Report.Results[0].Value | Should -BeLike '*cached False'
            $gui.Report.Results[0].Details | Should -Be @(Join-Path -Path $appData -ChildPath 'Cache')

            $gui.Worker | Should -BeNullOrEmpty
            $gui.CheckState | Should -BeNullOrEmpty
            Join-Path -Path $appData -ChildPath 'Cache\check-report.json' | Should -Not -Exist
            Should -Invoke -ModuleName HelpdeskToolkit Optimize-ProcessMemory -Times 1 -Exactly -Scope It -ParameterFilter { -not $Trim }
        }
        finally {
            $gui.Timer.Stop()
            if ($gui.Worker) {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }

    It 'shows why the check failed' {
        $gui = Get-TestWindow
        $gui.ManifestPath = New-TestModuleFolder -Name 'Failing' -Body $failingModule
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }
            $gui.Handle.AsyncWaitHandle.WaitOne(60000) | Should -BeTrue
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

            $gui.Controls.StatusText.Text | Should -BeLike 'The check failed: *The disk of Contoso is on fire*'
            $gui.Report | Should -BeNullOrEmpty
            $gui.Controls.RunButton.IsEnabled | Should -BeTrue
        }
        finally {
            $gui.Timer.Stop()
            if ($gui.Worker) {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }

    It 'says so when the script of the check is missing, without starting a process' {
        $gui = Get-TestWindow
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Nowhere\HelpdeskToolkit.psd1'
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }
            $gui.Handle.AsyncWaitHandle.WaitOne(30000) | Should -BeTrue
            $gui.CheckState.Process | Should -BeNullOrEmpty
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

            $gui.Controls.StatusText.Text | Should -BeLike 'The check failed: *The script of the check was not found*'
        }
        finally {
            $gui.Timer.Stop()
            if ($gui.Worker) {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }

    It 'ends with the process when that is ended from outside, as a closing window does' {
        $gui = Get-TestWindow
        $gui.ManifestPath = New-TestModuleFolder -Name 'Slow' -Body $slowModule
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }

            # The runspace publishes the process as soon as it has started it.
            $deadline = (Get-Date).AddSeconds(30)
            while (-not $gui.CheckState.Process -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            $process = $gui.CheckState.Process
            $process | Should -Not -BeNullOrEmpty
            $id = $process.Id
            $process.Kill()

            $gui.Handle.AsyncWaitHandle.WaitOne(30000) | Should -BeTrue
            Get-Process -Id $id -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }
            $gui.Controls.StatusText.Text | Should -BeLike 'The check failed: *'
        }
        finally {
            $gui.Timer.Stop()
            if ($gui.Worker) {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }

    It 'stops a check that does not finish, and says so' {
        $gui = Get-TestWindow
        $gui.ManifestPath = New-TestModuleFolder -Name 'Slow' -Body $slowModule
        # A limit of about a second instead of ten minutes
        $previous = InModuleScope HelpdeskToolkit { $script:CheckTimeoutMinutes }
        InModuleScope HelpdeskToolkit { $script:CheckTimeoutMinutes = 0.02 }
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }
            $gui.CheckStartedAt | Should -BeOfType [datetime]

            # What the timer of the window does: look a few times per second.
            $deadline = (Get-Date).AddSeconds(60)
            $id = 0
            while ($gui.Worker -and (Get-Date) -lt $deadline) {
                if (-not $id -and $gui.CheckState.Process) {
                    $id = $gui.CheckState.Process.Id
                }
                InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }
                Start-Sleep -Milliseconds 100
            }

            $gui.Worker | Should -BeNullOrEmpty -Because 'the check was stopped and the window is free for the next one'
            $gui.Controls.StatusText.Text | Should -BeLike 'The check failed: *did not finish within*and was stopped*'
            $gui.Controls.RunButton.IsEnabled | Should -BeTrue
            $gui.CheckStartedAt | Should -BeNullOrEmpty
            $id | Should -BeGreaterThan 0
            Get-Process -Id $id -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
        finally {
            InModuleScope HelpdeskToolkit -Parameters @{ Previous = $previous } { $script:CheckTimeoutMinutes = $Previous }
            $gui.Timer.Stop()
            if ($gui.Worker) {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }

    It 'leaves a check alone that is within its time' {
        InModuleScope HelpdeskToolkit { $script:CheckTimeoutMinutes } | Should -Be 10
        $gui = Get-TestWindow
        $gui.ManifestPath = New-TestModuleFolder -Name 'Slow' -Body $slowModule
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui }
            $deadline = (Get-Date).AddSeconds(30)
            while (-not $gui.CheckState.Process -and (Get-Date) -lt $deadline) {
                Start-Sleep -Milliseconds 50
            }
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

            $gui.CheckState.TimedOut | Should -BeFalse
            $gui.CheckState.Process.HasExited | Should -BeFalse
            $gui.Worker | Should -Not -BeNullOrEmpty
        }
        finally {
            $gui.Timer.Stop()
            if ($gui.CheckState -and $gui.CheckState.Process) {
                $gui.CheckState.Process.Kill()
            }
            if ($gui.Worker) {
                [void]$gui.Handle.AsyncWaitHandle.WaitOne(30000)
                $gui.Worker.Dispose()
            }
        }
    }

    It 'gives a repeated check the right to reuse remembered measurements' {
        $gui = Get-TestWindow
        $gui.ManifestPath = New-TestModuleFolder -Name 'Reporting' -Body $reportingModule
        $gui.Report = New-TestReport -Result @(New-TestResult -Category 'System' -Check 'Uptime' -Status OK -Value '1 d')
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowCheck -Gui $Gui -Background }
            $gui.Handle.AsyncWaitHandle.WaitOne(60000) | Should -BeTrue
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

            $gui.Report.Results[0].Value | Should -BeLike '*cached True'
        }
        finally {
            $gui.Timer.Stop()
            if ($gui.Worker) {
                $gui.Worker.Stop()
                $gui.Worker.Dispose()
            }
        }
    }

    It 'hands the memory back as well when the window is hidden' {
        $gui = Get-TestWindow
        $gui.Hidden = $true
        $gui.Worker = [powershell]::Create()
        [void]$gui.Worker.AddScript('Write-Error "Nothing to do"')
        $gui.Handle = $gui.Worker.BeginInvoke()
        [void]$gui.Handle.AsyncWaitHandle.WaitOne(10000)

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }
        Should -Invoke -ModuleName HelpdeskToolkit Optimize-ProcessMemory -Times 1 -Exactly -Scope It -ParameterFilter { $Trim }
    }
}

Describe 'Remembered measurements between two processes' {
    BeforeEach {
        $cache = Join-Path -Path $TestDrive -ChildPath ('Cache-{0}' -f [guid]::NewGuid().ToString('N'))
        $previous = $env:HELPDESKTOOLKIT_CACHE
    }

    AfterEach {
        $env:HELPDESKTOOLKIT_CACHE = $previous
    }

    It 'names no file while no folder is given' {
        $env:HELPDESKTOOLKIT_CACHE = $null
        InModuleScope HelpdeskToolkit { Get-ProcessCachePath -Key 'LargestFolders:C:' } | Should -BeNullOrEmpty
    }

    It 'names a file in the folder, with a name made of the key' {
        $env:HELPDESKTOOLKIT_CACHE = $cache
        InModuleScope HelpdeskToolkit { Get-ProcessCachePath -Key 'LargestFolders:C:' } |
            Should -Be (Join-Path -Path $cache -ChildPath 'LargestFolders_C_.xml')
    }

    It 'writes nothing to disk while no folder is given' {
        $env:HELPDESKTOOLKIT_CACHE = $null
        InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'Test:MemoryOnly' -Value 'x' }
        $cache | Should -Not -Exist
    }

    It 'finds in a new process what another one remembered' {
        $env:HELPDESKTOOLKIT_CACHE = $cache
        $key = 'Test:Folders{0}' -f [guid]::NewGuid().ToString('N')
        InModuleScope HelpdeskToolkit -Parameters @{ Key = $key } {
            Set-ProcessCache -Key $Key -Value @(
                [PSCustomObject]@{ Name = 'Users'; Bytes = 40GB; Complete = $true }
                [PSCustomObject]@{ Name = 'Windows'; Bytes = 25GB; Complete = $false }
            )
        }
        # What a new process has: the file, but nothing in memory.
        [System.AppDomain]::CurrentDomain.SetData("HelpdeskToolkit:$key", $null)

        $entry = InModuleScope HelpdeskToolkit -Parameters @{ Key = $key } { Get-ProcessCache -Key $Key -MaxAgeMinutes 30 }
        $entry.At | Should -BeOfType [datetime]
        @($entry.Value).Count | Should -Be 2
        $entry.Value[0].Name | Should -Be 'Users'
        $entry.Value[0].Bytes | Should -Be 40GB
        $entry.Value[1].Complete | Should -BeFalse
    }

    It 'does not return what a file remembered too long ago' {
        $env:HELPDESKTOOLKIT_CACHE = $cache
        $key = 'Test:Old{0}' -f [guid]::NewGuid().ToString('N')
        [void](New-Item -Path $cache -ItemType Directory -Force)
        @{ At = (Get-Date).AddHours(-2); Value = 'old' } | Export-Clixml -LiteralPath (Join-Path -Path $cache -ChildPath ('{0}.xml' -f ($key -replace '[^A-Za-z0-9]', '_')))

        InModuleScope HelpdeskToolkit -Parameters @{ Key = $key } { Get-ProcessCache -Key $Key -MaxAgeMinutes 30 } | Should -BeNullOrEmpty
        InModuleScope HelpdeskToolkit -Parameters @{ Key = $key } { Get-ProcessCache -Key $Key -MaxAgeMinutes 180 } | Should -Not -BeNullOrEmpty
    }

    It 'treats a file that cannot be read as no file' {
        $env:HELPDESKTOOLKIT_CACHE = $cache
        $key = 'Test:Broken{0}' -f [guid]::NewGuid().ToString('N')
        [void](New-Item -Path $cache -ItemType Directory -Force)
        Set-Content -LiteralPath (Join-Path -Path $cache -ChildPath ('{0}.xml' -f ($key -replace '[^A-Za-z0-9]', '_'))) -Value 'not what was written'

        { InModuleScope HelpdeskToolkit -Parameters @{ Key = $key } { Get-ProcessCache -Key $Key -MaxAgeMinutes 30 } } | Should -Not -Throw
        InModuleScope HelpdeskToolkit -Parameters @{ Key = $key } { Get-ProcessCache -Key $Key -MaxAgeMinutes 30 } | Should -BeNullOrEmpty
    }

    It 'does not fail when the file cannot be written' {
        # A file where the folder should be
        $blocked = Join-Path -Path $TestDrive -ChildPath ('blocked-{0}' -f [guid]::NewGuid().ToString('N'))
        Set-Content -LiteralPath $blocked -Value 'x'
        $env:HELPDESKTOOLKIT_CACHE = $blocked

        { InModuleScope HelpdeskToolkit { Set-ProcessCache -Key 'Test:Blocked' -Value 1 } } | Should -Not -Throw
        InModuleScope HelpdeskToolkit { (Get-ProcessCache -Key 'Test:Blocked' -MaxAgeMinutes 5).Value } | Should -Be 1
    }
}

Describe 'Optimize-ProcessMemory' {
    It 'returns nothing and does not fail' {
        { InModuleScope HelpdeskToolkit { Optimize-ProcessMemory } } | Should -Not -Throw
        InModuleScope HelpdeskToolkit { Optimize-ProcessMemory } | Should -BeNullOrEmpty
    }

    It 'hands the memory the process does not use back to Windows when asked to' {
        $process = [System.Diagnostics.Process]::GetCurrentProcess()
        $before = $process.WorkingSet64
        InModuleScope HelpdeskToolkit { Optimize-ProcessMemory -Trim } | Should -BeNullOrEmpty
        $process.Refresh()
        $process.WorkingSet64 | Should -BeLessThan $before
        $process.Dispose()

        # The declaration of the call to Windows is built once and kept.
        InModuleScope HelpdeskToolkit { $script:MemoryNativeType } | Should -Not -BeNullOrEmpty
    }
}

Describe 'Runspaces the window gives up' -Skip:(-not $isSta) {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Optimize-ProcessMemory { }
    }

    It 'releases the runspace of the Live monitor when the window goes into the background' {
        $gui = Get-TestWindow
        $worker = [powershell]::Create()
        [void]$worker.AddScript('param($Shared) while (-not $Shared.Stop) { Start-Sleep -Milliseconds 20 }')
        $shared = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; IntervalSeconds = 2 })
        [void]$worker.AddArgument($shared)
        $gui.Monitor = @{ Worker = $worker; Handle = $worker.BeginInvoke(); Shared = $shared; LastSequence = 0 }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui -Release }

        $gui.Monitor | Should -BeNullOrEmpty
        $shared.Stop | Should -BeTrue
        $gui.RetiredWorkers.Count | Should -Be 1

        # The loop ends by itself; the timer of the window then releases the runspace.
        $gui.RetiredWorkers[0].Handle.AsyncWaitHandle.WaitOne(10000) | Should -BeTrue
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Clear-WindowWorker -Gui $Gui } | Should -Be 1
        $gui.RetiredWorkers.Count | Should -Be 0
        $worker.Runspace.RunspaceStateInfo.State | Should -Be 'Closed'
        Should -Invoke -ModuleName HelpdeskToolkit Optimize-ProcessMemory -Times 1 -Exactly -Scope It
    }

    It 'only pauses the Live monitor when another page is opened' {
        $gui = Get-TestWindow
        $shared = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; IntervalSeconds = 2 })
        $gui.Monitor = @{ Worker = $null; Handle = $null; Shared = $shared; LastSequence = 0 }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui }

        $gui.Monitor | Should -Not -BeNullOrEmpty
        $shared.Paused | Should -BeTrue
        $shared.Stop | Should -BeFalse
        $gui.RetiredWorkers.Count | Should -Be 0
    }

    It 'keeps the Live monitor while it records into a file' {
        $gui = Get-TestWindow
        $shared = [hashtable]::Synchronized(@{ Paused = $false; Stop = $false; IntervalSeconds = 2 })
        $gui.Monitor = @{ Worker = $null; Handle = $null; Shared = $shared; LastSequence = 0 }
        $gui.Recorder = @{ Path = 'recording.csv' }

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Disable-WindowMonitor -Gui $Gui -Release }

        $gui.Monitor | Should -Not -BeNullOrEmpty
        $shared.Paused | Should -BeFalse
        $shared.Stop | Should -BeFalse
    }

    It 'leaves a runspace that is still working on the list' {
        $gui = Get-TestWindow
        $worker = [powershell]::Create()
        [void]$worker.AddScript('Start-Sleep -Seconds 30')
        [void]$gui.RetiredWorkers.Add(@{ Worker = $worker; Handle = $worker.BeginInvoke() })
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Clear-WindowWorker -Gui $Gui } | Should -Be 0
            $gui.RetiredWorkers.Count | Should -Be 1
            Should -Invoke -ModuleName HelpdeskToolkit Optimize-ProcessMemory -Times 0 -Exactly -Scope It
        }
        finally {
            $worker.Stop()
            $worker.Dispose()
        }
    }

    It 'does nothing while the list is empty' {
        $gui = Get-TestWindow
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Clear-WindowWorker -Gui $Gui } | Should -Be 0
    }

    It 'gives up the Live monitor and hands memory back when the window is hidden' {
        Mock -ModuleName HelpdeskToolkit Disable-WindowMonitor { }
        Mock -ModuleName HelpdeskToolkit Enable-WindowTrayIcon { }
        $gui = Get-TestWindow

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Hide-WindowToTray -Gui $Gui -Quiet }

        Should -Invoke -ModuleName HelpdeskToolkit Disable-WindowMonitor -Times 1 -Exactly -Scope It -ParameterFilter { $Release -and -not $Stop }
        Should -Invoke -ModuleName HelpdeskToolkit Optimize-ProcessMemory -Times 1 -Exactly -Scope It -ParameterFilter { $Trim }
    }
}
