function Get-ProcessCache {
    <#
    .SYNOPSIS
        Returns a value that was remembered earlier, when it is young enough.
    .DESCRIPTION
        Some measurements take seconds and change slowly, for example the sizes of the
        folders of a full drive. The window repeats the health check every few minutes;
        measuring those again each time would keep the drive and the processor busy
        for nothing.

        The values are kept in the memory of the process (as data of the application
        domain), not in the module: every check runs in a runspace of its own with a
        fresh copy of the module, and all of them have to see the same values.

        The window runs every check in a process of its own, which ends with the
        check, so what that process remembers would be lost. It names a folder in the
        environment variable HELPDESKTOOLKIT_CACHE (see Invoke-CheckWorker.ps1), and
        the values are then also kept as files in that folder, which is inside the
        folder of the application. Without the variable nothing is written to disk,
        and the values are gone when the process ends.

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

    if (-not $entry) {
        $path = Get-ProcessCachePath -Key $Key
        if ($path -and (Test-Path -LiteralPath $path)) {
            try {
                $stored = Import-Clixml -LiteralPath $path
                $entry = @{ At = [datetime]$stored.At; Value = $stored.Value }
            }
            catch {
                # A file that cannot be read is the same as no file: the value is measured.
                Write-Verbose "The remembered value '$Key' could not be read: $($_.Exception.Message)"
                $entry = $null
            }
        }
    }

    if ($entry -and ((Get-Date) - $entry.At).TotalMinutes -le $MaxAgeMinutes) {
        $entry
    }
}
