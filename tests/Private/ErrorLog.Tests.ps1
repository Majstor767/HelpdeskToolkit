# Tests for the log of the application and for the errors nobody expected: they are
# written down and the window stays open. The application folder is redirected into
# the test drive (see Import-TestModule), so the log of the person running the tests
# is never touched.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $appData = Join-Path -Path $TestDrive -ChildPath 'AppData'
    $log = Join-Path -Path $appData -ChildPath 'app.log'
    $oldLog = Join-Path -Path $appData -ChildPath 'app.old.log'

    # An error as PowerShell records it, with the place in the script.
    function Get-TestFailure {
        param([string]$Message = 'The printer of Contoso is jammed')
        try {
            throw $Message
        }
        catch {
            $_
        }
    }

    function Get-TestWindow {
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
        $gui
    }
}

Describe 'Write-AppLog' {
    BeforeEach {
        foreach ($file in $log, $oldLog) {
            if (Test-Path -LiteralPath $file) {
                Remove-Item -LiteralPath $file -Force
            }
        }
        Mock -ModuleName HelpdeskToolkit Test-IsAdministrator { $false }
    }

    It 'creates the file in the folder of the application and returns its path' {
        InModuleScope HelpdeskToolkit { Write-AppLog -Message 'The check failed' } | Should -Be $log
        $log | Should -Exist
    }

    It 'writes the time, the level, the message and what the application ran as' {
        [void](InModuleScope HelpdeskToolkit { Write-AppLog -Message 'The check failed' })
        $lines = @(Get-Content -LiteralPath $log)
        $lines.Count | Should -Be 1
        $lines[0] | Should -Match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \[Error\] The check failed \(HelpdeskToolkit \S+, PowerShell \d+\.\d+\S*, administrator: False\)$'
    }

    It 'adds the error and where in the code it happened' {
        $failure = Get-TestFailure
        [void](InModuleScope HelpdeskToolkit -Parameters @{ Failure = $failure } { Write-AppLog -Message 'An unexpected error in the window' -ErrorRecord $Failure })
        $lines = @(Get-Content -LiteralPath $log)
        $lines[1] | Should -Be '    System.Management.Automation.RuntimeException: The printer of Contoso is jammed'
        ($lines | Select-Object -Skip 2) -join "`n" | Should -Match 'ErrorLog\.Tests\.ps1: line \d+'
    }

    It 'keeps the level it is given' {
        [void](InModuleScope HelpdeskToolkit { Write-AppLog -Message 'Started' -Level Info })
        Get-Content -LiteralPath $log | Should -Match '\[Info\] Started'
    }

    It 'adds to the file instead of replacing it' {
        [void](InModuleScope HelpdeskToolkit { Write-AppLog -Message 'First' })
        [void](InModuleScope HelpdeskToolkit { Write-AppLog -Message 'Second' })
        @(Get-Content -LiteralPath $log).Count | Should -Be 2
    }

    It 'writes UTF-8 without a byte order mark' {
        [void](InModuleScope HelpdeskToolkit { Write-AppLog -Message 'Started' })
        [System.IO.File]::ReadAllBytes($log)[0] | Should -Be ([byte][char]'2') -Because 'the file starts with the year'
    }

    It 'starts a new file when the log has grown too large, and keeps one old one' {
        [void](New-Item -Path $appData -ItemType Directory -Force)
        [System.IO.File]::WriteAllText($log, ('x' * 600KB))
        [System.IO.File]::WriteAllText($oldLog, 'the log before that')

        [void](InModuleScope HelpdeskToolkit { Write-AppLog -Message 'After the turn' })

        (Get-Item -LiteralPath $oldLog).Length | Should -BeGreaterThan 500KB
        @(Get-Content -LiteralPath $log).Count | Should -Be 1
        Get-Content -LiteralPath $log | Should -Match 'After the turn'
    }

    It 'returns nothing and does not fail when the file cannot be written' {
        [void](New-Item -Path $appData -ItemType Directory -Force)
        [void](InModuleScope HelpdeskToolkit { Write-AppLog -Message 'First' })
        $stream = [System.IO.File]::Open($log, 'Open', 'ReadWrite', 'None')
        try {
            { InModuleScope HelpdeskToolkit { Write-AppLog -Message 'While locked' } } | Should -Not -Throw
            InModuleScope HelpdeskToolkit { Write-AppLog -Message 'While locked' } | Should -BeNullOrEmpty
        }
        finally {
            $stream.Dispose()
        }
    }
}

