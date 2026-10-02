<#
.SYNOPSIS
    Creates the screenshots and the animation used in the README files from fictional data.
.DESCRIPTION
    Writes these files to the docs folder:

    - screenshot-report.png:          the top of docs\sample-report.html, rendered by
                                      Microsoft Edge in headless mode
    - screenshot-window.png:          the Overview page of the application window
    - screenshot-category.png:        the page of one category, reached through the notice
                                      of an automatic check
    - screenshot-monitor.png:         the Live monitor page with an invented measurement
                                      and the advice for a value above its limit
    - screenshot-monitor-disks.png:   what takes up the space of a drive
    - screenshot-component.png:       the detail page of the processor
    - screenshot-monitor-details.png: the lower end of the same page
    - screenshot-dark-hr.png:         the Overview in the dark theme and in Croatian
    - demo.gif:                       an animation that shows the pages one after the other

    All of them are generated from invented data (docs\sample-report.json and a
    measurement defined in this script), so the pictures never show a real computer
    and can be rebuilt after a layout change.
    Run tools\New-SampleReport.ps1 first when the report itself has changed.

    The window is drawn off-screen; nothing appears on the desktop, and the settings and
    the history of the application are neither read nor written.
.PARAMETER OutputPath
    Folder for the pictures. Defaults to the docs folder of the repository.
.EXAMPLE
    .\tools\New-Screenshot.ps1

    Rewrites the docs\screenshot-*.png files and docs\demo.gif.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Build script that writes generated pictures.')]
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# The defaults are set here and not in the param block: Windows PowerShell 5.1 does not
# know $PSScriptRoot yet while it evaluates parameter defaults of a script run with -File.
$root = Split-Path -Path $PSScriptRoot -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $root -ChildPath 'docs'
}
$outputFolder = (Resolve-Path -LiteralPath $OutputPath).Path
$sampleHtml = Join-Path -Path $root -ChildPath 'docs\sample-report.html'
$sampleJson = Join-Path -Path $root -ChildPath 'docs\sample-report.json'

# --- HTML report -------------------------------------------------------------------

$candidates = foreach ($folder in ${env:ProgramFiles(x86)}, $env:ProgramFiles) {
    if ($folder) {
        Join-Path -Path $folder -ChildPath 'Microsoft\Edge\Application\msedge.exe'
    }
}
$edge = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $edge) {
    throw 'Microsoft Edge was not found; it is needed to render the HTML report to a picture.'
}

$reportPicture = Join-Path -Path $outputFolder -ChildPath 'screenshot-report.png'
$arguments = @(
    '--headless=new'
    '--disable-gpu'
    '--hide-scrollbars'
    # Always render the light theme, whatever the theme of this computer is.
    '--blink-settings=preferredColorScheme=1'
    '--window-size=1200,1340'
    ('--screenshot="{0}"' -f $reportPicture)
    ('"{0}"' -f ([System.Uri]$sampleHtml).AbsoluteUri)
)
Start-Process -FilePath $edge -ArgumentList $arguments -Wait
Write-Output $reportPicture

