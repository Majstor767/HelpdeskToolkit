function ConvertTo-WindowItem {
    <#
    .SYNOPSIS
        Turns a check result into the object that a result card of the window displays.
    .DESCRIPTION
        The card template in MainWindow.xaml only shows text and hides a line when its
        text is empty. This function prepares exactly those texts, so the XAML needs no
        logic of its own:

        - Reference: the allowed range and the typical value on one line
        - More / MoreHeader: the remaining items of a long list and the caption of the
          section that opens them
        - RecommendationLabel: "Recommended fix" for a problem, "Advice" otherwise
        - Category: only filled in on the Overview page, where cards of several
          categories are mixed
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Result,

        [switch]$ShowCategory
    )

    process {
        $reference = @()
        if ($Result.Allowed) {
            $reference += 'Allowed: {0}' -f $Result.Allowed
        }
        if ($Result.Typical) {
            $reference += 'Typical: {0}' -f $Result.Typical
        }

        $details = @($Result.Details | Where-Object { $_ })
        $label = if ($Result.Status -in 'Warning', 'Critical') { 'RECOMMENDED FIX' } else { 'ADVICE' }

        [PSCustomObject]@{
            Status              = $Result.Status
            Category            = if ($ShowCategory) { $Result.Category } else { '' }
            Check               = $Result.Check
            Value               = $Result.Value
            Description         = [string]$Result.Description
            Reference           = $reference -join '   |   '
            More                = $details -join "`n"
            MoreHeader          = if ($details.Count -gt 0) { 'Show {0} more' -f $details.Count } else { '' }
            Recommendation      = [string]$Result.Recommendation
            RecommendationLabel = $label
        }
    }
}
