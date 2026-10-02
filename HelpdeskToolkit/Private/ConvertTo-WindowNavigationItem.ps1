function ConvertTo-WindowNavigationItem {
    <#
    .SYNOPSIS
        Builds one entry of the page list on the left side of the window.
    .DESCRIPTION
        An entry has a name, an icon, the worst status among its results and the number
        of problems in it (drawn as a small badge in the color of the worst one; empty
        when there are none). Entries without results, such as "Live monitor", get the
        neutral status "None" unless another one is given.

        Group puts the entry under a heading of the list: the pages of the application
        (Overview, Live monitor, Timeline) have none, the check categories come under
        "CHECKS".

        Name is what the code works with and stays English; Label is the same name in
        the language of the window and is what the list shows.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [AllowEmptyCollection()]
        [object[]]$Result = @(),

        # Status to show when there are no results.
        [string]$EmptyStatus = 'None'
    )

    # Characters of the "Segoe MDL2 Assets" font, which is part of Windows 10 and 11
    $icons = @{
        'Overview'       = 0xE80F  # house
        'Live monitor'   = 0xEC4A  # speedometer
        'Timeline'       = 0xE81C  # clock with an arrow
        'System'         = 0xE770  # laptop
        'Specifications' = 0xE9F9  # sheet with a chart
        'Hardware'       = 0xE950  # chip
        'Software'       = 0xECAA  # tiles of apps
        'Event Log'      = 0xE8FD  # list
        'Windows Update' = 0xE895  # two arrows in a circle
        'Security'       = 0xE83D  # shield
        'Network'        = 0xE968  # computer on a network
        'Printers'       = 0xE749  # printer
        'Services'       = 0xE9F5  # gears
    }
    $icon = if ($icons.ContainsKey($Name)) { $icons[$Name] } else { 0xE8FD }
    $pages = 'Overview', 'Live monitor', 'Timeline'

    $statuses = @($Result | ForEach-Object { $_.Status })
    $worst = 'Critical', 'Warning', 'OK', 'Info' | Where-Object { $statuses -contains $_ } | Select-Object -First 1
    $problems = @($Result | Where-Object { $_.Status -in 'Critical', 'Warning' }).Count

    [PSCustomObject]@{
        Name  = $Name
        Label = Get-LocalizedText $Name
        Worst = if ($worst) { $worst } else { $EmptyStatus }
        Badge = if ($problems -gt 0) { [string]$problems } else { '' }
        Icon  = [string][char]$icon
        Group = if ($pages -contains $Name) { '' } else { Get-LocalizedText 'CHECKS' }
    }
}
