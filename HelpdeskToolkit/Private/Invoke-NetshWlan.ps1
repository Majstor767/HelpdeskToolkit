function Invoke-NetshWlan {
    <#
    .SYNOPSIS
        Returns the output of "netsh wlan show interfaces" as lines of text.
    .DESCRIPTION
        netsh.exe is started from the System32 folder by its full path. The command
        only displays the state of the Wi-Fi adapters. On a computer without Wi-Fi, or
        when the Wi-Fi service is not running, nothing is returned.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $path = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $lines = & $path wlan show interfaces 2>$null
    if ($LASTEXITCODE -eq 0) {
        $lines
    }
}
