function Get-HealthScore {
    <#
    .SYNOPSIS
        Condenses the result of a health check into one number from 0 to 100.
    .DESCRIPTION
        The score starts at 100. Every critical result and every warning takes points
        off (15 and 4 by default, see the Score section of Config\Thresholds.psd1);
        results with the status OK or Info do not change it. The score never drops
        below 0.

        The number is a rough guide for comparing two runs of the same computer, or
        several computers with each other. What needs to be done is in the list of
        problems, not in the score.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        # The count per status, as returned by Get-HealthSummary.
        [Parameter(Mandatory)]
        $Summary
    )

    $penalty = (Get-HealthThreshold).Score
    $score = 100 - [int]$Summary.Critical * $penalty.CriticalPenalty - [int]$Summary.Warning * $penalty.WarningPenalty

    [int][math]::Max(0, $score)
}