# --- Application window ------------------------------------------------------------

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    throw 'The window screenshots need a single-threaded (STA) PowerShell session.'
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$module = Import-Module -Name (Join-Path -Path $root -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force -PassThru
$pictures = @{
    Window         = Join-Path -Path $outputFolder -ChildPath 'screenshot-window.png'
    Category       = Join-Path -Path $outputFolder -ChildPath 'screenshot-category.png'
    Monitor        = Join-Path -Path $outputFolder -ChildPath 'screenshot-monitor.png'
    MonitorDisks   = Join-Path -Path $outputFolder -ChildPath 'screenshot-monitor-disks.png'
    Component      = Join-Path -Path $outputFolder -ChildPath 'screenshot-component.png'
    MonitorDetails = Join-Path -Path $outputFolder -ChildPath 'screenshot-monitor-details.png'
    Dark           = Join-Path -Path $outputFolder -ChildPath 'screenshot-dark-hr.png'
    Search         = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('HelpdeskToolkit-frame-{0}.png' -f [guid]::NewGuid())
}

# The window functions are private, so the block runs inside the module scope.
& $module {
    param($SampleJson, $Pictures)

    # Draws the content of the window into a PNG file.
    $savePicture = {
        param($Window, $Path)

        # Let WPF finish layout and drawing before the picture is taken.
        $Window.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

        $content = $Window.Content
        $width = [int]$content.ActualWidth
        $height = [int]$content.ActualHeight
        $area = New-Object -TypeName System.Windows.Rect -ArgumentList 0, 0, $width, $height

        $visual = New-Object -TypeName System.Windows.Media.DrawingVisual
        $context = $visual.RenderOpen()
        $context.DrawRectangle($Window.Background, $null, $area)
        $context.DrawRectangle((New-Object -TypeName System.Windows.Media.VisualBrush -ArgumentList $content), $null, $area)
        $context.Close()

        $bitmap = New-Object -TypeName System.Windows.Media.Imaging.RenderTargetBitmap -ArgumentList $width, $height, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($visual)

        $encoder = New-Object -TypeName System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [System.IO.File]::Create($Path)
        try {
            $encoder.Save($stream)
        }
        finally {
            $stream.Dispose()
        }
    }

    # Creates a window far outside the visible desktop: WPF only lays out a window that is shown.
    $newWindow = {
        param([string]$Theme)

        $gui = New-HealthCheckWindow -Theme $Theme
        $gui.Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
        $gui.Window.Left = -10000
        $gui.Window.Top = 0
        $gui.Window.ShowInTaskbar = $false
        $gui.Window.ShowActivated = $false
        $gui.Window.Show()
        $gui
    }

    $report = Import-HealthReport -Path $SampleJson

    # An invented report of the week before, so the Overview has changes to show: the
    # memory was fine then, and a printer problem of that day is gone.
    $previous = Import-HealthReport -Path $SampleJson
    $previous.GeneratedAt = '2026-09-23 08:57:10'
    ($previous.Results | Where-Object { $_.Check -eq 'Memory usage' }).Status = 'OK'
    ($previous.Results | Where-Object { $_.Check -eq 'Temporary files' }).Status = 'OK'
    ($previous.Results | Where-Object { $_.Check -eq 'Print queue' }).Status = 'Warning'
    ($previous.Results | Where-Object { $_.Check -eq 'Disk (C:)' }).Status = 'Warning'

    # An invented measurement for the Live monitor page, matching the sample report.
    $loads = 64, 12, 38, 7, 91, 22, 15, 4, 47, 9, 28, 3, 55, 18, 6, 11
    $index = 0
    $snapshot = [PSCustomObject]@{
        TakenAt         = [datetime]'2026-09-30 09:15:20'
        Cpu             = [PSCustomObject]@{
            Percent          = 27
            FrequencyMHz     = 3100
            BaseFrequencyMHz = 2400
            Processors       = @($loads | ForEach-Object { [PSCustomObject]@{ Name = 'CPU {0}' -f $index; Percent = $_; FrequencyMHz = 3100; Parked = $false }; $index++ })
        }
        System          = [PSCustomObject]@{ Processes = 214; Threads = 3187; Handles = 96412; UptimeSeconds = 1053420 }
        Memory          = [PSCustomObject]@{
            TotalBytes = 15.8GB; UsedBytes = 14GB; AvailableBytes = 1.8GB; Percent = 88
            CommittedBytes = 17.2GB; CommitLimitBytes = 20.5GB
            CachedBytes = 1.6GB; PagedPoolBytes = 0.7GB; NonPagedPoolBytes = 0.4GB; PageFilePercent = 34
        }
        Gpu             = @([PSCustomObject]@{
                Name = 'Contoso Graphics 770'; Percent = 14
                Engines = @(
                    [PSCustomObject]@{ Name = '3D'; Percent = 14 }
                    [PSCustomObject]@{ Name = 'Copy'; Percent = 1 }
                    [PSCustomObject]@{ Name = 'Video decode'; Percent = 9 }
                    [PSCustomObject]@{ Name = 'Video encode'; Percent = 0 }
                )
                DedicatedUsedBytes = 0.6GB; DedicatedTotalBytes = 2GB; SharedUsedBytes = 0.9GB
            })
        GpuSensors      = @()
        Disks           = @(
            [PSCustomObject]@{ Name = 'Disk 0 (C:)'; Percent = 36; ReadBytesPerSecond = 18.4MB; WriteBytesPerSecond = 6.1MB; QueueLength = 1 }
            [PSCustomObject]@{ Name = 'Disk 1 (D:)'; Percent = 2; ReadBytesPerSecond = 0; WriteBytesPerSecond = 48KB; QueueLength = 0 }
        )
        Volumes         = @(
            [PSCustomObject]@{ Name = 'C:'; Label = 'Windows'; TotalBytes = 237.9GB; FreeBytes = 7.4GB; Percent = 97 }
            [PSCustomObject]@{ Name = 'D:'; Label = 'Data'; TotalBytes = 465.8GB; FreeBytes = 286.1GB; Percent = 39 }
        )
        DriveHealth     = [PSCustomObject]@{ State = 'RequiresAdmin'; Message = ''; Drives = @() }
        Network         = @([PSCustomObject]@{ Name = 'Contoso Wi-Fi 6 AX200 160MHz'; ReceivedBytesPerSecond = 1.55MB; SentBytesPerSecond = 96KB; LinkBitsPerSecond = 867000000 })
        Thermal         = @([PSCustomObject]@{ Name = 'TZ00'; TemperatureC = 58 })
        Battery         = [PSCustomObject]@{ Percent = 64; PluggedIn = $true; MinutesRemaining = $null }
        Processes       = @(
            [PSCustomObject]@{ Name = 'msedge'; Percent = 11; MemoryBytes = 4.9GB }
            [PSCustomObject]@{ Name = 'Teams'; Percent = 7; MemoryBytes = 2.1GB }
            [PSCustomObject]@{ Name = 'EXCEL'; Percent = 4; MemoryBytes = 1.6GB }
            [PSCustomObject]@{ Name = 'MsMpEng'; Percent = 2; MemoryBytes = 0.3GB }
            [PSCustomObject]@{ Name = 'OUTLOOK'; Percent = 1; MemoryBytes = 1.2GB }
        )
        MemoryProcesses = @(
            [PSCustomObject]@{ Name = 'msedge'; MemoryBytes = 4.9GB }
            [PSCustomObject]@{ Name = 'Teams'; MemoryBytes = 2.1GB }
            [PSCustomObject]@{ Name = 'EXCEL'; MemoryBytes = 1.6GB }
            [PSCustomObject]@{ Name = 'OUTLOOK'; MemoryBytes = 1.2GB }
            [PSCustomObject]@{ Name = 'Memory Compression'; MemoryBytes = 0.9GB }
        )
        IoProcesses     = @(
            [PSCustomObject]@{ Name = 'OneDrive'; IoBytesPerSecond = 17.2MB }
            [PSCustomObject]@{ Name = 'msedge'; IoBytesPerSecond = 1.4MB }
            [PSCustomObject]@{ Name = 'MsMpEng'; IoBytesPerSecond = 640KB }
            [PSCustomObject]@{ Name = 'Teams'; IoBytesPerSecond = 210KB }
            [PSCustomObject]@{ Name = 'System'; IoBytesPerSecond = 52KB }
        )
    }

    # Earlier measurements, so the graphs show a history instead of a single point.
    $history = @{
        Cpu         = 18, 22, 19, 25, 31, 44, 62, 71, 58, 49, 37, 33, 29, 35, 41, 38, 30, 26, 24, 28, 34, 39, 45, 36, 31
        Memory      = 81, 81, 82, 82, 82, 83, 84, 84, 85, 85, 86, 86, 86, 87, 87, 87, 87, 88, 88, 88, 88, 88, 88, 88, 88
        Gpu         = 6, 8, 7, 12, 18, 22, 25, 19, 15, 11, 9, 13, 21, 27, 24, 18, 12, 10, 14, 16, 19, 17, 13, 12, 15
        Disk        = 4, 6, 3, 12, 48, 71, 66, 52, 30, 14, 9, 7, 22, 41, 38, 27, 18, 11, 8, 15, 29, 44, 40, 33, 30
        NetworkDown = @(0.3MB, 0.4MB, 0.2MB, 1.1MB, 2.4MB, 3.9MB, 4.2MB, 3.1MB, 2.2MB, 1.4MB, 0.8MB, 0.6MB, 0.9MB, 1.7MB, 2.6MB, 2.1MB, 1.5MB, 1.2MB, 0.9MB, 1.1MB, 1.6MB, 2MB, 1.8MB, 1.6MB, 1.5MB)
        NetworkUp   = @(40KB, 60KB, 50KB, 90KB, 150KB, 420KB, 610KB, 380KB, 200KB, 120KB, 90KB, 70KB, 80KB, 110KB, 160KB, 140KB, 100KB, 90KB, 80KB, 85KB, 95KB, 120KB, 110KB, 100KB, 98KB)
    }

    $collapsed = [System.Windows.Visibility]::Collapsed
    $visible = [System.Windows.Visibility]::Visible

    # Light theme, English
    $gui = & $newWindow 'Light'
    try {
        $controls = $gui.Controls

        # The Overview page: verdict, score, changes and the problems with their fixes.
        Show-WindowReport -Gui $gui -Report $report -Previous $previous
        & $savePicture $gui.Window $Pictures.Window

        # One category, reached through a notice: an automatic check has found that the
        # memory is fuller than before, and a click on the notice has led to the result.
        $newProblem = @(Compare-PCHealthReport -Reference $previous -Difference $report | Where-Object { $_.Check -eq 'Memory usage' })
        [void](Add-WindowNotice -Gui $gui -Change $newProblem)
        # The notice says when the problem was found; a fixed time keeps the picture the same.
        foreach ($notice in $gui.Notices.Values) {
            $notice.FoundAt = [datetime]'2026-09-30 09:14:52'
        }
        Show-WindowNotice -Gui $gui
        [void](Show-WindowResult -Gui $gui -Category 'Hardware' -Check 'Memory usage')
        & $savePicture $gui.Window $Pictures.Category

        # A search over all results
        $controls.SearchBox.Text = 'update'
        Show-WindowPage -Gui $gui -Name 'Hardware'
        & $savePicture $gui.Window $Pictures.Search
        $controls.SearchBox.Text = ''
        Show-WindowNotice -Gui $gui -Clear

        # The Live monitor page. Opening it through Show-WindowPage would start measuring
        # this computer, so the page is switched by hand and filled with the invented data.
        $controls.CategoryList.SelectedIndex = 1
        $gui.Page = 'Live monitor'
        $controls.PageTitle.Text = 'Live monitor'
        foreach ($name in 'OverviewPanel', 'ResultScroll', 'EmptyText', 'FilterPanel', 'SettingsPanel') {
            $controls[$name].Visibility = $collapsed
        }
        $controls.MonitorPanel.Visibility = $visible
        foreach ($name in $history.Keys) {
            # Played backwards and then forwards, the values fill most of the graph.
            $values = @($history[$name])
            [array]::Reverse($values)
            @($values) + @($history[$name]) | ForEach-Object { $gui.MonitorHistory[$name].Add($_) }
        }
        # The first call lays the page out; the second one draws the graphs at their real size.
        Show-WindowMonitor -Gui $gui -Snapshot $snapshot
        $gui.Window.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        foreach ($name in $gui.MonitorHistory.Keys) {
            $gui.MonitorHistory[$name].RemoveAt($gui.MonitorHistory[$name].Count - 1)
        }
        Show-WindowMonitor -Gui $gui -Snapshot $snapshot
        # The memory is above its limit, so its tile has a red dot and a triangle; the
        # triangle is "clicked" to show the advice.
        Switch-WindowAdvice -Gui $gui -Name 'Memory'
        & $savePicture $gui.Window $Pictures.Monitor

        # The lower end of the page: network, sensors and programs.
        $controls.MonitorPanel.ScrollToEnd()
        & $savePicture $gui.Window $Pictures.MonitorDetails

        # What takes up the space of drive C:, with an invented measurement that matches
        # the "Largest folders" of the sample report.
        $entry = { param($Name, $Bytes, $Complete = $true) [PSCustomObject]@{ Name = $Name; Bytes = $Bytes; Complete = $Complete } }
        $gui.DiskUsage['C:'] = @{
            Expanded = $true
            State    = 'Done'
            Error    = ''
            Worker   = $null
            Handle   = $null
            Detail   = [PSCustomObject]@{
                Drive        = 'C:'
                Programs     = @(
                    & $entry 'Contoso Office 16.0' 4.6GB
                    & $entry 'Contoso Design Suite 12.4' 3.8GB
                    & $entry 'Teams 25.1' 1.9GB
                    & $entry 'Web Browser 128.0' 1.1GB
                    & $entry 'Development Tools 17.9' 980MB $false
                    & $entry 'PDF Tools 2.0' 640MB
                    & $entry 'Video Player 3.0' 310MB
                    & $entry 'Web Meeting Client 6.2' 280MB
                    & $entry 'Cloud Backup 4.2' 240MB
                    & $entry 'Contoso VPN 5.1' 150MB
                )
                ProgramCount = 46
                ProgramBytes = 15.3GB
                UnknownCount = 7
                Folders      = @(
                    & $entry 'Users\m.horvat\AppData' 71.2GB $false
                    & $entry 'Windows' 28.4GB $false
                    & $entry 'Program Files' 19.6GB
                    & $entry 'Users\m.horvat\Downloads' 11.2GB
                    & $entry 'Users\m.horvat\Videos' 9.7GB
                    & $entry 'hiberfil.sys' 6.3GB
                    & $entry 'ProgramData' 5.1GB
                    & $entry 'pagefile.sys' 4.7GB
                )
                IsElevated   = $false
                MeasuredAt   = [datetime]'2026-09-30 09:15:00'
            }
        }
        Show-WindowVolume -Gui $gui
        $gui.Window.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $controls.MonitorVolumes.BringIntoView()
        & $savePicture $gui.Window $Pictures.MonitorDisks

        # The detail page of the processor, as a click on its tile opens it. What the
        # background would read about the processor is invented here, so nothing of
        # this computer gets into the picture.
        $line = { param($Name, $Text) [PSCustomObject]@{ Name = $Name; Text = $Text } }
        $part = { param($Title, $Rows, [switch]$Raw, [switch]$KeepNames) [PSCustomObject]@{ Title = $Title; Raw = [bool]$Raw; KeepNames = [bool]$KeepNames; Rows = @($Rows) } }
        $gui.ComponentDetail['Cpu'] = @{
            State      = 'Done'
            Error      = ''
            Worker     = $null
            Handle     = $null
            FinishedAt = Get-Date
            Detail     = [PSCustomObject]@{
                Name     = 'Cpu'
                ReadAt   = [datetime]'2026-09-30 09:15:21'
                Sections = @(
                    & $part 'Processor' @(
                        & $line 'Name' 'Contoso Core 8 2.40GHz'
                        & $line 'Maker' 'Contoso'
                        & $line 'Description' 'x64 Family 6 Model 10 Stepping 2'
                        & $line 'Architecture' 'x64 (64 bit)'
                        & $line 'Socket' 'U3E1'
                        & $line 'Cores' '8'
                        & $line 'Cores in use' '8'
                        & $line 'Logical processors' '16'
                        & $line 'Base speed' '2400 MHz'
                        & $line 'Speed of the bus' '100 MHz'
                        & $line 'L2 cache' '4 MB'
                        & $line 'L3 cache' '16 MB'
                        & $line 'Virtualization turned on in the firmware' 'Yes'
                        & $line 'Extensions for virtual machines' 'Yes'
                        & $line 'Second level address translation' 'Yes'
                        & $line 'Address width' '64 bit'
                        & $line 'Data width' '64 bit'
                        & $line 'Processor ID' 'BFEBFBFF000A0652'
                        & $line 'Status' 'OK'
                    )
                    & $part 'Cache' -KeepNames @(
                        & $line 'L1 Cache' '640 KB'
                        & $line 'L2 Cache' '4 MB'
                        & $line 'L3 Cache' '16 MB'
                    )
                    & $part 'Activity right now' @(
                        & $line 'Time spent in programs' '21 %'
                        & $line 'Time spent in Windows itself' '6 %'
                        & $line 'Time spent on signals from hardware' '0 %'
                        & $line 'Time spent on postponed work of drivers' '0 %'
                        & $line 'Idle' '73 %'
                        & $line 'Signals from hardware per second' '5139'
                        & $line 'Switches between programs per second' '7197'
                        & $line 'Requests to Windows per second' '37102'
                        & $line 'Threads waiting for a free processor' '0'
                    )
                    & $part 'Computer' @(
                        & $line 'Processor sockets in use' '1'
                        & $line 'Logical processors in total' '16'
                        & $line 'Runs under a hypervisor' 'No'
                        & $line 'Power plan' 'Balanced'
                    )
                    & $part 'Win32_Processor' -Raw @(
                        & $line 'AddressWidth' '64'
                        & $line 'Architecture' '9'
                        & $line 'Caption' 'x64 Family 6 Model 10 Stepping 2'
                        & $line 'CurrentClockSpeed' '2400'
                        & $line 'DataWidth' '64'
                        & $line 'L2CacheSize' '4096'
                        & $line 'L3CacheSize' '16384'
                        & $line 'MaxClockSpeed' '2400'
                        & $line 'NumberOfCores' '8'
                        & $line 'NumberOfLogicalProcessors' '16'
                    )
                )
            }
        }
        Open-WindowComponent -Gui $gui -Name 'Cpu'
        # Once more after the layout, so the large graph is drawn at its real size.
        $gui.Window.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        Show-WindowComponent -Gui $gui
        & $savePicture $gui.Window $Pictures.Component
    }
    finally {
        $gui.Window.Close()
    }

    # Dark theme, Croatian
    try {
        $script:Language = 'hr'
        $script:Translations = $null
        $gui = & $newWindow 'Dark'
        try {
            Show-WindowReport -Gui $gui -Report $report -Previous $previous
            & $savePicture $gui.Window $Pictures.Dark
        }
        finally {
            $gui.Window.Close()
        }
    }
    finally {
        $script:Language = 'en'
        $script:Translations = $null
    }
} $sampleJson $pictures

foreach ($name in 'Window', 'Category', 'Monitor', 'MonitorDisks', 'Component', 'MonitorDetails', 'Dark') {
    Write-Output $pictures[$name]
}

# --- Animation ---------------------------------------------------------------------
# An animated GIF of the pictures above. Windows can write a GIF with several pictures,
# but not the two things that make it an animation: how long each picture is shown and
# that it starts over at the end. Both are added to the file afterwards.

$frames = $pictures.Window, $pictures.Category, $pictures.Search, $pictures.Monitor, $pictures.Component, $pictures.MonitorDisks, $pictures.MonitorDetails, $pictures.Dark
$encoder = New-Object -TypeName System.Windows.Media.Imaging.GifBitmapEncoder
foreach ($frame in $frames) {
    $bitmap = New-Object -TypeName System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = New-Object -TypeName System.Uri -ArgumentList $frame
    $bitmap.EndInit()
    # Three quarters of the size keep the file small and the text readable.
    $scaled = New-Object -TypeName System.Windows.Media.Imaging.TransformedBitmap -ArgumentList $bitmap, (New-Object -TypeName System.Windows.Media.ScaleTransform -ArgumentList 0.75, 0.75)
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($scaled))
}
$memory = New-Object -TypeName System.IO.MemoryStream
$encoder.Save($memory)
$source = $memory.ToArray()
$memory.Dispose()

