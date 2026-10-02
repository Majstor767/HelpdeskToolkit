function New-HealthCheckWindow {
    <#
    .SYNOPSIS
        Creates the application window from Assets\MainWindow.xaml without showing it.
    .DESCRIPTION
        The window is built with WPF, which is part of Windows, so nothing has to be
        installed. The XAML file describes the layout; this function loads it and
        returns one table that the other window functions pass around:

        - Window:       the window object
        - Controls:     every element that has an x:Name in the XAML, by that name
        - ManifestPath: where the module is, for the background runspaces
        - Settings, Theme, Palette: the settings of the window, the theme that is on,
          and the colors of both themes (see Set-WindowTheme)
        - Page:         name of the page that is shown
        - CardState:    which compact result cards the user has opened or closed, by
                        "category|check" (see Show-WindowPage)
        - AppLock:      the file that tells the installer the application is running
                        (see Lock-AppFile)
        - Startup:      how the window was asked to start (see Invoke-WindowStartup)
        - Report, PreviousReport, Worker, Handle, Timer: state of the health check
        - Background, LastCheckAt, AutoTimer, Notices, HighlightCheck, TrayIcon:
                        state of the automatic check and of what it announces
        - Monitor, MonitorTimer, MonitorHistory, MonitorUserPaused, Recorder:
                        state of the Live monitor page
        - MonitorStatus, MonitorAdvice: the status dots of its tiles and the advice
                        that is open
        - MonitorVolumes, VolumeSignature, DiskUsage: the drives and what takes up
                        their space
        - MonitorSnapshot, MonitorComponent, ComponentDetail: the newest measurement,
                        the component whose detail page is open ("Cpu", "Memory",
                        "Gpu" or nothing) and what was read about each component

        Before the XAML becomes a window, two things are changed in it:

        - Theme:    for the dark theme, the color of every named brush is replaced
                    with the one in Assets\DarkTheme.psd1. The theme can be changed
                    later, while the window is open (Set-WindowTheme).
        - Language: every text written in the XAML is replaced with its translation
                    (see Get-LocalizedText). The language is the one in $script:Language.

        The page list starts with the pages that need no health check: Overview and
        Live monitor. The settings have a button of their own below the list.
    .PARAMETER Theme
        "Light" (the default) or "Dark".
    .PARAMETER Setting
        The settings of the window, as returned by Get-AppSetting. Without it the
        defaults are used and nothing is read from the disk, which the tests rely on.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds a window object in memory; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateSet('Light', 'Dark')]
        [string]$Theme = 'Light',

        [hashtable]$Setting = @{ Language = 'en'; Theme = 'System'; MonitorIntervalSeconds = 2; AutoCheckMinutes = 5; StartupElevation = 'Ask'; SkipNetwork = $false; HistoryDays = 7 }
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $path = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\MainWindow.xaml'
    [xml]$xaml = Get-Content -LiteralPath $path -Raw

    $xamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $namespaces = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $xaml.NameTable
    $namespaces.AddNamespace('x', $xamlNamespace)

    # The colors of both themes, by the name of the brush: the light ones as the
    # layout has them, the dark ones from Assets\DarkTheme.psd1 (a brush that is not
    # listed there keeps its color). They are kept for switching the theme later.
    $darkColors = Import-PowerShellDataFile -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\DarkTheme.psd1')
    $palettes = @{ Light = @{}; Dark = @{} }
    foreach ($brush in $xaml.SelectNodes('//*[local-name()="SolidColorBrush"][@x:Key]', $namespaces)) {
        $key = $brush.GetAttribute('Key', $xamlNamespace)
        $palettes.Light[$key] = $brush.GetAttribute('Color')
        $palettes.Dark[$key] = if ($darkColors.ContainsKey($key)) { $darkColors[$key] } else { $brush.GetAttribute('Color') }

        # Dark theme from the start: the window is built with those colors.
        if ($Theme -eq 'Dark') {
            $brush.SetAttribute('Color', $palettes.Dark[$key])
        }
    }

    # Language: texts written in the XAML. A value in braces is a binding, not a text.
    if ($script:Language -and $script:Language -ne 'en') {
        foreach ($node in $xaml.SelectNodes('//*[@Text or @Content or @ToolTip or @Title]')) {
            foreach ($attribute in 'Text', 'Content', 'ToolTip', 'Title') {
                $value = $node.GetAttribute($attribute)
                if ($value -and -not $value.StartsWith('{')) {
                    $node.SetAttribute($attribute, (Get-LocalizedText $value))
                }
            }
        }
    }

    $reader = New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # Without an icon of its own the window would show the PowerShell icon.
    $iconPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\HelpdeskToolkit.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object -TypeName System.Uri -ArgumentList $iconPath))
    }

    # Collect the named elements, so the code can write $controls.RunButton
    # instead of calling FindName everywhere.
    $controls = @{}
    foreach ($node in $xaml.SelectNodes('//*[@x:Name]', $namespaces)) {
        $name = $node.GetAttribute('Name', $xamlNamespace)
        $element = $window.FindName($name)
        # Names inside a template belong to that template and cannot be found on the window.
        if ($element) {
            $controls[$name] = $element
        }
    }

    $controls.CategoryList.ItemsSource = @(
        ConvertTo-WindowNavigationItem -Name 'Overview'
        ConvertTo-WindowNavigationItem -Name 'Live monitor' -EmptyStatus 'Info'
    )

    # The switch in the header starts on the side of the theme that is on.
    $controls.ThemeToggle.IsChecked = $Theme -eq 'Dark'
    if ($Theme -eq 'Dark') {
        $controls.ThemeToggle.ToolTip = Get-LocalizedText 'Switch to the light theme (Ctrl+T)'
    }

    $newHistory = { New-Object -TypeName 'System.Collections.Generic.List[double]' }

    @{
        Window            = $window
        Controls          = $controls
        ManifestPath      = Join-Path -Path $script:ModuleRoot -ChildPath 'HelpdeskToolkit.psd1'
        Settings          = $Setting
        Theme             = $Theme
        # The colors of the light and of the dark theme, by the name of the brush.
        Palette           = $palettes
        Page              = 'Overview'
        CardState         = @{}
        AppLock           = $null
        # RunCheck: start the check at once. NoQuestion: do not ask about administrator rights.
        Startup           = @{ RunCheck = $false; NoQuestion = $false }
        Report            = $null
        PreviousReport    = $null
        # The report on the screen is the one of an earlier start of the application,
        # shown until the first check of this start has finished (see Show-WindowLastReport).
        StaleReport       = $false
        Worker            = $null
        Handle            = $null
        Timer             = $null
        # The running check was started by the application itself (see Invoke-WindowAutoCheck).
        Background        = $false
        # The progress of the running check that is on the screen (see Receive-WindowCheck).
        RunStep           = ''
        # When the last check ended; the automatic check counts from here.
        LastCheckAt       = $null
        AutoTimer         = $null
        # Problems found by an automatic check that the user has not dismissed yet,
        # by "category|check", oldest first.
        Notices           = [ordered]@{}
        # Name of the check whose card gets a frame when its page is shown the next time.
        HighlightCheck    = ''
        # The icon in the notification area; created with the first Windows notification.
        TrayIcon          = $null
        Monitor           = $null
        MonitorTimer      = $null
        # The user pressed Pause; opening the page again must not resume by itself.
        MonitorUserPaused = $false
        # State of a recording of the Live monitor into a file (see Enable-WindowRecording).
        Recorder          = $null
        # The last measurements of the values that are drawn as graphs, oldest first.
        MonitorHistory    = @{
            Cpu          = & $newHistory
            Memory       = & $newHistory
            Gpu          = & $newHistory
            Disk         = & $newHistory
            NetworkDown  = & $newHistory
            NetworkUp    = & $newHistory
            # Answer time of the internet in milliseconds; -1 for a measurement without an answer
            Latency      = & $newHistory
        }
        # The judgements behind the status dots of the tiles, and the tile whose advice is open.
        MonitorStatus     = @()
        MonitorAdvice     = ''
        # The drives of the last measurement, what is drawn for them, and per drive
        # letter what takes up its space (see Switch-WindowVolume).
        MonitorVolumes    = @()
        VolumeSignature   = ''
        DiskUsage         = @{}
        # The newest measurement, kept for the detail page of a component; the component
        # whose page is open; and per component what was read about it in the background.
        MonitorSnapshot   = $null
        MonitorComponent  = ''
        ComponentDetail   = @{}
        # Set while the code itself changes a selection, so the event handlers do not react.
        Loading           = $false
    }
}
