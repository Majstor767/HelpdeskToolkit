function ConvertTo-WindowItem {
    <#
    .SYNOPSIS
        Turns a check result into the object that a result card of the window displays.
    .DESCRIPTION
        The card template in MainWindow.xaml only shows text and hides a line when its
        text is empty. This function prepares exactly those texts, so the XAML needs no
        logic of its own:

        - Reference: the allowed range and the typical value on one line
        - More / MoreItems / MoreHeader: the remaining items of a long list (as one
          text, which the search looks through, and line by line, where a line that
          names an event carries the address that explains it) and the caption of the
          section that opens them
        - Links: where the problem is explained on the web, shown below the
          recommended fix of a Warning or Critical result
        - RecommendationLabel: "Recommended fix" for a problem, "Advice" otherwise
        - ActionLabel: the caption of the button that opens the place in Windows where
          the problem is fixed; empty when there is no recommendation or no such place
        - Category: only filled in where cards of several categories are mixed
        - StatusText: the status as shown on the badge

        All texts are shown in the language of the window (see Get-LocalizedText). The
        properties Status, SourceCheck, SourceValue and SourceCategory keep the
        original, English values: the colors of the card depend on Status, and the
        button looks its target up by the original names.
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
            $action = Get-CheckAction -Check $Result.Check -Category $Result.Category -Value ([string]$Result.Value)
            if ($action) {
                $actionLabel = Get-LocalizedText $action.Label
            }
        }

        # Why the problem matters; only for a result that is one. A check that could
        # not be read ("Unavailable") is no finding, so nothing is said about it.
        $risk = ''
        if ($Result.Status -in 'Warning', 'Critical' -and [string]$Result.Value -ne 'Unavailable') {
            $risk = Get-LocalizedText (Get-CheckRisk -Check $Result.Check -Category $Result.Category -Value ([string]$Result.Value))
        }

        # Where things are explained on the web (see Get-CheckHelpLink). A problem gets
        # a link below its recommended fix: the page of the maker, or a search for the
        # name of the check. A line of the details that names an event of the event log
        # becomes a link itself, whatever the status of the result.
        $isProblem = $Result.Status -in 'Warning', 'Critical' -and [string]$Result.Value -ne 'Unavailable'
        $help = @(
            if ($isProblem -or $details.Count -gt 0) {
                Get-CheckHelpLink -Check $Result.Check -Category $Result.Category -Detail $details
            }
        )
        $links = @(
            if ($isProblem) {
                foreach ($link in $help | Where-Object { $_.Kind -ne 'Event' }) {
                    $text = if ($link.Kind -eq 'Page') { 'What this means and how to fix it' } else { 'Search the web for this problem' }
                    [PSCustomObject]@{ Label = Get-LocalizedText $text; Url = $link.Url }
                }
            }
        )

        # The details, line by line. An event reads "Event 10016: DistributedCOM, 45
        # times" and opens the search for that event; any other line is plain text.
        $eventLinks = @{}
        foreach ($link in $help | Where-Object { $_.Kind -eq 'Event' }) {
            $eventLinks[$link.Line] = $link
        }
        $moreItems = @(
            foreach ($line in $details) {
                if ($eventLinks.ContainsKey($line)) {
                    $link = $eventLinks[$line]
                    [PSCustomObject]@{
                        Text = (Get-LocalizedText 'Event {0}: {1}, {2} times') -f $link.Id, $link.Source, $link.Count
                        Url  = $link.Url
                    }
                }
                else {
                    [PSCustomObject]@{ Text = [string]$line; Url = '' }
                }
            }
        )

        [PSCustomObject]@{
            Status              = $Result.Status
            StatusText          = Get-LocalizedText $Result.Status
            Category            = if ($ShowCategory) { Get-LocalizedText $Result.Category } else { '' }
            Check               = $check
            Value               = Get-LocalizedText ([string]$Result.Value)
            Description         = Get-LocalizedText ([string]$Result.Description)
            Reference           = $reference -join '   |   '
            More                = $details -join "`n"
            MoreItems           = $moreItems
            MoreHeader         = if ($details.Count -gt 0) { (Get-LocalizedText 'Show {0} more') -f $details.Count } else { '' }
            Risk                = $risk
            RiskLabel           = Get-LocalizedText 'WHY THIS IS A PROBLEM'
            Recommendation      = Get-LocalizedText ([string]$Result.Recommendation)
            RecommendationLabel = Get-LocalizedText $label
            ActionLabel         = $actionLabel
            Links               = $links
            SourceCheck         = $Result.Check
            SourceValue         = [string]$Result.Value
            # "Yes" frames the card; set for the result a notice has led to.
            Highlight           = ''
            # Whether the details of a compact card are open; set by Show-WindowPage.
            Expanded            = $false
            SourceCategory      = $Result.Category
        }
    }
}
