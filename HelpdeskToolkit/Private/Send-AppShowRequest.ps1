function Send-AppShowRequest {
    <#
    .SYNOPSIS
        Asks the copy of the application that is already running to show its window.
    .DESCRIPTION
        Used by a second copy that found the first one (see Lock-AppInstance), for
        example after a click on the shortcut while the application sits next to the
        clock. It leaves an empty file "show.request" in the application folder; the
        running copy looks for that file once a second, removes it and opens its
        window (Receive-AppShowRequest).

        Returns $true when the request was left.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $folder = Get-AppDataPath
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }
        [System.IO.File]::WriteAllText((Get-AppDataPath -ChildPath 'show.request'), '')
        $true
    }
    catch {
        Write-Verbose "The running copy could not be asked to show its window: $($_.Exception.Message)"
        $false
    }
}
