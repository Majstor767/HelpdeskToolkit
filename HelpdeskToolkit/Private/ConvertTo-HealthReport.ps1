function ConvertTo-HealthReport {
    <#
    .SYNOPSIS
        Turns a report that was read from JSON back into a report object.
    .DESCRIPTION
        A report that was saved as JSON, or that came from another computer, is plain
        data after reading: the count per status is no longer a table, a list with one
        entry has become a single value, and properties that older versions did not
        write are missing. This function restores the shape the rest of the module
        expects, so a loaded report can be displayed, exported and compared like a
        fresh one.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.HealthReport')]
    param(
        # The object returned by ConvertFrom-Json.
        [Parameter(Mandatory)]
        [PSCustomObject]$InputObject
    )

    # A property that may be missing in a report of an older version
    $read = {
        param($Object, [string]$Name, $Default)
        $property = $Object.PSObject.Properties[$Name]
        if ($property -and $null -ne $property.Value) { $property.Value } else { $Default }
    }

    $results = @(
        foreach ($item in @(& $read $InputObject 'Results' @())) {
            [PSCustomObject]@{
                PSTypeName     = 'HelpdeskToolkit.CheckResult'
                Category       = [string](& $read $item 'Category' '')
                Check          = [string](& $read $item 'Check' '')
                Description    = [string](& $read $item 'Description' '')
                Status         = [string](& $read $item 'Status' 'Info')
                Value          = [string](& $read $item 'Value' '')
                Details        = @(& $read $item 'Details' @() | Where-Object { $_ } | ForEach-Object { [string]$_ })
                Allowed        = [string](& $read $item 'Allowed' '')
                Typical        = [string](& $read $item 'Typical' '')
                Recommendation = [string](& $read $item 'Recommendation' '')
            }
        }
    )

    # Counted again from the results, so the numbers always match them.
    $summary = Get-HealthSummary -Result $results

    [PSCustomObject]@{
        PSTypeName      = 'HelpdeskToolkit.HealthReport'
        ToolVersion     = [string](& $read $InputObject 'ToolVersion' '')
        ComputerName    = [string](& $read $InputObject 'ComputerName' '')
        GeneratedAt     = [string](& $read $InputObject 'GeneratedAt' '')
        DurationSeconds = [double](& $read $InputObject 'DurationSeconds' 0)
        IsElevated      = [bool](& $read $InputObject 'IsElevated' $false)
        EventLogDays    = [int](& $read $InputObject 'EventLogDays' 7)
        Score           = Get-HealthScore -Summary $summary
        Summary         = $summary
        Results         = $results
    }
}
