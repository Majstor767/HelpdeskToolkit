function Get-ProcessCache {
    <#
    .SYNOPSIS
        Returns a value that was remembered earlier in this process, when it is young enough.
    .DESCRIPTION
        Some measurements take seconds and change slowly, for example the sizes of the
        folders of a full drive. The window repeats the health check every few minutes;
        measuring those again each time would keep the drive and the processor busy
        for nothing.

        The values are kept in the memory of the process (as data of the application
        domain), not in the module: every check runs in a runspace of its own with a
        fresh copy of the module, and all of them have to see the same values. Nothing
        is written to disk, and the values are gone when the application is closed.

        Returns a table with At (when it was remembered) and Value, or nothing when
        there is no value under the key or when it is older than -MaxAgeMinutes.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [double]$MaxAgeMinutes
    )

    $entry = [System.AppDomain]::CurrentDomain.GetData("HelpdeskToolkit:$Key")
    if ($entry -and ((Get-Date) - $entry.At).TotalMinutes -le $MaxAgeMinutes) {
        $entry
    }
}
