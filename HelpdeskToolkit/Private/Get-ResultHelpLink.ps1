function Get-ResultHelpLink {
    <#
    .SYNOPSIS
        Returns the links a result is shown with: where its problem and the errors it names are explained.
    .DESCRIPTION
        Decides which of the links of Get-CheckHelpLink a result gets, in one place
        for the window (ConvertTo-WindowItem) and the HTML report
        (ConvertTo-HealthReportHtml):

        - A problem (Warning or Critical) gets all of them: the page or the search
          for its name, and one for every update, error code and crashing program.
        - A check that could not be read ("Unavailable") is no finding. It gets a
          search for every error code its error names, and nothing else.
        - A result that is fine gets only the links that belong to a line of its
          details (an event, a program), so the line can be looked up.

        A link with a Line belongs to that line of the details; the others are shown
        below the recommended fix.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # A result as returned by the checks.
        [Parameter(Mandatory)]
        [PSCustomObject]$Result
    )

    $details = [string[]]@($Result.Details | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $problem = $Result.Status -in 'Warning', 'Critical'

    if ($problem -and [string]$Result.Value -eq 'Unavailable') {
        if ($Result.Recommendation) {
            Get-CheckHelpLink -Check $Result.Check -Category $Result.Category -ErrorText ([string]$Result.Recommendation)
        }
    }
    elseif ($problem) {
        Get-CheckHelpLink -Check $Result.Check -Category $Result.Category -Detail $details -Value ([string]$Result.Value)
    }
    elseif ($details.Count -gt 0) {
        Get-CheckHelpLink -Check $Result.Check -Category $Result.Category -Detail $details -Value ([string]$Result.Value) | Where-Object { $_.Line }
    }
}
