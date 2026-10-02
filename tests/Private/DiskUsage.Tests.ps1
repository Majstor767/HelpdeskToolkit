# Tests for "What takes up the space" of the drives on the Live monitor page: the sizes
# of the installed programs, the largest folders, and how the window shows them.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    # The test limits: the three largest programs and the two largest folders are listed.
    Set-TestThreshold

    function New-TestProgram {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([string]$Name, $SizeBytes = $null, [string]$Location = '')

        [PSCustomObject]@{ Name = $Name; Version = '1.0'; InstallDate = $null; SizeBytes = $SizeBytes; Location = $Location }
    }

    # What Get-DiskUsageDetail returns for a drive.
    function New-TestDetail {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds objects in memory.')]
        param([int]$UnknownCount = 0, [bool]$IsElevated = $true)

        [PSCustomObject]@{
            Drive        = 'C:'
            Programs     = @(
                [PSCustomObject]@{ Name = 'Contoso Game'; Version = '1.0'; Bytes = 60GB; Complete = $false }
                [PSCustomObject]@{ Name = 'Contoso Office'; Version = '16.0'; Bytes = 3GB; Complete = $true }
                [PSCustomObject]@{ Name = 'Archive Tool'; Version = ''; Bytes = 20MB; Complete = $true }
            )
            ProgramCount = 12
            ProgramBytes = 70GB
            UnknownCount = $UnknownCount
            Folders      = @(
                [PSCustomObject]@{ Name = 'Users\m.horvat\AppData'; Bytes = 71GB; Complete = $false }
                [PSCustomObject]@{ Name = 'Windows'; Bytes = 28GB; Complete = $true }
            )
            IsElevated   = $IsElevated
            MeasuredAt   = [datetime]'2026-01-15 10:31:00'
        }
    }

    $testVolumes = @(
        [PSCustomObject]@{ Name = 'C:'; Label = 'Windows'; TotalBytes = 200GB; FreeBytes = 6GB; Percent = 97 }
        [PSCustomObject]@{ Name = 'D:'; Label = ''; TotalBytes = 400GB; FreeBytes = 300GB; Percent = 25 }
    )
}

