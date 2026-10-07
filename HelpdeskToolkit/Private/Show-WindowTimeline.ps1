function Show-WindowTimeline {
    <#
    .SYNOPSIS
        Fills the Timeline page of the window: what happened on the computer lately, one group per day.
    .DESCRIPTION
        The report carries the time line (see Get-ChangeTimeline) newest first. The
        page shows it grouped by day, each day with the number of problems and changes
        on it, so that a bad day stands out and the change before it is found quickly.

        Like the result cards, the rows only show text; this function prepares it:

        - Day:     "Today", "Yesterday", or the weekday and the date in the language of
                   the window
        - Summary: "2 problems, 5 changes"
        - Events:  one row each with Time, Level (decides the color of the dot), Kind,
                   Title and Times (how often it happened that day, when more than once).
                   A problem also carries Url, the web search for exactly that error
                   (see Get-TimelineHelpLink), and its title is shown as a link (Link)

        The filter of the page leaves only the problems or only the changes.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Leave the list where it is scrolled to. Used when an automatic check replaces the report.
        [switch]$KeepScroll
    )

    $controls = $Gui.Controls
    $report = $Gui.Report
    $visible = [System.Windows.Visibility]::Visible
    $collapsed = [System.Windows.Visibility]::Collapsed

    $entries = @()
    if ($report -and $report.PSObject.Properties['Timeline']) {
        $entries = @($report.Timeline | Where-Object { $_ })
    }

    $problemCount = @($entries | Where-Object { $_.Level -eq 'Problem' }).Count
    $controls.TimelineSummary.Text = (Get-LocalizedText '{0} problems and {1} changes on record') -f $problemCount, ($entries.Count - $problemCount)

    $filter = if ($controls.TimelineFilter.SelectedItem) { [string]$controls.TimelineFilter.SelectedItem.Tag } else { '' }
    if ($filter) {
        $entries = @($entries | Where-Object { $_.Level -eq $filter })
    }

    # "2 problems, 5 changes"; a part that is zero is left out.
    $count = {
        param($Events)
        $problems = @($Events | Where-Object { $_.Level -eq 'Problem' }).Count
        $changes = @($Events).Count - $problems
        $parts = @(
            if ($problems -eq 1) { Get-LocalizedText '1 problem' } elseif ($problems -gt 1) { (Get-LocalizedText '{0} problems') -f $problems }
            if ($changes -eq 1) { Get-LocalizedText '1 change' } elseif ($changes -gt 1) { (Get-LocalizedText '{0} changes') -f $changes }
        )
        $parts -join ', '
    }

    $culture = [cultureinfo]$(if ($script:Language -eq 'hr') { 'hr-HR' } else { 'en-US' })
    $today = (Get-Date).Date
    $times = [string][char]0xD7

    # The time of an entry is text: "2026-01-15 10:30". Its first ten characters are the day.
    $days = @(
        $entries | Group-Object -Property { ([string]$_.Time).Substring(0, [math]::Min(10, ([string]$_.Time).Length)) } |
            Sort-Object -Property Name -Descending | ForEach-Object {
                $date = [datetime]::MinValue
                $label = $_.Name
                if ([datetime]::TryParseExact($_.Name, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
                    $label = if ($date -eq $today) {
                        Get-LocalizedText 'Today'
                    }
                    elseif ($date -eq $today.AddDays(-1)) {
                        Get-LocalizedText 'Yesterday'
                    }
                    else {
                        $date.ToString('dddd, yyyy-MM-dd', $culture)
                    }
                }

                [PSCustomObject]@{
                    Day     = $label
                    Summary = & $count $_.Group
                    Events  = @(
                        $_.Group | Sort-Object -Property Time -Descending | ForEach-Object {
                            $time = [string]$_.Time
                            $url = Get-TimelineHelpLink -Entry $_
                            [PSCustomObject]@{
                                Time  = if ($time.Length -ge 16) { $time.Substring(11, 5) } else { '' }
                                Level = [string]$_.Level
                                Kind  = Get-LocalizedText ([string]$_.Kind)
                                # Names of programs and updates stay as they are; only
                                # the titles the tool wrote itself are translated.
                                Title = if ($_.Title -in 'Antivirus definitions', 'Microsoft Store apps') { Get-LocalizedText ([string]$_.Title) } else { [string]$_.Title }
                                Times = if ($_.Count -gt 1) { '{0} {1}' -f $times, $_.Count } else { '' }
                                # A problem is a link to a web search for exactly that error.
                                Url   = $url
                                Link  = if ($url) { 'Yes' } else { '' }
                            }
                        }
                    )
                }
            }
    )

    $offset = $controls.TimelineScroll.VerticalOffset
    $controls.TimelineItems.ItemsSource = $days
    if ($KeepScroll) {
        $controls.TimelineScroll.ScrollToVerticalOffset($offset)
    }
    else {
        $controls.TimelineScroll.ScrollToTop()
    }

    $controls.EmptyText.Text = if ($filter) { Get-LocalizedText 'Nothing of that kind is on record.' } else { Get-LocalizedText 'Windows has nothing on record for the last weeks.' }
    $controls.EmptyText.Visibility = if ($days.Count -eq 0) { $visible } else { $collapsed }
}
