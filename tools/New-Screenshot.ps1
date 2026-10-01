<#
.SYNOPSIS
    Creates the screenshots used in the README files from the fictional sample report.
.DESCRIPTION
    Writes four pictures to the docs folder:

    - screenshot-report.png:  the top of docs\sample-report.html, rendered by Microsoft
      Edge in headless mode (Edge is part of Windows 10 and 11)
    - screenshot-window.png:  the application window showing the same sample data
    - screenshot-monitor.png: the Live monitor page of the window with an invented
      measurement
    - screenshot-monitor-details.png: the lower half of the same page

    All of them are generated from invented data (docs\sample-report.json and a
    measurement defined in this script), so the pictures never show a real computer
    and can be rebuilt after a layout change.
    Run tools\New-SampleReport.ps1 first when the report itself has changed.

    The window is drawn off-screen; nothing appears on the desktop.
.PARAMETER OutputPath
    Folder for the pictures. Defaults to the docs folder of the repository.
.EXAMPLE
    .\tools\New-Screenshot.ps1

    Rewrites the four docs\screenshot-*.png files.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Build script that writes four generated pictures.')]
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
    throw 'The window screenshot needs a single-threaded (STA) PowerShell session.'
}

$module = Import-Module -Name (Join-Path -Path $root -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1') -Force -PassThru
$report = Get-Content -LiteralPath $sampleJson -Raw | ConvertFrom-Json
$windowPicture = Join-Path -Path $outputFolder -ChildPath 'screenshot-window.png'
$monitorPicture = Join-Path -Path $outputFolder -ChildPath 'screenshot-monitor.png'
$monitorDetailPicture = Join-Path -Path $outputFolder -ChildPath 'screenshot-monitor-details.png'

# The window functions are private, so the block runs inside the module scope.
& $module {
    param($Report, $WindowPath, $MonitorPath, $MonitorDetailPath)

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
        Cpu    = 18, 22, 19, 25, 31, 44, 62, 71, 58, 49, 37, 33, 29, 35, 41, 38, 30, 26, 24, 28, 34, 39, 45, 36, 31
        Memory = 81, 81, 82, 82, 82, 83, 84, 84, 85, 85, 86, 86, 86, 87, 87, 87, 87, 88, 88, 88, 88, 88, 88, 88, 88
        Gpu    = 6, 8, 7, 12, 18, 22, 25, 19, 15, 11, 9, 13, 21, 27, 24, 18, 12, 10, 14, 16, 19, 17, 13, 12, 15
    }
    $gui = New-HealthCheckWindow
    $window = $gui.Window

    # Shown far outside the visible desktop: WPF only lays out a window that is shown.
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $window.Left = -10000
    $window.Top = 0
    $window.ShowInTaskbar = $false
    $window.ShowActivated = $false
    $window.Show()

    try {
        # The Overview page: the verdict, the counts and the problems with their fixes.
        Show-WindowReport -Gui $gui -Report $Report
        & $savePicture $window $WindowPath

        # The Live monitor page. Opening it through Show-WindowPage would start measuring
        # this computer, so the page is switched by hand and filled with the invented data.
        $controls = $gui.Controls
        $controls.CategoryList.SelectedIndex = 1
        $controls.PageTitle.Text = 'Live monitor'
        $controls.OverviewPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $controls.ResultScroll.Visibility = [System.Windows.Visibility]::Collapsed
        $controls.EmptyText.Visibility = [System.Windows.Visibility]::Collapsed
        $controls.MonitorPanel.Visibility = [System.Windows.Visibility]::Visible
        Disable-WindowMonitor -Gui $gui -Stop
        foreach ($name in $history.Keys) {
            $history[$name] | ForEach-Object { $gui.MonitorHistory[$name].Add($_) }
        }
        # The first call lays the page out; the second one draws the graphs at their real size.
        Show-WindowMonitor -Gui $gui -Snapshot $snapshot
        $window.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
        foreach ($name in $history.Keys) {
            $gui.MonitorHistory[$name].RemoveAt($gui.MonitorHistory[$name].Count - 1)
        }
        Show-WindowMonitor -Gui $gui -Snapshot $snapshot
        & $savePicture $window $MonitorPath

        # The lower half of the page: disks, network, sensors and programs.
        $controls.MonitorPanel.ScrollToEnd()
        & $savePicture $window $MonitorDetailPath
    }
    finally {
        Disable-WindowMonitor -Gui $gui -Stop
        $window.Close()
    }
} $report $windowPicture $monitorPicture $monitorDetailPicture

Write-Output $windowPicture
Write-Output $monitorPicture
Write-Output $monitorDetailPicture
