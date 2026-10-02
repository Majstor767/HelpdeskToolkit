function Show-PCHealthCheck {
    <#
    .SYNOPSIS
        Opens the HelpdeskToolkit window for running the health check with the mouse.
    .DESCRIPTION
        When the window opens, it asks whether to run with administrator rights and
        then starts the check by itself: with "Yes" in a new, elevated window (after
        the confirmation Windows asks for), with "No" in this one with standard
        rights. The answer can be remembered. An elevated start asks nothing.

        The window has a "Run check" button and a list of pages:

        - Overview: the health score, every problem with its recommended fix and a
          button that opens the place in Windows where it is fixed, and what changed
          since the last check of this computer.
        - A page per category (System, Hardware, Network and so on) with all of its
          checks in four columns, one per status (Info, OK, Warning, Critical). A
          click on a card shows the explanation, the allowed range, the typical value
          and the recommendation.
        - Live monitor: what the computer is doing right now (processor, memory,
          graphics, disks, network, sensors and the busiest programs). It needs no
          check, can be paused, and can record its measurements into a CSV file. A dot
          on the tiles of processor, memory and graphics turns orange and red as the
          value approaches and passes its limit, with advice on what to do. A click
          on one of these tiles opens a page with everything that can be read about
          that component. Every drive can list the programs and folders that take up
          its space; a click on a program opens the page of Windows where it is removed.
        - Settings: language (English or Croatian), theme (light or dark) and how
          often the check is repeated by itself.

        When the window opens, it shows the results of the last check of this
        computer at once; the results of the new check replace them when it has
        finished. "Skip network tests" and the history period are remembered.

        After the first check the application repeats it in the background and
        replaces the results without interrupting. A problem that is new is announced
        at the top of the window and, while the window is not in front, with a Windows
        notification; a click leads to the result.

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
    .PARAMETER RunCheck
        Start the check as soon as the window is open, with the rights the window
        has, without asking about administrator rights.
    .PARAMETER NoQuestion
        Do not ask about administrator rights. Without -RunCheck the window then
        waits for a click on "Run check".
    .EXAMPLE
        Show-PCHealthCheck

        Opens the window, asks about administrator rights and runs the check.
    .EXAMPLE
        Show-PCHealthCheck -NoQuestion

        Opens the window and waits for "Run check".
    .EXAMPLE
        Show-PCHealthCheck -OutputPath C:\Temp\Reports

        Opens the window; reports opened from it are saved to C:\Temp\Reports.
    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'HelpdeskToolkit'),

        [switch]$RunCheck,

        [switch]$NoQuestion
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
    $gui.Startup = @{ RunCheck = [bool]$RunCheck; NoQuestion = [bool]$NoQuestion }

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

    # The two options of a check are remembered from the last time.
    $controls.SkipNetworkCheckBox.IsChecked = [bool]$settings.SkipNetwork
    $daysItem = $controls.DaysComboBox.Items | Where-Object { [int]$_.Tag -eq [int]$settings.HistoryDays } | Select-Object -First 1
    if ($daysItem) {
        $controls.DaysComboBox.SelectedItem = $daysItem
    }
    $saveOptions = {
        $state = $script:HealthCheckWindow
        $state.Settings.SkipNetwork = $state.Controls.SkipNetworkCheckBox.IsChecked -eq $true
        if ($state.Controls.DaysComboBox.SelectedItem) {
            $state.Settings.HistoryDays = [int]$state.Controls.DaysComboBox.SelectedItem.Tag
        }
        [void](Save-AppSetting -Setting $state.Settings)
    }
    $controls.SkipNetworkCheckBox.Add_Click($saveOptions)
    $controls.DaysComboBox.Add_SelectionChanged($saveOptions)

    # Looks every few seconds whether it is time to repeat the check (see Invoke-WindowAutoCheck).
    $gui.AutoTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
    $gui.AutoTimer.Interval = [timespan]::FromSeconds(15)
    $gui.AutoTimer.Add_Tick({ [void](Invoke-WindowAutoCheck -Gui $script:HealthCheckWindow) })
    $gui.AutoTimer.Start()

    # A click on a notice opens its result; the button next to them dismisses them all.
    $controls.NoticeItems.AddHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, [System.Windows.Input.MouseButtonEventHandler] {
            $item = $args[1].OriginalSource.DataContext
            if ($item -and $item.PSObject.Properties['Check']) {
                [void](Show-WindowResult -Gui $script:HealthCheckWindow -Category $item.Category -Check $item.Check)
            }
        })
    $controls.NoticeCloseButton.Add_Click({ Show-WindowNotice -Gui $script:HealthCheckWindow -Clear })

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
    $controls.ElevateButton.Add_Click({ [void](Invoke-ElevatedRestart -Gui $script:HealthCheckWindow -RunCheck) })

    # The question at the start and its two answers. The window decides what to do once
    # it has been drawn for the first time (see Invoke-WindowStartup).
    $controls.StartupYesButton.Add_Click({ [void](Invoke-WindowElevationChoice -Gui $script:HealthCheckWindow -Elevate) })
    $controls.StartupNoButton.Add_Click({ [void](Invoke-WindowElevationChoice -Gui $script:HealthCheckWindow) })
    # The moment the window is drawn, it shows what the last check found, so there is
    # something to read while the new check runs.
    $window.Add_ContentRendered({
            $state = $script:HealthCheckWindow
            [void](Show-WindowLastReport -Gui $state)
            [void](Invoke-WindowStartup -Gui $state)
        })

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

    # The filter of the Timeline page: everything, only the problems or only the changes.
    $controls.TimelineFilter.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            if (-not $state.Loading -and $state.Page -eq 'Timeline') {
                Show-WindowTimeline -Gui $state
            }
        })

    # The button inside a card opens the place in Windows where the problem is fixed.
    # The cards are created from a template, so the click is caught on the list that
    # contains them; the card it came from is the "data context" of the button.
    # The same goes for the compact cards in the columns of a category page, where a
    # click on the card itself opens and closes its details (see Invoke-WindowCardClick).
    $cardClick = [System.Windows.RoutedEventHandler] {
        # An event handler receives the sender and the details of the event.
        Invoke-WindowCardClick -Gui $script:HealthCheckWindow -Source $args[1].OriginalSource
    }
    $controls.ResultItems.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $cardClick)
    $controls.ColumnsPanel.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, $cardClick)

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

    # The warning triangle on a tile opens the advice for that value; the button below
    # the advice opens Task Manager.
    $controls.MonitorCpuAdviceButton.Add_Click({ Switch-WindowAdvice -Gui $script:HealthCheckWindow -Name 'Cpu' })
    $controls.MonitorMemoryAdviceButton.Add_Click({ Switch-WindowAdvice -Gui $script:HealthCheckWindow -Name 'Memory' })
    $controls.MonitorGpuAdviceButton.Add_Click({ Switch-WindowAdvice -Gui $script:HealthCheckWindow -Name 'Gpu' })
    $controls.MonitorAdviceAction.Add_Click({
            $state = $script:HealthCheckWindow
            $entry = @($state.MonitorStatus) | Where-Object { $_.Name -eq $state.MonitorAdvice } | Select-Object -First 1
            if ($entry -and -not (Invoke-CheckAction -Check $entry.ActionCheck -Category 'Hardware')) {
                $state.Controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
            }
        })

    # A click on the tile of the processor, the memory or the graphics card opens the
    # page with everything about it. (A click on the triangle inside a tile is used up
    # by the triangle and does not arrive here.)
    $controls.MonitorCpuTile.Add_MouseLeftButtonUp({ Open-WindowComponent -Gui $script:HealthCheckWindow -Name 'Cpu' })
    $controls.MonitorMemoryTile.Add_MouseLeftButtonUp({ Open-WindowComponent -Gui $script:HealthCheckWindow -Name 'Memory' })
    $controls.MonitorGpuTile.Add_MouseLeftButtonUp({ Open-WindowComponent -Gui $script:HealthCheckWindow -Name 'Gpu' })
    $controls.ComponentBackButton.Add_Click({ Close-WindowComponent -Gui $script:HealthCheckWindow })
    $controls.ComponentRefreshButton.Add_Click({
            $state = $script:HealthCheckWindow
            if ($state.MonitorComponent) {
                Invoke-WindowComponentDetail -Gui $state -Name $state.MonitorComponent
                Show-WindowComponentDetail -Gui $state
            }
        })
    $controls.ComponentAdviceAction.Add_Click({
            $state = $script:HealthCheckWindow
            $entry = @($state.MonitorStatus) | Where-Object { $_.Name -eq $state.MonitorComponent } | Select-Object -First 1
            if ($entry -and -not (Invoke-CheckAction -Check $entry.ActionCheck -Category 'Hardware')) {
                $state.Controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
            }
        })

    # A click on a program in "What takes up the space" opens the page of Windows where
    # it is removed.
    $controls.MonitorVolumes.AddHandler([System.Windows.UIElement]::MouseLeftButtonUpEvent, [System.Windows.Input.MouseButtonEventHandler] {
            $item = $args[1].OriginalSource.DataContext
            if ($item -and $item.PSObject.Properties['Kind'] -and $item.Kind -eq 'Program') {
                [void](Open-WindowUninstall -Gui $script:HealthCheckWindow -Name $item.Name)
            }
        })

    # The drives: the line below a meter opens what takes up the space, and the buttons
    # in that box open the pages of Windows where programs and files are removed. Like
    # the result cards they come from a template, so the click is caught on the list.
    $controls.MonitorVolumes.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
            $clicked = $args[1].OriginalSource
            $state = $script:HealthCheckWindow
            $item = $clicked.DataContext
            if (-not $item -or -not $item.PSObject.Properties['Drive']) {
                return
            }
            $opened = $true
            switch ($clicked.Name) {
                'VolumeToggle' { Switch-WindowVolume -Gui $state -Drive $item.Drive }
                'VolumeRefreshButton' { Switch-WindowVolume -Gui $state -Drive $item.Drive -Refresh }
                'VolumeAppsButton' { $opened = Invoke-CheckAction -Check 'Installed programs' -Category 'Software' }
                'VolumeStorageButton' { $opened = Invoke-CheckAction -Check 'Disk' -Category 'Hardware' }
            }
            if (-not $opened) {
                $state.Controls.StatusText.Text = Get-LocalizedText 'Windows could not open that place.'
            }
        })

    # --- Settings ----------------------------------------------------------------
    $controls.SettingsButton.Add_Click({ Show-WindowPage -Gui $script:HealthCheckWindow -Name 'Settings' })

    # The language is stored at once and applied by the next start.
    $controls.LanguageBox.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            if ($state.Loading -or -not $state.Controls.LanguageBox.SelectedItem) {
                return
            }
            $state.Settings.Language = [string]$state.Controls.LanguageBox.SelectedItem.Tag
            [void](Save-AppSetting -Setting $state.Settings)
            $state.Controls.RestartButton.Visibility = [System.Windows.Visibility]::Visible
        })

    # The theme changes at once: with the switch in the header, which turns it over,
    # and with the list of the Settings page, which also offers "Same as Windows".
    $controls.ThemeToggle.Add_Click({ [void](Switch-WindowTheme -Gui $script:HealthCheckWindow) })
    $controls.ThemeBox.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            if ($state.Loading -or -not $state.Controls.ThemeBox.SelectedItem) {
                return
            }
            [void](Switch-WindowTheme -Gui $state -Setting ([string]$state.Controls.ThemeBox.SelectedItem.Tag))
        })
    $controls.RestartButton.Add_Click({ [void](Invoke-AppRestart -Gui $script:HealthCheckWindow) })

    # What happens at the next start
    $controls.StartupBox.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            if ($state.Loading -or -not $state.Controls.StartupBox.SelectedItem) {
                return
            }
            $state.Settings.StartupElevation = [string]$state.Controls.StartupBox.SelectedItem.Tag
            [void](Save-AppSetting -Setting $state.Settings)
        })

    # The interval of the automatic check applies at once.
    $controls.AutoCheckBox.Add_SelectionChanged({
            $state = $script:HealthCheckWindow
            if ($state.Loading -or -not $state.Controls.AutoCheckBox.SelectedItem) {
                return
            }
            $state.Settings.AutoCheckMinutes = [int]$state.Controls.AutoCheckBox.SelectedItem.Tag
            [void](Save-AppSetting -Setting $state.Settings)
        })

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
            $state.AutoTimer.Stop()
            Disable-WindowMonitor -Gui $state -Stop
            if ($state.Worker) {
                [void]$state.Worker.BeginStop($null, $null)
            }
            foreach ($usage in @($state.DiskUsage.Values) + @($state.ComponentDetail.Values)) {
                if ($usage.Worker) {
                    [void]$usage.Worker.BeginStop($null, $null)
                }
            }
            # Takes the icon out of the notification area.
            if ($state.TrayIcon) {
                $state.TrayIcon.Visible = $false
                $state.TrayIcon.Dispose()
            }
        })

    # While the window exists, the installer must not replace the files of the application.
    $gui.AppLock = Lock-AppFile

    try {
        [void]$window.ShowDialog()
    }
    finally {
        if ($gui.AppLock) {
            $gui.AppLock.Dispose()
        }
        $script:HealthCheckWindow = $null
    }
}