$output = New-Object -TypeName System.IO.MemoryStream
$position = 0

# Reads a chain of data blocks: each starts with its length; a length of 0 ends the chain.
function Copy-GifBlock {
    param([byte[]]$Bytes, [ref]$Position, [System.IO.Stream]$Target)

    while ($true) {
        $length = $Bytes[$Position.Value]
        if ($Target) {
            $Target.Write($Bytes, $Position.Value, $length + 1)
        }
        $Position.Value += $length + 1
        if ($length -eq 0) {
            break
        }
    }
}

# Header (6 bytes) and screen description (7 bytes), then the global color table, if any
$headerLength = 13
if ($source[10] -band 0x80) {
    $headerLength += 3 * [math]::Pow(2, ($source[10] -band 0x07) + 1)
}
$output.Write($source, 0, $headerLength)
$position = $headerLength

# "Play again and again": the application extension that every browser understands
[byte[]]$loop = 0x21, 0xFF, 0x0B, 0x4E, 0x45, 0x54, 0x53, 0x43, 0x41, 0x50, 0x45, 0x32, 0x2E, 0x30, 0x03, 0x01, 0x00, 0x00, 0x00
$output.Write($loop, 0, $loop.Length)

# Every picture gets a control block of its own that says how long it is shown,
# in hundredths of a second.
$delay = 280
[byte[]]$control = 0x21, 0xF9, 0x04, 0x00, ($delay -band 0xFF), ($delay -shr 8), 0x00, 0x00

while ($position -lt $source.Length) {
    switch ($source[$position]) {
        0x21 {
            # An extension written by Windows: skipped, its place is taken by the blocks above.
            $position += 2
            Copy-GifBlock -Bytes $source -Position ([ref]$position) -Target $null
        }
        0x2C {
            $output.Write($control, 0, $control.Length)

            # Picture description (10 bytes), its own color table, if any, then the picture data
            $descriptorLength = 10
            if ($source[$position + 9] -band 0x80) {
                $descriptorLength += 3 * [math]::Pow(2, ($source[$position + 9] -band 0x07) + 1)
            }
            # One more byte: the code size the data starts with
            $output.Write($source, $position, $descriptorLength + 1)
            $position += $descriptorLength + 1
            Copy-GifBlock -Bytes $source -Position ([ref]$position) -Target $output
        }
        default {
            # The end mark, or something unknown: stop here.
            $position = $source.Length
        }
    }
}
$output.WriteByte(0x3B)

$animation = Join-Path -Path $outputFolder -ChildPath 'demo.gif'
[System.IO.File]::WriteAllBytes($animation, $output.ToArray())
$output.Dispose()
Remove-Item -LiteralPath $pictures.Search -Force
Write-Output $animation