Describe 'Get-ProgramDiskUsage' {
    BeforeAll {
        $systemDrive = $env:SystemDrive
        # A drive letter that is not the one Windows is on.
        $otherDrive = 'Q:'

        Mock -ModuleName HelpdeskToolkit Get-InstalledProgram {
            New-TestProgram -Name 'Small Tool' -SizeBytes 20MB -Location "$env:SystemDrive\Program Files\Small Tool"
            New-TestProgram -Name 'Big Suite' -SizeBytes 3GB
            New-TestProgram -Name 'No Size Here' -Location "$env:SystemDrive\Apps\NoSize"
            New-TestProgram -Name 'Unknown'
            New-TestProgram -Name 'Shared Folder' -Location $env:ProgramFiles
            New-TestProgram -Name 'Elsewhere' -SizeBytes 9GB -Location 'Q:\Games\Elsewhere'
        }
        Mock -ModuleName HelpdeskToolkit Test-Path { $true } -ParameterFilter { $LiteralPath -like '*\Apps\NoSize' }
        Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 500MB; FileCount = 10; Complete = $false } }

        $programs = @(InModuleScope HelpdeskToolkit -Parameters @{ Drive = $systemDrive } { Get-ProgramDiskUsage -Drive $Drive })
    }

    It 'returns the programs of the drive, largest first, and leaves out the ones of other drives' {
        $programs.Name | Should -Be @('Big Suite', 'No Size Here', 'Small Tool', 'Shared Folder', 'Unknown')
    }

    It 'takes the size the installer wrote down' {
        ($programs | Where-Object Name -eq 'Big Suite').Bytes | Should -Be 3GB
        ($programs | Where-Object Name -eq 'Big Suite').Complete | Should -BeTrue
    }

    It 'counts a program without a folder to the drive Windows is on' {
        $programs.Name | Should -Contain 'Big Suite'
        $programs.Name | Should -Contain 'Unknown'
    }

    It 'measures the folder of a program whose installer wrote down no size' {
        $program = $programs | Where-Object Name -eq 'No Size Here'
        $program.Bytes | Should -Be 500MB
        $program.Complete | Should -BeFalse
        Should -Invoke -ModuleName HelpdeskToolkit Get-FolderSize -Times 1 -Exactly -Scope Describe -ParameterFilter { $Path -like '*\Apps\NoSize' -and $TimeoutMs -le 1500 }
    }

    It 'never measures a folder that many programs share as the size of one program' {
        ($programs | Where-Object Name -eq 'Shared Folder').Bytes | Should -BeNullOrEmpty
        Should -Invoke -ModuleName HelpdeskToolkit Get-FolderSize -Times 0 -Exactly -Scope Describe -ParameterFilter { $Path -eq $env:ProgramFiles }
    }

    It 'returns a program whose size cannot be found out without a size' {
        ($programs | Where-Object Name -eq 'Unknown').Bytes | Should -BeNullOrEmpty
    }

    It 'returns the programs of another drive by their folder' {
        $elsewhere = @(InModuleScope HelpdeskToolkit -Parameters @{ Drive = $otherDrive } { Get-ProgramDiskUsage -Drive $Drive })
        $elsewhere.Name | Should -Be 'Elsewhere'
        $elsewhere[0].Bytes | Should -Be 9GB
    }

    It 'measures no folder once the time for all programs is used up' {
        $none = @(InModuleScope HelpdeskToolkit -Parameters @{ Drive = $systemDrive } { Get-ProgramDiskUsage -Drive $Drive -BudgetMs 0 })
        ($none | Where-Object Name -eq 'No Size Here').Bytes | Should -BeNullOrEmpty
    }

    It 'accepts a drive letter with a colon only' {
        { InModuleScope HelpdeskToolkit { Get-ProgramDiskUsage -Drive 'C:\' } } | Should -Throw
    }
}

Describe 'Get-DiskUsageDetail' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-ProgramDiskUsage {
            [PSCustomObject]@{ Name = 'A'; Version = '1'; Bytes = 8GB; Complete = $true }
            [PSCustomObject]@{ Name = 'B'; Version = '1'; Bytes = 4GB; Complete = $true }
            [PSCustomObject]@{ Name = 'C'; Version = '1'; Bytes = 2GB; Complete = $true }
            [PSCustomObject]@{ Name = 'D'; Version = '1'; Bytes = 1GB; Complete = $true }
            [PSCustomObject]@{ Name = 'E'; Version = '1'; Bytes = $null; Complete = $true }
        }
        Mock -ModuleName HelpdeskToolkit Get-LargestFolder {
            [PSCustomObject]@{ Name = 'Users'; Bytes = 50GB; Complete = $false }
            [PSCustomObject]@{ Name = 'Windows'; Bytes = 28GB; Complete = $true }
            [PSCustomObject]@{ Name = 'Program Files'; Bytes = 19GB; Complete = $true }
        }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }

        $detail = InModuleScope HelpdeskToolkit { Get-DiskUsageDetail -Drive 'C:' }
    }

    It 'lists the largest programs, as many as the configuration says' {
        $detail.Programs.Name | Should -Be @('A', 'B', 'C')
    }

    It 'counts and adds up all programs with a known size, not only the listed ones' {
        $detail.ProgramCount | Should -Be 4
        $detail.ProgramBytes | Should -Be 15GB
    }

    It 'counts the programs whose size is not known' {
        $detail.UnknownCount | Should -Be 1
    }

    It 'lists the largest folders of the drive, as many as the configuration says' {
        $detail.Folders.Name | Should -Be @('Users', 'Windows')
        Should -Invoke -ModuleName HelpdeskToolkit Get-LargestFolder -Times 1 -Exactly -Scope Describe -ParameterFilter { $Path -eq 'C:\' -and $TimeoutMs -eq 1000 -and $BudgetMs -eq 3000 }
    }

    It 'says for which drive, when and with which rights it was measured' {
        $detail.Drive | Should -Be 'C:'
        $detail.MeasuredAt | Should -BeOfType [datetime]
        $detail.IsElevated | Should -BeFalse
    }

    It 'returns empty lists for a drive without programs and folders' {
        Mock -ModuleName HelpdeskToolkit Get-ProgramDiskUsage { }
        Mock -ModuleName HelpdeskToolkit Get-LargestFolder { }
        $empty = InModuleScope HelpdeskToolkit { Get-DiskUsageDetail -Drive 'E:' }

        @($empty.Programs).Count | Should -Be 0
        @($empty.Folders).Count | Should -Be 0
        $empty.ProgramCount | Should -Be 0
        $empty.ProgramBytes | Should -Be 0
    }
}

