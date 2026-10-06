# Tests for what happens when Windows does not answer: every source the checks read
# (WMI, the registry, the event log, the services, the cmdlets of Defender and of the
# storage) fails, or returns nothing. A check must then say "Unavailable" for what it
# could not read; it must never end with an error, because one check that throws takes
# its whole category with it.
#
# Nothing is started and nothing is asked from the network: Start-Process and
# Invoke-WebRequest fail like everything else, and the tests that need the network or
# walk through whole drives are left out or replaced.

BeforeDiscovery {
    $commands = @(
        @{ Command = 'Get-SystemHealth'; Parameters = @{} }
        @{ Command = 'Get-ComputerSpecification'; Parameters = @{} }
        @{ Command = 'Get-HardwareHealth'; Parameters = @{} }
        @{ Command = 'Get-SoftwareHealth'; Parameters = @{ SkipUpdateCheck = $true } }
        @{ Command = 'Get-EventLogHealth'; Parameters = @{} }
        @{ Command = 'Get-WindowsUpdateHealth'; Parameters = @{} }
        @{ Command = 'Get-SecurityHealth'; Parameters = @{} }
        @{ Command = 'Get-NetworkHealth'; Parameters = @{ SkipConnectivity = $true } }
        @{ Command = 'Get-PrinterHealth'; Parameters = @{} }
        @{ Command = 'Get-ServiceHealth'; Parameters = @{} }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    # Everything the module reads the computer with. A cmdlet that this edition of
    # PowerShell does not have cannot be replaced, and cannot be called either. The
    # cmdlets of the Storage module cannot be replaced by Pester at all, so the function
    # of the module that calls them (Get-DriveReliability) is replaced instead.
    $sources = @(
        'Get-CimInstance', 'Get-CimAssociatedInstance', 'Get-WinEvent', 'Get-ItemProperty', 'Get-ChildItem', 'Get-Item', 'Get-Content',
        'Get-Process', 'Get-Service', 'Get-HotFix', 'Get-MpThreat', 'Get-MpComputerStatus',
        'Get-NetTCPConnection', 'Get-NetFirewallProfile', 'Get-ScheduledTask', 'Invoke-WebRequest', 'Start-Process', 'Select-String'
    ) | Where-Object { Get-Command -Name $_ -ErrorAction SilentlyContinue }

    $statuses = 'OK', 'Warning', 'Critical', 'Info'

    # What every result must be, whatever happened while it was made.
    function Assert-TestResult {
        param([object[]]$Result, [string]$Command)

        $Result.Count | Should -BeGreaterThan 0 -Because "$Command must say something even when nothing could be read"
        foreach ($item in $Result) {
            $item.PSObject.TypeNames | Should -Contain 'HelpdeskToolkit.CheckResult'
            $item.Category | Should -Not -BeNullOrEmpty
            $item.Check | Should -Not -BeNullOrEmpty
            $item.Status | Should -BeIn $statuses
            # A value the window and the reports can show: text, never an object or nothing.
            $item.Value | Should -BeOfType [string]
        }
    }
}

Describe 'A check when every source fails' {
    BeforeAll {
        foreach ($source in $sources) {
            Mock -ModuleName HelpdeskToolkit $source { throw 'Access is denied.' }
        }
        # Walking through drives is real work on the disk, not a question to Windows.
        Mock -ModuleName HelpdeskToolkit Get-DriveReliability { throw 'Access is denied.' }
        Mock -ModuleName HelpdeskToolkit Get-LargestFolder { throw 'Access is denied.' }
        Mock -ModuleName HelpdeskToolkit Get-FolderSize { throw 'Access is denied.' }
    }

    It '<Command> does not throw and returns well-formed results' -ForEach $commands {
        $parameters = $Parameters
        $results = $null
        { $script:results = @(& $Command @parameters) } | Should -Not -Throw
        Assert-TestResult -Result $script:results -Command $Command
    }

    It '<Command> says why something could not be read' -ForEach $commands {
        $parameters = $Parameters
        $results = @(& $Command @parameters)
        foreach ($item in $results | Where-Object { $_.Value -eq 'Unavailable' }) {
            $item.Recommendation | Should -Match 'could not be read: \S' -Because "$($item.Check) leaves the reader guessing otherwise"
        }
    }
}

Describe 'A check when every source returns nothing' {
    BeforeAll {
        foreach ($source in $sources) {
            Mock -ModuleName HelpdeskToolkit $source { }
        }
        Mock -ModuleName HelpdeskToolkit Get-DriveReliability { }
        Mock -ModuleName HelpdeskToolkit Get-LargestFolder { }
        Mock -ModuleName HelpdeskToolkit Get-FolderSize { [PSCustomObject]@{ Bytes = 0; Complete = $true } }
    }

    It '<Command> does not throw and returns well-formed results' -ForEach $commands {
        $parameters = $Parameters
        { $script:results = @(& $Command @parameters) } | Should -Not -Throw
        Assert-TestResult -Result $script:results -Command $Command
    }
}

Describe 'The whole report when every source fails' {
    Context 'while nothing can be read' {
        BeforeAll {
            foreach ($source in $sources) {
                Mock -ModuleName HelpdeskToolkit $source { throw 'Access is denied.' }
            }
            Mock -ModuleName HelpdeskToolkit Get-DriveReliability { throw 'Access is denied.' }
            Mock -ModuleName HelpdeskToolkit Get-LargestFolder { throw 'Access is denied.' }
            Mock -ModuleName HelpdeskToolkit Get-FolderSize { throw 'Access is denied.' }
            # Kept for the tests below, which need the files of the module to be readable again.
            $script:unreadReport = Get-PCHealthReport -SkipNetwork
        }

        It 'is still a report, with every category in it' {
            $script:unreadReport.PSObject.TypeNames | Should -Contain 'HelpdeskToolkit.HealthReport'
            @($script:unreadReport.Results | ForEach-Object Category | Sort-Object -Unique).Count | Should -Be 10
            $script:unreadReport.Score | Should -BeGreaterOrEqual 0
            $script:unreadReport.Score | Should -BeLessOrEqual 100
        }

        It 'has no category that was lost as a whole' {
            @($script:unreadReport.Results | Where-Object Check -eq 'Check execution').Count | Should -Be 0
        }
    }

    Context 'afterwards' {
        BeforeAll {
            $folder = Join-Path -Path $TestDrive -ChildPath 'Unread'
            [void](New-Item -Path $folder -ItemType Directory -Force)
        }

        It 'can be saved as <_>' -ForEach 'Json', 'Html', 'Csv' {
            $path = Join-Path -Path $folder -ChildPath ('report.{0}' -f $_.ToLowerInvariant())
            { InModuleScope HelpdeskToolkit -Parameters @{ Report = $script:unreadReport; Path = $path; Format = $_ } { & "Export-HealthReport$Format" -Report $Report -Path $Path } } | Should -Not -Throw
            (Get-Item -LiteralPath $path).Length | Should -BeGreaterThan 500
        }

        It 'comes back from JSON as the same report' {
            $path = Join-Path -Path $folder -ChildPath 'report.json'
            $loaded = InModuleScope HelpdeskToolkit -Parameters @{ Path = $path } { Import-HealthReport -Path $Path }
            @($loaded.Results).Count | Should -Be @($script:unreadReport.Results).Count
            $loaded.Score | Should -Be $script:unreadReport.Score
        }
    }
}

Describe 'A category that fails in the middle' {
    It 'keeps what it had found, when the categories run side by side' {
        $manifest = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit\HelpdeskToolkit.psd1'
        # A command of PowerShell itself that returns two things and then fails.
        $job = [ordered]@{
            'Broken' = @{ Command = 'Invoke-Expression'; Parameters = @{ Command = "'first'; 'second'; throw 'The third one failed'" } }
            'Fine'   = @{ Command = 'Write-Output'; Parameters = @{ InputObject = 'all of it' } }
        }
        $outcome = InModuleScope HelpdeskToolkit -Parameters @{ Job = $job; Manifest = $manifest } {
            Invoke-ParallelCommand -Job $Job -ManifestPath $Manifest -ThrottleLimit 2
        }

        $outcome['Broken'].Output | Should -Be @('first', 'second')
        $outcome['Broken'].Error.Exception.Message | Should -Match 'The third one failed'
        $outcome['Fine'].Output | Should -Be @('all of it')
        $outcome['Fine'].Error | Should -BeNullOrEmpty
    }
}
