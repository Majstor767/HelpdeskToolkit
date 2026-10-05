function Get-ProcessCachePath {
    <#
    .SYNOPSIS
        Returns the file in which a remembered value is kept between two processes.
    .DESCRIPTION
        Get-ProcessCache explains what is remembered and why. The folder comes from
        the environment variable HELPDESKTOOLKIT_CACHE, which the window sets for the
        process of a check. The name of the file is the key, with every character
        that is not a letter or a digit replaced ("LargestFolders:C:" becomes
        "LargestFolders_C_.xml").

        Returns nothing when the variable is not set: the values then only live in
        the memory of the process.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $folder = $env:HELPDESKTOOLKIT_CACHE
    if (-not $folder) {
        return
    }

    Join-Path -Path $folder -ChildPath ('{0}.xml' -f ($Key -replace '[^A-Za-z0-9]', '_'))
}
