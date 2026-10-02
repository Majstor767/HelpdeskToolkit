function Get-HealthScoreBreakdown {
    <#
    .SYNOPSIS
        Tells where the points of the health score went: how many each category cost.
    .DESCRIPTION
        A score alone says little: 72 can be one serious problem or a handful of small
        ones. This function splits the points that were taken off (see Get-HealthScore)
        by category, so the score can be read: "Security -19, Software -8".

        Returns one object per category that lost points, the most expensive first,
        with Category, Critical, Warning and Points. The points of all categories can
        add up to more than 100; the score itself never drops below 0.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # The results of a report.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Result
    )

    $penalty = (Get-HealthThreshold).Score

    $categories = @($Result | ForEach-Object { $_.Category } | Select-Object -Unique)
    $lost = foreach ($category in $categories) {
        $critical = @($Result | Where-Object { $_.Category -eq $category -and $_.Status -eq 'Critical' }).Count
        $warning = @($Result | Where-Object { $_.Category -eq $category -and $_.Status -eq 'Warning' }).Count
        $points = $critical * $penalty.CriticalPenalty + $warning * $penalty.WarningPenalty

        if ($points -gt 0) {
            [PSCustomObject]@{
                Category = [string]$category
                Critical = $critical
                Warning  = $warning
                Points   = [int]$points
            }
        }
    }

    # Sort-Object is stable, so categories with the same loss keep the order of the report.
    $lost | Sort-Object -Property Points -Descending
}
