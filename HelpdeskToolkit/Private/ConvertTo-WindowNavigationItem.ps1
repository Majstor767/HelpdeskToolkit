function ConvertTo-WindowNavigationItem {
    <#
    .SYNOPSIS
        Builds one entry of the category list on the left side of the window.
    .DESCRIPTION
        An entry has a name, the worst status among its results (drawn as a colored dot)
        and the number of problems in it (drawn as a small badge; empty when there are
        none). Entries without results, such as "Live monitor", get the neutral status
        "None" unless another one is given.
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

    $statuses = @($Result | ForEach-Object { $_.Status })
    $worst = 'Critical', 'Warning', 'OK', 'Info' | Where-Object { $statuses -contains $_ } | Select-Object -First 1
    $problems = @($Result | Where-Object { $_.Status -in 'Critical', 'Warning' }).Count

    [PSCustomObject]@{
        Name  = $Name
        Worst = if ($worst) { $worst } else { $EmptyStatus }
        Badge = if ($problems -gt 0) { [string]$problems } else { '' }
    }
}
