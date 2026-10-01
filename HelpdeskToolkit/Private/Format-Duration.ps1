function Format-Duration {
    <#
    .SYNOPSIS
        Formats a number of seconds as a short duration, for example "3 d 4 h" or "2 h 10 min".
    .DESCRIPTION
        Shows the two largest units that matter: days and hours, hours and minutes, or
        minutes alone. Used by the Live monitor for the time since Windows started and
        for the remaining battery time.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Seconds
    )

    $span = [timespan]::FromSeconds([math]::Max(0, $Seconds))

    if ($span.Days -gt 0) {
        return '{0} d {1} h' -f $span.Days, $span.Hours
    }
    if ($span.Hours -gt 0) {
        return '{0} h {1} min' -f $span.Hours, $span.Minutes
    }
    '{0} min' -f $span.Minutes
}
