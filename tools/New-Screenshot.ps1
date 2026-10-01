<#
.SYNOPSIS
    Creates the screenshots used in the README files from the fictional sample report.
.DESCRIPTION
    Writes three pictures to the docs folder:

    - screenshot-report.png:  the top of docs\sample-report.html, rendered by Microsoft
      Edge in headless mode (Edge is part of Windows 10 and 11)
    - screenshot-window.png:  the application window showing the same sample data
    - screenshot-monitor.png: the Live monitor page of the window with an invented
      measurement

    All of them are generated from invented data (docs\sample-report.json and a
    measurement defined in this script), so the pictures never show a real computer
    and can be rebuilt after a layout change.
    Run tools\New-SampleReport.ps1 first when the report itself has changed.

    The window is drawn off-screen; nothing appears on the desktop.
.PARAMETER OutputPath
    Folder for the pictures. Defaults to the docs folder of the repository.
.EXAMPLE
    .\tools\New-Screenshot.ps1

    Rewrites docs\screenshot-report.png, docs\screenshot-window.png and docs\screenshot-monitor.png.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Build script that writes three generated pictures.')]
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

# The window functions are private, so the block runs inside the module scope.
& $module {
    param($Report, $WindowPath, $MonitorPath)

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
        TakenAt   = [datetime]'2026-09-30 09:15:20'
        Cpu       = [PSCustomObject]@{
            Percent      = 27
            FrequencyMHz = 3100
            Processors   = @($loads | ForEach-Object { [PSCustomObject]@{ Name = 'CPU {0}' -f $index; Percent = $_; FrequencyMHz = 3100 }; $index++ })
        }
        Memory    = [PSCustomObject]@{ TotalBytes = 15.8GB; UsedBytes = 14GB; Percent = 88; CommittedBytes = 17.2GB; CommitLimitBytes = 20.5GB }
        Gpu       = @([PSCustomObject]@{ Name = 'Contoso Graphics 770'; Percent = 14; DedicatedUsedBytes = 0.6GB; DedicatedTotalBytes = 2GB })
        Disks     = @(
            [PSCustomObject]@{ Name = 'Disk 0 (C:)'; Percent = 36; ReadBytesPerSecond = 18.4MB; WriteBytesPerSecond = 6.1MB }
            [PSCustomObject]@{ Name = 'Disk 1 (D:)'; Percent = 2; ReadBytesPerSecond = 0; WriteBytesPerSecond = 48KB }
        )
        Network   = @([PSCustomObject]@{ Name = 'Contoso Wi-Fi 6 AX200 160MHz'; ReceivedBytesPerSecond = 1.55MB; SentBytesPerSecond = 96KB })
        Processes = @(
            [PSCustomObject]@{ Name = 'msedge'; Percent = 11; MemoryBytes = 4.9GB }
            [PSCustomObject]@{ Name = 'Teams'; Percent = 7; MemoryBytes = 2.1GB }
            [PSCustomObject]@{ Name = 'EXCEL'; Percent = 4; MemoryBytes = 1.6GB }
            [PSCustomObject]@{ Name = 'MsMpEng'; Percent = 2; MemoryBytes = 0.3GB }
            [PSCustomObject]@{ Name = 'OUTLOOK'; Percent = 1; MemoryBytes = 1.2GB }
        )
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
        Show-WindowMonitor -Gui $gui -Snapshot $snapshot
        & $savePicture $window $MonitorPath
    }
    finally {
        Disable-WindowMonitor -Gui $gui -Stop
        $window.Close()
    }
} $report $windowPicture $monitorPicture

Write-Output $windowPicture
Write-Output $monitorPicture