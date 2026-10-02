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
        - ActionLabel: the caption of the button that opens the place in Windows where
          the problem is fixed; empty when there is no recommendation or no such place
        - Category: only filled in where cards of several categories are mixed
        - StatusText: the status as shown on the badge

        All texts are shown in the language of the window (see Get-LocalizedText). The
        properties Status, SourceCheck and SourceCategory keep the original, English
        values: the colors of the card depend on Status, and the button looks its
        target up by the original names.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSCustomObject]$Result,

        [switch]$ShowCategory
    )

    process {
        $check = Get-LocalizedCheckName $Result.Check

        $reference = @()
        if ($Result.Allowed) {
            $reference += (Get-LocalizedText 'Allowed: {0}') -f (Get-LocalizedText $Result.Allowed)
        }
        if ($Result.Typical) {
            $reference += (Get-LocalizedText 'Typical: {0}') -f (Get-LocalizedText $Result.Typical)
        }

        $details = @($Result.Details | Where-Object { $_ })
        $label = if ($Result.Status -in 'Warning', 'Critical') { 'RECOMMENDED FIX' } else { 'ADVICE' }

        $actionLabel = ''
        if ($Result.Recommendation) {
            $action = Get-CheckAction -Check $Result.Check -Category $Result.Category
            if ($action) {
                $actionLabel = Get-LocalizedText $action.Label
            }
        }

        [PSCustomObject]@{
            Status              = $Result.Status
            StatusText          = Get-LocalizedText $Result.Status
            Category            = if ($ShowCategory) { Get-LocalizedText $Result.Category } else { '' }
            Check               = $check
            Value               = Get-LocalizedText ([string]$Result.Value)
            Description         = Get-LocalizedText ([string]$Result.Description)
            Reference           = $reference -join '   |   '
            More                = $details -join "`n"
            MoreHeader          = if ($details.Count -gt 0) { (Get-LocalizedText 'Show {0} more') -f $details.Count } else { '' }
            Recommendation      = Get-LocalizedText ([string]$Result.Recommendation)
            RecommendationLabel = Get-LocalizedText $label
            ActionLabel         = $actionLabel
            SourceCheck         = $Result.Check
            # "Yes" frames the card; set for the result a notice has led to.
            Highlight           = ''
            # Whether the details of a compact card are open; set by Show-WindowPage.
            Expanded            = $false
            SourceCategory      = $Result.Category
        }
    }
}
