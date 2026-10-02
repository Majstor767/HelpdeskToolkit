function Get-DiskUsageDetail {
    <#
    .SYNOPSIS
        Finds out what takes up the space of one drive: its largest programs and folders.
    .DESCRIPTION
        Used by the Live monitor when the line "What takes up the space" of a drive is
        opened. Puts together:

        - Programs:     the largest installed programs of the drive (see Get-ProgramDiskUsage)
        - ProgramCount, ProgramBytes: how many programs have a known size, and their sum
        - UnknownCount: programs whose size could not be found out
        - Folders:      the largest folders and files of the drive (see Get-LargestFolder)
        - IsElevated:   whether everything could be read; without administrator rights
                        the folders of other users and of Windows are only measured as
                        far as they can be read
        - MeasuredAt:   when the measurement ended

        Measuring can take up to half a minute, so the window runs it in the
        background. The time limits and the length of the two lists are in the
        Cleanup section of Config\Thresholds.psd1. Only sizes are read.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Drive letter with colon, for example "C:".
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]:$')]
        [string]$Drive
    )

    $limits = (Get-HealthThreshold).Cleanup

    $programs = @(Get-ProgramDiskUsage -Drive $Drive -BudgetMs $limits.ProgramSizeBudgetMs)
    $known = @($programs | Where-Object { $_.Bytes -gt 0 })
    $programBytes = if ($known.Count -gt 0) { [long]($known | Measure-Object -Property Bytes -Sum).Sum } else { [long]0 }

    $folders = @(
        Get-LargestFolder -Path ('{0}\' -f $Drive) -BudgetMs $limits.LargestFolderBudgetMs |
            Select-Object -First ([int]$limits.UsageFolderCount)
    )

    [PSCustomObject]@{
        Drive        = $Drive
        Programs     = @($known | Select-Object -First ([int]$limits.UsageProgramCount))
        ProgramCount = $known.Count
        ProgramBytes = $programBytes
        UnknownCount = $programs.Count - $known.Count
        Folders      = $folders
        IsElevated   = Test-IsAdministrator
        MeasuredAt   = Get-Date
    }
}
