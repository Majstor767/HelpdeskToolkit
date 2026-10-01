function Get-FileProductName {
    <#
    .SYNOPSIS
        Returns the product name stored in a program file, or the file name without it.
    .DESCRIPTION
        Programs carry their product name in the file properties ("Opera GX Internet
        Browser", "Microsoft Edge"). That is friendlier than the name of the executable.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $name = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductName
        if ($name) {
            return $name.Trim()
        }
    }
    catch {
        Write-Verbose "Could not read the product name of ${Path}: $($_.Exception.Message)"
    }

    [System.IO.Path]::GetFileNameWithoutExtension($Path)
}
