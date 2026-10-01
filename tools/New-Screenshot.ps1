<#
.SYNOPSIS
    Creates the screenshots used in the README files from the fictional sample report.
.DESCRIPTION
    Writes two pictures to the docs folder:

    - screenshot-report.png: the top of docs\sample-report.html, rendered by Microsoft
      Edge in headless mode (Edge is part of Windows 10 and 11)
    - screenshot-window.png: the application window showing the same sample data

    Both are generated from docs\sample-report.json, which contains invented data, so
    the pictures never show a real computer and can be rebuilt after a layout change.
    Run tools\New-SampleReport.ps1 first when the report itself has changed.

    The window is drawn off-screen; nothing appears on the desktop.
.PARAMETER OutputPath
    Folder for the pictures. Defaults to the docs folder of the repository.
.EXAMPLE
    .\tools\New-Screenshot.ps1

    Rewrites docs\screenshot-report.png and docs\screenshot-window.png.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Build script that writes two generated pictures.')]
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

# The window functions are private, so the block runs inside the module scope.
& $module {
    param($Report, $Path)

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
        Show-WindowReport -Gui $gui -Report $Report

        # Select a result with a recommendation, so the detail panel is filled in.
        $selected = $Report.Results | Where-Object { $_.Check -eq 'Uptime' } | Select-Object -First 1
        $gui.Controls.ResultsGrid.SelectedItem = $selected
        Show-WindowResultDetail -Gui $gui -Result $selected

        # Let WPF finish layout and drawing before the picture is taken.
        $window.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)

        $content = $window.Content
        $width = [int]$content.ActualWidth
        $height = [int]$content.ActualHeight
        $area = New-Object -TypeName System.Windows.Rect -ArgumentList 0, 0, $width, $height

        $visual = New-Object -TypeName System.Windows.Media.DrawingVisual
        $context = $visual.RenderOpen()
        $context.DrawRectangle($window.Background, $null, $area)
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
    finally {
        $window.Close()
    }
} $report $windowPicture

Write-Output $windowPicture
