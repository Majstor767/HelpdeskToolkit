function Get-WindowImage {
    <#
    .SYNOPSIS
        Returns a picture of what the window shows right now.
    .DESCRIPTION
        The window draws itself into a bitmap, at the sharpness of the screen it is on
        (a display scaled to 150 % gives a picture with 1.5 times the pixels). Nothing
        is read from the screen: other windows that overlap this one, and whatever
        else is on the desktop, are not in the picture.

        Returns a bitmap (System.Windows.Media.Imaging.BitmapSource), or nothing while
        the window has no size yet.
    #>
    [CmdletBinding()]
    [OutputType([System.Windows.Media.Imaging.BitmapSource])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $window = $Gui.Window
    $root = $window.Content
    $width = [int][math]::Ceiling($root.ActualWidth)
    $height = [int][math]::Ceiling($root.ActualHeight)
    if ($width -le 0 -or $height -le 0) {
        return
    }

    # How many pixels of the screen one unit of the window is
    $scaleX = 1.0
    $scaleY = 1.0
    $source = [System.Windows.PresentationSource]::FromVisual($window)
    if ($source -and $source.CompositionTarget) {
        $scaleX = $source.CompositionTarget.TransformToDevice.M11
        $scaleY = $source.CompositionTarget.TransformToDevice.M22
    }

    # The background first: the content of the window is transparent where nothing is drawn.
    $visual = New-Object -TypeName System.Windows.Media.DrawingVisual
    $area = New-Object -TypeName System.Windows.Rect -ArgumentList 0, 0, $width, $height
    $context = $visual.RenderOpen()
    try {
        $context.DrawRectangle($window.Background, $null, $area)
        $context.DrawRectangle((New-Object -TypeName System.Windows.Media.VisualBrush -ArgumentList $root), $null, $area)
    }
    finally {
        $context.Close()
    }

    $bitmap = New-Object -TypeName System.Windows.Media.Imaging.RenderTargetBitmap -ArgumentList @(
        [int][math]::Ceiling($width * $scaleX), [int][math]::Ceiling($height * $scaleY),
        (96 * $scaleX), (96 * $scaleY), [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $bitmap.Freeze()
    $bitmap
}
