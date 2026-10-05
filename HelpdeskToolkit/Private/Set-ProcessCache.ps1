function Set-ProcessCache {
    <#
    .SYNOPSIS
        Remembers a value with the time it was measured.
    .DESCRIPTION
        The counterpart of Get-ProcessCache, which explains what the cache is for and
        where it lives: in the memory of this process and, when the environment
        variable HELPDESKTOOLKIT_CACHE names a folder, also as a file in that folder,
        so the next check finds it although it runs in a new process.

        Only the memory and the own folder of the application change. A file that
        cannot be written is no error: the value is then measured again next time.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only keeps a value in the memory and in the own folder of the application; no system state is changed.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]$Value
    )

    $entry = @{ At = Get-Date; Value = $Value }
    [System.AppDomain]::CurrentDomain.SetData("HelpdeskToolkit:$Key", $entry)

    $path = Get-ProcessCachePath -Key $Key
    if ($path) {
        try {
            $folder = Split-Path -Path $path -Parent
            if (-not (Test-Path -LiteralPath $folder)) {
                [void](New-Item -Path $folder -ItemType Directory -Force)
            }
            $entry | Export-Clixml -LiteralPath $path -Depth 4 -Force
        }
        catch {
            Write-Verbose "The value '$Key' could not be remembered in a file: $($_.Exception.Message)"
        }
    }
}
