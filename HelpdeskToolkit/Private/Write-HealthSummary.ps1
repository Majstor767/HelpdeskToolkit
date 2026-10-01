function Write-HealthSummary {
    <#
    .SYNOPSIS
        Prints a short, colored summary of a health report to the console.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Colored, human-readable console output is the purpose of this function. Data is returned separately with -PassThru.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        [string[]]$ReportPath = @()
    )

    $colors = @{
        OK       = 'Green'
        Warning  = 'Yellow'
        Critical = 'Red'
        Info     = 'Cyan'
    }

    Write-Host ''
    Write-Host 'HelpdeskToolkit - PC Health Check' -ForegroundColor White
    Write-Host ('Computer: {0} | Date: {1} | Duration: {2} s' -f $Report.ComputerName, $Report.GeneratedAt, $Report.DurationSeconds) -ForegroundColor DarkGray

    $currentCategory = ''
    foreach ($result in $Report.Results) {
        if ($result.Category -ne $currentCategory) {
            $currentCategory = $result.Category
            Write-Host ''
            Write-Host $currentCategory -ForegroundColor White
        }

        $label = '[{0}]' -f $result.Status.ToUpper()
        Write-Host ('  {0,-10} ' -f $label) -ForegroundColor $colors[$result.Status] -NoNewline
        Write-Host ('{0}: {1}' -f $result.Check, $result.Value)

        if ($result.Recommendation) {
            Write-Host ('             -> {0}' -f $result.Recommendation) -ForegroundColor DarkGray
        }
    }

    Write-Host ''
    Write-Host 'Summary: ' -NoNewline
    $statuses = @('OK', 'Warning', 'Critical', 'Info')
    for ($i = 0; $i -lt $statuses.Count; $i++) {
        $status = $statuses[$i]
        Write-Host ('{0} {1}' -f $Report.Summary[$status], $status) -ForegroundColor $colors[$status] -NoNewline
        if ($i -lt $statuses.Count - 1) {
            Write-Host ', ' -NoNewline
        }
    }
    Write-Host ''

    if (-not $Report.IsElevated) {
        Write-Host 'Run without administrator rights: checks marked "Requires admin" were skipped.' -ForegroundColor DarkGray
    }

    foreach ($path in $ReportPath) {
        Write-Host ('Report saved: {0}' -f $path) -ForegroundColor DarkGray
    }
    Write-Host ''
}
