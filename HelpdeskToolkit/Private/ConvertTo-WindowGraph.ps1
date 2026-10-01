function ConvertTo-WindowGraph {
    <#
    .SYNOPSIS
        Turns a series of percentages into the points of a history graph.
    .DESCRIPTION
        The Live monitor draws the last measurements of a value as a line with a filled
        area below it. This function calculates the corner points of both shapes for a
        drawing area of the given size:

        - the newest value sits at the right edge, older ones to the left of it, one
          step apart; the graph has room for -Capacity values
        - 0 % is the bottom edge and 100 % the top edge (screen coordinates count
          downwards, so the height is subtracted)

        Returns an object with Line and Area. Area holds the same points as Line plus
        the two corners on the bottom edge that close the shape.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # The measured values in percent, oldest first.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [double[]]$Value,

        [Parameter(Mandatory)]
        [double]$Width,

        [Parameter(Mandatory)]
        [double]$Height,

        # How many values fit into the graph.
        [ValidateRange(2, 1000)]
        [int]$Capacity = 60
    )

    $line = New-Object -TypeName System.Windows.Media.PointCollection
    $area = New-Object -TypeName System.Windows.Media.PointCollection

    # Only the newest values that still fit are drawn.
    $values = @($Value | Select-Object -Last $Capacity)
    if ($values.Count -eq 0) {
        return [PSCustomObject]@{ Line = $line; Area = $area }
    }

    $step = $Width / ($Capacity - 1)
    $firstX = $Width - ($values.Count - 1) * $step

    for ($i = 0; $i -lt $values.Count; $i++) {
        $percent = [math]::Max(0, [math]::Min(100, $values[$i]))
        $point = New-Object -TypeName System.Windows.Point -ArgumentList ($firstX + $i * $step), ($Height - $percent / 100 * $Height)
        $line.Add($point)
        $area.Add($point)
    }

    $area.Add((New-Object -TypeName System.Windows.Point -ArgumentList $Width, $Height))
    $area.Add((New-Object -TypeName System.Windows.Point -ArgumentList $firstX, $Height))

    [PSCustomObject]@{ Line = $line; Area = $area }
}
