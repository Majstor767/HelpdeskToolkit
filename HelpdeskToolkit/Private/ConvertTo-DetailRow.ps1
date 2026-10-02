function ConvertTo-DetailRow {
    <#
    .SYNOPSIS
        Turns every property of an object into a line of a detail page.
    .DESCRIPTION
        The detail pages end with sections that show everything Windows reports about
        a component, useful or not: each property of the WMI object with its value,
        under the name Windows gives it, sorted by that name.

        Properties without a value are left out, as are the ones that describe the WMI
        object itself instead of the component. A list becomes one line with its
        entries separated by commas, a date is written as year-month-day, and a very
        long value is cut off.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject
    )

    begin {
        # What WMI adds to every object
        $technical = 'CimClass', 'CimInstanceProperties', 'CimSystemProperties', 'PSComputerName', 'PSShowComputerName'
        $longest = 400
    }

    process {
        if ($null -eq $InputObject) {
            return
        }

        foreach ($property in ($InputObject.PSObject.Properties | Sort-Object -Property Name)) {
            if ($property.Name -in $technical) {
                continue
            }

            $value = $property.Value
            if ($null -eq $value) {
                continue
            }

            $text = if ($value -is [datetime]) {
                '{0:yyyy-MM-dd HH:mm:ss}' -f $value
            }
            elseif ($value -is [array]) {
                ($value | ForEach-Object { [string]$_ }) -join ', '
            }
            else {
                [string]$value
            }

            $text = $text.Trim()
            if (-not $text) {
                continue
            }
            if ($text.Length -gt $longest) {
                $text = $text.Substring(0, $longest) + ' ...'
            }

            [PSCustomObject]@{ Name = $property.Name; Text = $text }
        }
    }
}