Describe 'Show-WindowVolume and Switch-WindowVolume' -Skip:(-not $isSta) {
    BeforeAll {
        # The measurement itself is not started: the tests set its result.
        Mock -ModuleName HelpdeskToolkit Invoke-WindowDiskUsage { $Gui.DiskUsage[$Drive].State = 'Loading' }

        # Windows is on C: in these tests, whatever the drive of the test computer is.
        $realSystemDrive = $env:SystemDrive
        $env:SystemDrive = 'C:'
    }

    AfterAll {
        $env:SystemDrive = $realSystemDrive
    }

    BeforeEach {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Volume = $testVolumes } { Show-WindowVolume -Gui $Gui -Volume $Volume }
    }

    It 'shows one line per drive letter with its label, used and free space' {
        $rows = @($gui.Controls.MonitorVolumes.ItemsSource)
        $rows.Name | Should -Be @('C: Windows', 'D:')
        $rows.Drive | Should -Be @('C:', 'D:')
        $rows[0].Text | Should -Be '97 % used  |  6 GB free of 200 GB  |  Windows drive'
        $rows[0].Percent | Should -Be 97
    }

    It 'names only the drive Windows is installed on as the Windows drive' {
        $rows = @($gui.Controls.MonitorVolumes.ItemsSource)
        $rows[1].Text | Should -Not -Match 'Windows drive'
        @($rows | Where-Object { $_.Text -match 'Windows drive$' }).Drive | Should -Be 'C:'
    }

    It 'mentions the folders of Windows in the note of the Windows drive only' {
        foreach ($drive in 'C:', 'D:') {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Drive = $drive } { Switch-WindowVolume -Gui $Gui -Drive $Drive }
            $gui.DiskUsage[$drive].State = 'Done'
            $gui.DiskUsage[$drive].Detail = New-TestDetail -IsElevated $false
        }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowVolume -Gui $Gui }

        $rows = @($gui.Controls.MonitorVolumes.ItemsSource)
        $rows[0].Note | Should -Match 'the folders of Windows and of other users'
        $rows[1].Note | Should -Match 'folders that belong to other users'
        $rows[1].Note | Should -Not -Match 'folders of Windows'
    }

    It 'colors the meter by the limits of the disk space check' {
        @($gui.Controls.MonitorVolumes.ItemsSource).Level | Should -Be @('Critical', 'Normal')
    }

    It 'offers to show what takes up the space, closed at first' {
        $row = @($gui.Controls.MonitorVolumes.ItemsSource)[0]
        $row.ToggleText | Should -Be 'What takes up the space on C:'
        $row.Expanded | Should -BeFalse
        $row.Details | Should -Be ''
    }

    It 'starts measuring when the line of a drive is opened, and says so' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowDiskUsage -Times 1 -Exactly -ParameterFilter { $Drive -eq 'C:' }
        $rows = @($gui.Controls.MonitorVolumes.ItemsSource)
        $rows[0].Expanded | Should -BeTrue
        $rows[0].Details | Should -Be 'Open'
        $rows[0].State | Should -Be 'Measuring ... this can take up to half a minute.'
        $rows[0].Lists | Should -Be ''
        # The other drive stays closed.
        $rows[1].Expanded | Should -BeFalse
    }

    It 'lists the largest programs and folders once the measurement is there' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].State = 'Done'
        $gui.DiskUsage['C:'].Detail = New-TestDetail
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowVolume -Gui $Gui }

        $row = @($gui.Controls.MonitorVolumes.ItemsSource)[0]
        $row.State | Should -Be 'Measured at 10:31. The 12 programs installed on this drive take up 70 GB.'
        $row.Lists | Should -Be 'Show'
        $row.Programs.Name | Should -Be @('Contoso Game', 'Contoso Office', 'Archive Tool')
        $row.Programs.Text | Should -Be @('60 GB or more', '3 GB', '20 MB')
        $row.Folders.Name | Should -Be @('Users\m.horvat\AppData', 'Windows')
        $row.Folders.Text | Should -Be @('71 GB or more', '28 GB')
    }

    It 'says that the application removes nothing, and where a program is removed' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].State = 'Done'
        $gui.DiskUsage['C:'].Detail = New-TestDetail
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowVolume -Gui $Gui }

        $note = @($gui.Controls.MonitorVolumes.ItemsSource)[0].Note
        $note | Should -Match 'click it: Installed apps of Windows opens, where you choose it and click Uninstall'
        $note | Should -Match 'This application itself removes nothing'
        $note | Should -Not -Match 'administrator'
        $note | Should -Not -Match 'do not say how large'
    }

    It 'mentions programs without a known size and the limits of a run without administrator rights' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].State = 'Done'
        $gui.DiskUsage['C:'].Detail = New-TestDetail -UnknownCount 4 -IsElevated $false
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowVolume -Gui $Gui }

        $note = @($gui.Controls.MonitorVolumes.ItemsSource)[0].Note
        $note | Should -Match 'Programs that do not say how large they are: 4\.'
        $note | Should -Match 'Without administrator rights'
    }

    It 'reports a measurement that failed' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].State = 'Failed'
        $gui.DiskUsage['C:'].Error = 'The drive is not ready'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowVolume -Gui $Gui }

        @($gui.Controls.MonitorVolumes.ItemsSource)[0].State | Should -Be 'The space could not be measured: The drive is not ready'
    }

    It 'closes the line again and keeps the measurement for the next time' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].State = 'Done'
        $gui.DiskUsage['C:'].Detail = New-TestDetail
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        @($gui.Controls.MonitorVolumes.ItemsSource)[0].Expanded | Should -BeFalse

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        @($gui.Controls.MonitorVolumes.ItemsSource)[0].Lists | Should -Be 'Show'
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowDiskUsage -Times 1 -Exactly
    }

    It 'measures again when asked to, and leaves the line open' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].State = 'Done'
        $gui.DiskUsage['C:'].Detail = New-TestDetail
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' -Refresh }

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowDiskUsage -Times 2 -Exactly
        $row = @($gui.Controls.MonitorVolumes.ItemsSource)[0]
        $row.Expanded | Should -BeTrue
        $row.State | Should -Match '^Measuring'
    }

    It 'does not start a second measurement while one is under way' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:'; Switch-WindowVolume -Gui $Gui -Drive 'C:' -Refresh }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowDiskUsage -Times 1 -Exactly
    }

    It 'tries again when a line whose measurement failed is opened' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].State = 'Failed'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'C:'; Switch-WindowVolume -Gui $Gui -Drive 'C:' }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-WindowDiskUsage -Times 2 -Exactly
    }

    It 'keeps a line open when the next measurement of the Live monitor arrives' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Switch-WindowVolume -Gui $Gui -Drive 'D:' }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Volume = $testVolumes } { Show-WindowVolume -Gui $Gui -Volume $Volume }
        @($gui.Controls.MonitorVolumes.ItemsSource).Expanded | Should -Be @($false, $true)
    }

    It 'leaves the list alone while nothing in it has changed' {
        $before = $gui.Controls.MonitorVolumes.ItemsSource
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Volume = $testVolumes } { Show-WindowVolume -Gui $Gui -Volume $Volume }
        [object]::ReferenceEquals($gui.Controls.MonitorVolumes.ItemsSource, $before) | Should -BeTrue
    }

    It 'rebuilds the list when the free space has changed' {
        $before = $gui.Controls.MonitorVolumes.ItemsSource
        $changed = @(
            [PSCustomObject]@{ Name = 'C:'; Label = 'Windows'; TotalBytes = 200GB; FreeBytes = 20GB; Percent = 90 }
            $testVolumes[1]
        )
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Volume = $changed } { Show-WindowVolume -Gui $Gui -Volume $Volume }

        [object]::ReferenceEquals($gui.Controls.MonitorVolumes.ItemsSource, $before) | Should -BeFalse
        @($gui.Controls.MonitorVolumes.ItemsSource)[0].Level | Should -Be 'Warning'
    }

    It 'shows an empty list for a computer without drive letters' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowVolume -Gui $Gui -Volume @() }
        @($gui.Controls.MonitorVolumes.ItemsSource).Count | Should -Be 0
    }
}

