function Show-WindowTrend {
    <#
    .SYNOPSIS
        Draws how the health score changed over the last checks, on the Overview page.
    .DESCRIPTION
        One number says how the computer is doing now; the line says where it is
        heading. The points are in $Gui.ScoreHistory (see Show-WindowReport): the
        scores of the reports the application kept, oldest first, and the score of
        the report on the screen. They are spread over the whole width, with 0 at the
        bottom edge and 100 at the top (ConvertTo-WindowGraph, as on the Live monitor).

        Next to the title stands what the line shows: how many checks, since when,
        and the first and the last score. With fewer than two points there is nothing
        to draw and the card stays hidden.

        Called again whenever the drawing area changes its size, because the points
        are calculated for the size the area has.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $controls = $Gui.Controls
    $points = @($Gui['ScoreHistory'] | Where-Object { $_ })

    if ($points.Count -lt 2) {
        $controls.TrendBorder.Visibility = [System.Windows.Visibility]::Collapsed
        return
    }

    # Before the page was laid out for the first time the area has no size yet.
    $canvas = $controls.TrendGraph
    $width = if ($canvas.ActualWidth -gt 0) { $canvas.ActualWidth } else { 600 }
    $height = if ($canvas.ActualHeight -gt 0) { $canvas.ActualHeight } else { 88 }

    $graph = ConvertTo-WindowGraph -Value ([double[]]@($points | ForEach-Object { $_.Score })) -Width $width -Height $height -Capacity $points.Count
    $controls.TrendLine.Points = $graph.Line
    $controls.TrendArea.Points = $graph.Area

    $controls.TrendText.Text = (Get-LocalizedText '{0} checks since {1}: from {2} to {3}') -f
        $points.Count, $points[0].Time.ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture), $points[0].Score, $points[-1].Score
    $controls.TrendCaption.Text = Get-LocalizedText 'oldest check on the left, newest on the right, 0 - 100'
    $controls.TrendBorder.Visibility = [System.Windows.Visibility]::Visible
}
