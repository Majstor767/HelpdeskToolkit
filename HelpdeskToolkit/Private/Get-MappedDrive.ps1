function Get-MappedDrive {
    <#
    .SYNOPSIS
        Returns the network drives the user has mapped permanently, as "Z: -> \\server\share".
    .DESCRIPTION
        A drive mapped with "Reconnect at sign-in" is stored under HKCU:\Network, one
        key per drive letter. Reading the registry does not touch the network, so the
        check stays fast even when a server is unreachable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-Path -Path 'HKCU:\Network')) {
        return
    }

    foreach ($key in Get-ChildItem -Path 'HKCU:\Network' -ErrorAction SilentlyContinue) {
        $target = $key.GetValue('RemotePath')
        if ($target) {
            '{0}: -> {1}' -f $key.PSChildName.ToUpperInvariant(), $target
        }
    }
}