Describe 'Invoke-WindowDiskUsage and Receive-WindowDiskUsage' -Skip:(-not $isSta) {
    BeforeAll {
        # Gives a drive a finished background runspace that returns what the script produces.
        function Set-TestWorker {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only runs a short script in a background runspace.')]
            param($Gui, [string]$Drive, [string]$Script)

            $worker = [powershell]::Create()
            [void]$worker.AddScript($Script)
            $usage = @{ Expanded = $true; State = 'Loading'; Detail = $null; Error = ''; Worker = $worker; Handle = $worker.BeginInvoke() }
            [void]$usage.Handle.AsyncWaitHandle.WaitOne(10000)
            $Gui.DiskUsage[$Drive] = $usage
        }
    }

    BeforeEach {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Volume = $testVolumes } { Show-WindowVolume -Gui $Gui -Volume $Volume }
    }

    It 'starts a background runspace for the drive and marks it as being measured' {
        # A module path that does not exist: the runspace fails at once instead of
        # measuring this computer.
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'Missing.psd1'
        $gui.DiskUsage['C:'] = @{ Expanded = $true; State = 'None'; Detail = $null; Error = ''; Worker = $null; Handle = $null }
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowDiskUsage -Gui $Gui -Drive 'C:' }

            $gui.DiskUsage['C:'].State | Should -Be 'Loading'
            $gui.DiskUsage['C:'].Worker | Should -BeOfType [powershell]
            $gui.DiskUsage['C:'].Handle | Should -Not -BeNullOrEmpty
        }
        finally {
            $gui.DiskUsage['C:'].Worker.Stop()
            $gui.DiskUsage['C:'].Worker.Dispose()
        }
    }

    It 'does not start a second runspace for a drive that is being measured' {
        $gui.DiskUsage['C:'] = @{ Expanded = $true; State = 'Loading'; Detail = $null; Error = ''; Worker = 'already measuring'; Handle = $null }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowDiskUsage -Gui $Gui -Drive 'C:' }
        $gui.DiskUsage['C:'].Worker | Should -Be 'already measuring'
    }

    It 'does nothing for a drive whose line was never opened' {
        { InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Invoke-WindowDiskUsage -Gui $Gui -Drive 'Z:' } } | Should -Not -Throw
        $gui.DiskUsage.ContainsKey('Z:') | Should -BeFalse
    }

    It 'stores a finished measurement, releases the runspace and shows the lists' {
        Set-TestWorker -Gui $gui -Drive 'C:' -Script @'
[PSCustomObject]@{
    Drive = 'C:'; ProgramCount = 1; ProgramBytes = 2GB; UnknownCount = 0; IsElevated = $true; MeasuredAt = [datetime]'2026-01-15 10:31:00'
    Programs = @([PSCustomObject]@{ Name = 'Contoso Office'; Version = '16.0'; Bytes = 2GB; Complete = $true })
    Folders = @([PSCustomObject]@{ Name = 'Windows'; Bytes = 28GB; Complete = $true })
}
'@
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowDiskUsage -Gui $Gui }

        $gui.DiskUsage['C:'].State | Should -Be 'Done'
        $gui.DiskUsage['C:'].Worker | Should -BeNullOrEmpty
        $gui.DiskUsage['C:'].Detail.ProgramCount | Should -Be 1
        $row = @($gui.Controls.MonitorVolumes.ItemsSource)[0]
        $row.Programs.Name | Should -Be 'Contoso Office'
        $row.Folders.Text | Should -Be '28 GB'
    }

    It 'reports a measurement that failed in the list of the drive' {
        Set-TestWorker -Gui $gui -Drive 'C:' -Script 'Write-Error "The module could not be loaded"'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowDiskUsage -Gui $Gui }

        $gui.DiskUsage['C:'].State | Should -Be 'Failed'
        $gui.DiskUsage['C:'].Worker | Should -BeNullOrEmpty
        @($gui.Controls.MonitorVolumes.ItemsSource)[0].State | Should -Be 'The space could not be measured: The module could not be loaded'
    }

    It 'leaves a measurement that is still running alone' {
        $worker = [powershell]::Create()
        [void]$worker.AddScript('Start-Sleep -Seconds 30')
        $gui.DiskUsage['C:'] = @{ Expanded = $true; State = 'Loading'; Detail = $null; Error = ''; Worker = $worker; Handle = $worker.BeginInvoke() }
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowDiskUsage -Gui $Gui }
            $gui.DiskUsage['C:'].State | Should -Be 'Loading'
            $gui.DiskUsage['C:'].Worker | Should -Not -BeNullOrEmpty
        }
        finally {
            $worker.Stop()
            $worker.Dispose()
        }
    }

    It 'is called by the timer of the Live monitor, also before the first measurement of the monitor' {
        Mock -ModuleName HelpdeskToolkit Receive-WindowDiskUsage { }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowMonitor -Gui $Gui }
        Should -Invoke -ModuleName HelpdeskToolkit Receive-WindowDiskUsage -Times 1 -Exactly
    }
}
