function Disable-AppAutoStart {
    <#
    .SYNOPSIS
        Stops the application from starting with Windows.
    .DESCRIPTION
        Removes the shortcut that Enable-AppAutoStart put into the Startup folder of
        the current user. Returns $true when the shortcut is gone afterwards, also
        when there was none.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $path = Get-AutoStartPath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [System.IO.File]::Delete($path)
        }
        $true
    }
    catch {
        Write-Verbose "The shortcut for starting with Windows could not be removed: $($_.Exception.Message)"
        $false
    }
}