Describe 'Write-WindowError' -Skip:(-not $isSta) {
    BeforeEach {
        if (Test-Path -LiteralPath $log) {
            Remove-Item -LiteralPath $log -Force
        }
        $gui = Get-TestWindow
    }

    It 'writes the error of a timer to the log and says where it is' {
        $failure = Get-TestFailure
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $failure } { Write-WindowError -Gui $Gui -ErrorRecord $Failure } | Should -BeTrue

        $gui.Controls.StatusText.Text | Should -Be "Something went wrong; the application keeps running. The details were written to $log"
        $lines = @(Get-Content -LiteralPath $log)
        $lines[0] | Should -Match '\[Error\] An unexpected error in the window'
        $lines[1] | Should -Match 'The printer of Contoso is jammed'
    }

    It 'finds the error of PowerShell inside the exception the window reports' {
        $failure = Get-TestFailure -Message 'The click went wrong'
        $wrapped = New-Object -TypeName System.Reflection.TargetInvocationException -ArgumentList 'An event handler failed', $failure.Exception

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Wrapped = $wrapped } { Write-WindowError -Gui $Gui -Exception $Wrapped } | Should -BeTrue

        # The error of the script is named, not the wrapper around it.
        $text = (Get-Content -LiteralPath $log) -join "`n"
        $text | Should -Match 'System\.Management\.Automation\.RuntimeException: The click went wrong'
        $text | Should -Not -Match 'An event handler failed'
    }

    It 'writes down where in the script the error the window reports happened' {
        # An exception as the window reports it: its error record knows the place.
        $failure = Get-TestFailure -Message 'The key went wrong'
        $exception = New-Object -TypeName System.Management.Automation.RuntimeException -ArgumentList 'The key went wrong', $null, $failure
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $exception } { Write-WindowError -Gui $Gui -Exception $Failure } | Should -BeTrue

        (Get-Content -LiteralPath $log) -join "`n" | Should -Match 'ErrorLog\.Tests\.ps1: line \d+' -Because 'the place in the script is what helps to find the cause'
    }

    It 'also takes an error that did not come from PowerShell' {
        $exception = New-Object -TypeName System.InvalidOperationException -ArgumentList 'The window is not ready'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $exception } { Write-WindowError -Gui $Gui -Exception $Failure } | Should -BeTrue
        (Get-Content -LiteralPath $log) -join "`n" | Should -Match 'System\.InvalidOperationException: The window is not ready'
    }

    It 'writes an error that repeats itself only once a minute' {
        $failure = Get-TestFailure
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $failure } { Write-WindowError -Gui $Gui -ErrorRecord $Failure } | Should -BeTrue
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $failure } { Write-WindowError -Gui $Gui -ErrorRecord $Failure } | Should -BeFalse
        @(Get-Content -LiteralPath $log | Where-Object { $_ -match '^\d{4}-' }).Count | Should -Be 1

        # Another error is written at once.
        $other = Get-TestFailure -Message 'Something else'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $other } { Write-WindowError -Gui $Gui -ErrorRecord $Failure } | Should -BeTrue

        # And the first one again after a minute.
        $gui.LastError = @{ Text = 'The printer of Contoso is jammed'; At = (Get-Date).AddSeconds(-61) }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $failure } { Write-WindowError -Gui $Gui -ErrorRecord $Failure } | Should -BeTrue
        @(Get-Content -LiteralPath $log | Where-Object { $_ -match '^\d{4}-' }).Count | Should -Be 3
    }

    It 'shows the error itself when the log cannot be written' {
        Mock -ModuleName HelpdeskToolkit Write-AppLog { }
        $failure = Get-TestFailure
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Failure = $failure } { Write-WindowError -Gui $Gui -ErrorRecord $Failure } | Should -BeFalse
        $gui.Controls.StatusText.Text | Should -Be 'Something went wrong; the application keeps running: The printer of Contoso is jammed'
    }
}

Describe 'A check that failed' -Skip:(-not $isSta) {
    It 'is written to the log' {
        if (Test-Path -LiteralPath $log) {
            Remove-Item -LiteralPath $log -Force
        }
        Mock -ModuleName HelpdeskToolkit Optimize-ProcessMemory { }
        $gui = Get-TestWindow
        $gui.Worker = [powershell]::Create()
        [void]$gui.Worker.AddScript('throw "The module could not be loaded"')
        $gui.Handle = $gui.Worker.BeginInvoke()
        [void]$gui.Handle.AsyncWaitHandle.WaitOne(10000)

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Receive-WindowCheck -Gui $Gui }

        $gui.Controls.StatusText.Text | Should -BeLike 'The check failed: *The module could not be loaded*'
        $text = (Get-Content -LiteralPath $log) -join "`n"
        $text | Should -Match '\[Error\] The check failed'
        $text | Should -Match 'The module could not be loaded'
    }
}

Describe 'How Show-PCHealthCheck deals with errors' {
    BeforeAll {
        $source = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Public\Show-PCHealthCheck.ps1'))
    }

    It 'lets every timer catch its own errors, because a timer that failed is never called again' {
        $ticks = [regex]::Matches($source, '(?s)\.Add_Tick\(\{(.*?)\n        \}\)')
        $ticks.Count | Should -Be 4
        foreach ($tick in $ticks) {
            $tick.Groups[1].Value | Should -Match '(?s)try \{.*\}\s+catch \{\s+\[void\]\(Write-WindowError -Gui \$script:HealthCheckWindow -ErrorRecord \$_\)'
        }
    }

    It 'lets every handler of the icon next to the clock catch its own errors, which the window would not hear' {
        $tray = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Private\Enable-WindowTrayIcon.ps1'))
        # Three entries of the menu, the click on the icon and the click on a notification
        $handlers = [regex]::Matches($tray, '(?s)(Add_Click|Add_MouseClick)\(\{(.*?)\n        \}\)|\$open = \{(.*?)\n    \}')
        $handlers.Count | Should -Be 5
        foreach ($handler in $handlers) {
            $handler.Value | Should -Match '(?s)try \{.*\}\s+catch \{\s+\[void\]\(Write-WindowError -Gui \$script:HealthCheckWindow -ErrorRecord \$_\)'
        }
    }

    It 'takes the errors nothing caught from the window and lets it stay open' {
        $source | Should -Match 'DispatcherUnhandledExceptionEventHandler'
        $source | Should -Match '\$window\.Dispatcher\.add_UnhandledException\(\$errorHandler\)'
        $source | Should -Match '\$window\.Dispatcher\.remove_UnhandledException\(\$errorHandler\)'
        $source | Should -Match '\$failure\.Handled = \$true'
    }
}
