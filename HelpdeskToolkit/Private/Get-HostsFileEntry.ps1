function Get-HostsFileEntry {
    <#
    .SYNOPSIS
        Returns the active entries of the hosts file.
    .DESCRIPTION
        The hosts file maps names to IP addresses and is consulted before DNS. Windows
        ships it with comments only. An entry in it overrides DNS for that name, which
        is a classic reason for "this one web site does not open on this computer".
        Empty lines and comment lines (starting with #) are not returned.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $path = Join-Path -Path $env:WINDIR -ChildPath 'System32\drivers\etc\hosts'
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    Get-Content -LiteralPath $path -ErrorAction Stop |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and $_ -notlike '#*' } |
        ForEach-Object { ($_ -replace '\s+', ' ') }
}
