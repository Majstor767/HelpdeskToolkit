function ConvertTo-ListValue {
    <#
    .SYNOPSIS
        Turns a list of names into the value of a check: the first few names and "and N more".
    .DESCRIPTION
        Many checks report a list (programs, tasks, drivers). The value of a result
        should stay readable, so only the first names are written out; the others are
        returned separately and end up behind the "Show N more" section.

        Returns an object with Value and Details. With -Label the value starts with the
        number of items, for example "12 tasks: A, B, C and 9 more". The label is given
        in the singular and gets an "s" unless there is exactly one item.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Item,

        # What one item is called: "task", "driver".
        [string]$Label = '',

        # How many items are written into the value.
        [ValidateRange(1, 100)]
        [int]$Shown = 5
    )

    $items = @($Item | Where-Object { $_ })
    $remaining = @($items | Select-Object -Skip $Shown)

    $value = ($items | Select-Object -First $Shown) -join ', '
    if ($Label) {
        $plural = if ($items.Count -eq 1) { $Label } else { '{0}s' -f $Label }
        $value = if ($items.Count -gt 0) { '{0} {1}: {2}' -f $items.Count, $plural, $value } else { '0 {0}' -f $plural }
    }
    if ($remaining.Count -gt 0) {
        $value = '{0} and {1} more' -f $value, $remaining.Count
    }

    [PSCustomObject]@{
        Value   = $value
        Details = $remaining
    }
}
