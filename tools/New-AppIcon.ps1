<#
.SYNOPSIS
    Draws the application icon and saves it as HelpdeskToolkit\Assets\HelpdeskToolkit.ico.
.DESCRIPTION
    The icon is generated from code instead of being drawn in an image editor, so it
    can be changed and rebuilt by anyone: a dark blue rounded square with a green
    check mark, in the colors of the report.

    An .ico file is a small header followed by one image per size. Windows picks the
    size it needs (16 px in a title bar, 256 px in a large-icons view), so the icon is
    drawn separately for every size rather than scaled down from one picture.
.PARAMETER Path
    Where to save the icon. Defaults to the Assets folder of the module.
.EXAMPLE
    .\tools\New-AppIcon.ps1

    Rewrites HelpdeskToolkit\Assets\HelpdeskToolkit.ico.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
    Justification = 'Build script that writes a single generated file.')]
[CmdletBinding()]
param(
    [string]$Path
)

# The default is set here and not in the param block: Windows PowerShell 5.1 does not
# know $PSScriptRoot yet while it evaluates parameter defaults of a script run with -File.
if (-not $Path) {
    $Path = Join-Path -Path $PSScriptRoot -ChildPath '..\HelpdeskToolkit\Assets\HelpdeskToolkit.ico'
}

Add-Type -AssemblyName System.Drawing

$sizes = 16, 24, 32, 48, 64, 256
$background = [System.Drawing.Color]::FromArgb(0x14, 0x23, 0x3A)
$accent = [System.Drawing.Color]::FromArgb(0x4A, 0xD9, 0x8A)

# Draw one PNG per size.
$images = foreach ($size in $sizes) {
    $bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    # Rounded square
    $radius = [single]($size * 0.22)
    $diameter = $radius * 2
    $edge = [single]($size - 1)
    $shape = New-Object -TypeName System.Drawing.Drawing2D.GraphicsPath
    $shape.AddArc(0, 0, $diameter, $diameter, 180, 90)
    $shape.AddArc($edge - $diameter, 0, $diameter, $diameter, 270, 90)
    $shape.AddArc($edge - $diameter, $edge - $diameter, $diameter, $diameter, 0, 90)
    $shape.AddArc(0, $edge - $diameter, $diameter, $diameter, 90, 90)
    $shape.CloseFigure()
    $brush = New-Object -TypeName System.Drawing.SolidBrush -ArgumentList $background
    $graphics.FillPath($brush, $shape)

    # Check mark
    $pen = New-Object -TypeName System.Drawing.Pen -ArgumentList $accent, ([single]($size * 0.13))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $points = @(
        New-Object -TypeName System.Drawing.PointF -ArgumentList ([single]($size * 0.26)), ([single]($size * 0.53))
        New-Object -TypeName System.Drawing.PointF -ArgumentList ([single]($size * 0.43)), ([single]($size * 0.70))
        New-Object -TypeName System.Drawing.PointF -ArgumentList ([single]($size * 0.75)), ([single]($size * 0.32))
    )
    $graphics.DrawLines($pen, [System.Drawing.PointF[]]$points)

    $stream = New-Object -TypeName System.IO.MemoryStream
    if ($size -ge 256) {
        # The largest image is stored as PNG, which keeps the file small.
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    else {
        # Smaller images are stored as uncompressed bitmaps, the classic icon format
        # that every Windows component and tool understands.
        $area = New-Object -TypeName System.Drawing.Rectangle -ArgumentList 0, 0, $size, $size
        $data = $bitmap.LockBits($area, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $pixels = New-Object -TypeName byte[] -ArgumentList ($size * $size * 4)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $pixels, 0, $pixels.Length)
        $bitmap.UnlockBits($data)

        $maskRowBytes = [int]([math]::Ceiling($size / 32) * 4)
        $bmp = New-Object -TypeName System.IO.BinaryWriter -ArgumentList $stream
        $bmp.Write([uint32]40)              # size of this header
        $bmp.Write([int32]$size)            # width
        $bmp.Write([int32]($size * 2))      # height: color image plus transparency mask
        $bmp.Write([uint16]1)               # color planes
        $bmp.Write([uint16]32)              # bits per pixel
        $bmp.Write([uint32]0)               # no compression
        $bmp.Write([uint32]($pixels.Length + $maskRowBytes * $size))
        $bmp.Write([int32]0); $bmp.Write([int32]0); $bmp.Write([uint32]0); $bmp.Write([uint32]0)

        # Bitmap rows are stored bottom-up.
        for ($row = $size - 1; $row -ge 0; $row--) {
            $bmp.Write($pixels, $row * $size * 4, $size * 4)
        }
        # The mask is all zeros: transparency comes from the alpha channel above.
        $bmp.Write((New-Object -TypeName byte[] -ArgumentList ($maskRowBytes * $size)))
        $bmp.Flush()
    }

    $pen.Dispose(); $brush.Dispose(); $shape.Dispose(); $graphics.Dispose(); $bitmap.Dispose()

    [PSCustomObject]@{ Size = $size; Bytes = $stream.ToArray() }
    $stream.Dispose()
}

# Write the .ico container: a 6-byte header, one 16-byte directory entry per image,
# then the images themselves.
$output = New-Object -TypeName System.IO.MemoryStream
$writer = New-Object -TypeName System.IO.BinaryWriter -ArgumentList $output

$writer.Write([uint16]0)                # reserved
$writer.Write([uint16]1)                # type 1 = icon
$writer.Write([uint16]$images.Count)

$offset = 6 + 16 * $images.Count
foreach ($image in $images) {
    # A size of 256 is stored as 0, because the field is a single byte.
    $writer.Write([byte]($image.Size % 256))    # width
    $writer.Write([byte]($image.Size % 256))    # height
    $writer.Write([byte]0)                      # palette colors (none)
    $writer.Write([byte]0)                      # reserved
    $writer.Write([uint16]1)                    # color planes
    $writer.Write([uint16]32)                   # bits per pixel
    $writer.Write([uint32]$image.Bytes.Length)
    $writer.Write([uint32]$offset)
    $offset += $image.Bytes.Length
}
foreach ($image in $images) {
    $writer.Write($image.Bytes)
}
$writer.Flush()

$target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
[System.IO.File]::WriteAllBytes($target, $output.ToArray())
$writer.Dispose()

Write-Output $target
