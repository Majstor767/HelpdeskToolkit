function Show-PCHealthCheck {
    <#
    .SYNOPSIS
        Opens the HelpdeskToolkit window for running the health check with the mouse.
    .DESCRIPTION
        Shows a window with a "Run check" button and a list of pages:

        - Overview: the health score, every problem with its recommended fix and a
          button that opens the place in Windows where it is fixed, and what changed
          since the last check of this computer.
        - A page per category (System, Hardware, Network and so on) with all of its
          checks, each with an explanation, the allowed range and the typical value.
        - Live monitor: what the computer is doing right now (processor, memory,
          graphics, disks, network, sensors and the busiest programs). It needs no
          check, can be paused, and can record its measurements into a CSV file.
        - Settings: language (English or Croatian) and theme (light or dark).

        The results can be searched and filtered by status. The report can be opened
        in the browser, saved as HTML, PDF, JSON or CSV, or copied as a short text for
        a ticket.

        The window runs exactly the same checks as Invoke-PCHealthCheck; it only
        presents them differently. The checks run in the background, so the window
        stays responsive. Nothing on the computer is changed. The window keeps its own
        settings and a copy of each report in %LOCALAPPDATA%\HelpdeskToolkit.

        No administrator rights are needed. Checks that need them are marked "Requires
        admin"; the "Restart as administrator" button starts the window again
        elevated, after the user has confirmed the Windows prompt, and then includes them.

        The command returns when the window is closed.
    .PARAMETER OutputPath
        Folder used by the "Open HTML report" button and for recordings of the Live
        monitor. It is created when needed. Defaults to a HelpdeskToolkit folder
        inside the current user's Documents.
    .EXAMPLE
        Show-PCHealthCheck

        Opens the window.
    .EXAMPLE
        Show-PCHealthCheck -OutputPath C:\Temp\Reports

        Opens the window; reports opened from it are saved to C:\Temp\Reports.
    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'HelpdeskToolkit')
    )

    # WPF windows can only be created on a single-threaded apartment (STA) thread.
    # powershell.exe and pwsh.exe start that way unless they were launched with -MTA.
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw 'Show-PCHealthCheck needs a single-threaded (STA) PowerShell session. Start PowerShell without the -MTA switch.'
    }

    # Language and theme are fixed when the window is created.
    $settings = Get-AppSetting
    $script:Language = $settings.Language
    $gui = New-HealthCheckWindow -Theme (Get-WindowTheme -Setting $settings.Theme) -Setting $settings
    $gui.OutputFolder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)

    # The event handlers below run later, when a button is clicked. They reach the
    # window through this module-level variable.
    $script:HealthCheckWindow = $gui

    $controls = $gui.Controls
    $window = $gui.Window
    $controls.ComputerText.Text = (Get-LocalizedText 'Computer: {0}') -f $env:COMPUTERNAME

    # Size and place of the window from the last time, when they still fit on the screen.
    if ($settings.WindowWidth -and $settings.WindowHeight) {
        $screenLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
        $screenTop = [System.Windows.SystemParameters]::VirtualScreenTop
        $screenRight = $screenLeft + [System.Windows.SystemParameters]::VirtualScreenWidth
        $screenBottom = $screenTop + [System.Windows.SystemParameters]::VirtualScreenHeight

        $window.Width = [math]::Max($window.MinWidth, [double]$settings.WindowWidth)
        $window.Height = [math]::Max($window.MinHeight, [double]$settings.WindowHeight)
        if ($null -ne $settings.WindowLeft -and $null -ne $settings.WindowTop -and
            [double]$settings.WindowLeft -ge $screenLeft -and [double]$settings.WindowTop -ge $screenTop -and
            [double]$settings.WindowLeft + 100 -le $screenRight -and [double]$settings.WindowTop + 100 -le $screenBottom) {
            $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
            $window.Left = [double]$settings.WindowLeft
            $window.Top = [double]$settings.WindowTop
        }
        if ($settings.WindowMaximized) {
            $window.WindowState = [System.Windows.WindowState]::Maximized
        }
    }

    # Polls the background check a few times per second (see Receive-WindowCheck).
    $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
    $gui.Timer.Interval = [timespan]::FromMilliseconds(200)
    $gui.Timer.Add_Tick({ Receive-WindowCheck -Gui $script:HealthCheckWindow })

    $controls.RunButton.Add_Click({ Invoke-WindowCheck -Gui $script:HealthCheckWindow })

    # Shows new measurements on the Live monitor page (see Receive-WindowMonitor). The
    # timer only runs while that page is open or a recording is under way.
    $gui.MonitorTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
    $gui.MonitorTimer.Interval = [timespan]::FromMilliseconds(400)
    $gui.MonitorTimer.Add_Tick({ Receive-WindowMonitor -Gui $script:HealthCheckWindow })

    # With administrator rights there is nothing left to elevate.
    if (Test-IsAdministrator) {
        $controls.ElevationText.Text = Get-LocalizedText 'Running as administrator: all checks are included.'
        $controls.ElevateButton.Visibility = [System.Windows.Visibility]::Collapsed
    }
    $controls.ElevateButton.Add_Click({ [void](Invoke-ElevatedRestart -Gui $script:HealthCheckWindow) })

    # Choosing an entry in the page list shows that page on the right. A search belongs
    # to the page it was typed on, so it is cleared.
    $controls.CategoryList.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            if ($state.Loading) {
                return
            }
            $state.Loading = $true
            try {
                $state.Controls.SearchBox.Text = ''
            }
            finally {
                $state.Loading = $false
            }
            Show-WindowPage -Gui $state
        })

    # Search text and status filter narrow down the cards of the page.
    $controls.SearchBox.Add_TextChanged({
            $state = $script:HealthCheckWindow
            if (-not $state.Loading) {
                Show-WindowPage -Gui $state
            }
        })
    $controls.StatusFilter.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            if (-not $state.Loading) {
                Show-WindowPage -Gui $state
            }
        })

    # The button inside a card opens the place in Windows where the problem is fixed.
    # The cards are created from a template, so the click is caught on the list that
    # contains them; the card it came from is the "data context" of the button.
    $controls.ResultItems.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
            # An event handler receives the sender and the details of the event.
            $clicked = $args[1].OriginalSource
            $state = $script:HealthCheckWindow
            $item = $clicked.DataContext
            if ($clicked -is [System.Windows.Controls.Button] -and $item -and $item.PSObject.Properties['SourceCheck']) {
                if (-not (Invoke-CheckAction -Check $item.SourceCheck -Category $item.SourceCategory)) {
                    $state.Controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
                }
            }
        })

    # Saves the report as HTML in the output folder and opens it in the browser.
    $controls.OpenReportButton.Add_Click({
            $state = $script:HealthCheckWindow
            $fileName = '{0}.html' -f (Get-ReportFileName -Report $state.Report)
            $path = Export-WindowReport -Gui $state -Path (Join-Path -Path $state.OutputFolder -ChildPath $fileName)
            if ($path) {
                Open-HealthReport -Path $path
            }
        })

    $controls.CopySummaryButton.Add_Click({ [void](Copy-WindowSummary -Gui $script:HealthCheckWindow) })

    # Lets the user choose the place, the name and the format.
    $controls.SaveAsButton.Add_Click({
            $state = $script:HealthCheckWindow
            $dialog = New-Object -TypeName Microsoft.Win32.SaveFileDialog
            $dialog.Title = Get-LocalizedText 'Save report'
            $dialog.Filter = 'HTML (*.html)|*.html|PDF (*.pdf)|*.pdf|JSON (*.json)|*.json|CSV (*.csv)|*.csv'
            $dialog.FileName = Get-ReportFileName -Report $state.Report

            if ($dialog.ShowDialog($state.Window)) {
                $state.Controls.StatusText.Text = Get-LocalizedText 'Saving the report ...'
                [void](Export-WindowReport -Gui $state -Path $dialog.FileName)
            }
        })

    # --- Live monitor ------------------------------------------------------------
    $controls.MonitorPauseButton.Add_Click({ Switch-WindowMonitorPause -Gui $script:HealthCheckWindow })

    $intervalItem = $controls.MonitorIntervalBox.Items | Where-Object { [int]$_.Tag -eq [int]$settings.MonitorIntervalSeconds } | Select-Object -First 1
    if ($intervalItem) {
        $controls.MonitorIntervalBox.SelectedItem = $intervalItem
    }
    $controls.MonitorIntervalBox.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            $seconds = [int]$state.Controls.MonitorIntervalBox.SelectedItem.Tag
            $state.Settings.MonitorIntervalSeconds = $seconds
            if ($state.Monitor) {
                $state.Monitor.Shared.IntervalSeconds = $seconds
            }
            [void](Save-AppSetting -Setting $state.Settings)
        })

    $controls.MonitorRecordButton.Add_Click({
            $state = $script:HealthCheckWindow
            if ($state.Recorder) {
                Disable-WindowRecording -Gui $state
            }
            else {
                try {
                    [void](Enable-WindowRecording -Gui $state -Minutes ([int]$state.Controls.MonitorRecordMinutes.SelectedItem.Tag))
                }
                catch {
                    $state.Controls.StatusText.Text = (Get-LocalizedText 'The recording could not be started: {0}') -f $_.Exception.Message
                }
            }
        })

    # A click on a program in one of the three lists shows its details.
    $showProgram = [System.Windows.Input.MouseButtonEventHandler] {
        $item = $args[1].OriginalSource.DataContext
        if ($item -and $item.PSObject.Properties['Name']) {
            Show-WindowProgram -Gui $script:HealthCheckWindow -Name $item.Name
        }
    }
    foreach ($list in $controls.MonitorProcesses, $controls.MonitorMemoryProcesses, $controls.MonitorIoProcesses) {
        $list.AddHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, $showProgram)
    }

    # --- Settings ----------------------------------------------------------------
    # Language and theme are stored at once and applied by the next start.
    $changeSetting = {
        $state = $script:HealthCheckWindow
        if ($state.Loading) {
            return
        }
        $state.Settings.Language = [string]$state.Controls.LanguageBox.SelectedItem.Tag
        $state.Settings.Theme = [string]$state.Controls.ThemeBox.SelectedItem.Tag
        [void](Save-AppSetting -Setting $state.Settings)
        $state.Controls.RestartButton.Visibility = [System.Windows.Visibility]::Visible
    }
    $controls.LanguageBox.Add_SelectionChanged($changeSetting)
    $controls.ThemeBox.Add_SelectionChanged($changeSetting)
    $controls.RestartButton.Add_Click({ [void](Invoke-AppRestart -Gui $script:HealthCheckWindow) })

    $controls.OpenDataFolderButton.Add_Click({
            $folder = Get-AppDataPath
            if (-not (Test-Path -LiteralPath $folder)) {
                New-Item -Path $folder -ItemType Directory -Force | Out-Null
            }
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $folder)
        })

    # --- Keyboard shortcuts ------------------------------------------------------
    $window.Add_PreviewKeyDown({
            $keyEvent = $args[1]
            $modifiers = [System.Windows.Input.Keyboard]::Modifiers
            $handled = Invoke-WindowShortcut -Gui $script:HealthCheckWindow -Key ([string]$keyEvent.Key) `
                -Control:(($modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0) `
                -Shift:(($modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0)
            if ($handled) {
                $keyEvent.Handled = $true
            }
        })

    # Closing the window stops the background work and remembers where the window was.
    $window.Add_Closing({
            $state = $script:HealthCheckWindow
            $bounds = $state.Window.RestoreBounds
            if (-not $bounds.IsEmpty) {
                $state.Settings.WindowWidth = [int]$bounds.Width
                $state.Settings.WindowHeight = [int]$bounds.Height
                $state.Settings.WindowLeft = [int]$bounds.Left
                $state.Settings.WindowTop = [int]$bounds.Top
            }
            $state.Settings.WindowMaximized = $state.Window.WindowState -eq [System.Windows.WindowState]::Maximized
            [void](Save-AppSetting -Setting $state.Settings)
        })
    $window.Add_Closed({
            $state = $script:HealthCheckWindow
            $state.Timer.Stop()
            Disable-WindowMonitor -Gui $state -Stop
            if ($state.Worker) {
                [void]$state.Worker.BeginStop($null, $null)
            }
        })

    try {
        [void]$window.ShowDialog()
    }
    finally {
        $script:HealthCheckWindow = $null
    }
}
