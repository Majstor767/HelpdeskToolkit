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
          text, which the search looks through, and line by line) and the caption of
          the section that opens them. A line can be clicked (Link) when it names an
          event, which carries the address that explains it (Url), or a startup
          program, which a click switches off or on (Action, Target)
        - Links: where the problem, and every update and error code it names, is
          explained on the web, shown below the recommended fix of a Warning or
          Critical result
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

        # Where things are explained on the web (see Get-ResultHelpLink). A problem gets
        # links below its recommended fix: the page of the maker or a search for the
        # name of the check, and one for every update, error code and crashing program
        # it names. A line of the details that names an event of the event log or a
        # program that crashed becomes a link itself, whatever the status of the result.
        $help = @(Get-ResultHelpLink -Result $Result)
        $links = @(
            foreach ($link in $help | Where-Object { -not $_.Line }) {
                [PSCustomObject]@{ Label = Get-HelpLinkCaption -Link $link -Translate; Url = $link.Url }
            }
        )
        # The details, line by line. An event reads "Event 10016: DistributedCOM (45x)",
        # with how often it happened, and opens the search for that event; a program
        # that crashed opens the search for its crashes; any other line is plain text.
        $lineLinks = @{}
        foreach ($link in $help | Where-Object { $_.Line }) {
            $lineLinks[$link.Line] = $link
        }
        $moreItems = @(
            foreach ($line in $details) {
                if ($lineLinks.ContainsKey($line) -and $lineLinks[$line].Kind -eq 'Program') {
                    # A program that crashed: the line opens the search for its crashes.
                    [PSCustomObject]@{
                        Text   = [string]$line
                        Url    = $lineLinks[$line].Url
                        Action = ''
                        Target = ''
                        Tip    = Get-LocalizedText 'Search the web for the crashes of this program'
                        Link   = 'Yes'
                    }
                }
                elseif ($lineLinks.ContainsKey($line)) {
                    $link = $lineLinks[$line]
                    [PSCustomObject]@{
                        Text   = (Get-LocalizedText 'Event {0}: {1} ({2}x)') -f $link.Id, $link.Source, $link.Count
                        Url    = $link.Url
                        Action = ''
                        Target = ''
                        Tip    = Get-LocalizedText 'Look up what this event means and how it is fixed'
                        Link   = 'Yes'
                    }
                }
                elseif ($Result.Check -eq 'Startup programs') {
                    # A startup program: a click switches it off or on, after a question
                    # (see Switch-WindowStartupProgram).
                    $off = $line -match '^(?<name>.+) \(turned off\)$'
                    $name = if ($off) { $Matches['name'] } else { [string]$line }
                    [PSCustomObject]@{
                        Text   = if ($off) { '{0} ({1})' -f $name, (Get-LocalizedText 'turned off') } else { $name }
                        Url    = ''
                        Action = 'Startup'
                        Target = $name
                        Tip    = if ($off) { Get-LocalizedText 'Click to let this program start with Windows again' } else { Get-LocalizedText 'Click to stop this program from starting with Windows' }
                        Link   = 'Yes'
                    }
                }
                else {
                    [PSCustomObject]@{ Text = [string]$line; Url = ''; Action = ''; Target = ''; Tip = ''; Link = '' }
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
            MoreHeader         = if ($details.Count -eq 0) {
                ''
            }
            elseif ($Result.Check -eq 'Startup programs') {
                # The value names none of them: this is the whole list, and every line a switch.
                (Get-LocalizedText 'Show all {0}: click a program to switch it off or on') -f $details.Count
            }
            else {
                (Get-LocalizedText 'Show {0} more') -f $details.Count
            }
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
