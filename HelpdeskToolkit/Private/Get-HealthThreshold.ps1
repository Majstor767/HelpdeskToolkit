function Get-HealthThreshold {
    <#
    .SYNOPSIS
        Returns the thresholds defined in Config\Thresholds.psd1.
    .DESCRIPTION
        The file is read once and cached for the lifetime of the module.
        Checks call this function instead of hard-coding limits, which also
        gives the tests a single place to mock.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not $script:Thresholds) {
        $path = Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Thresholds.psd1'
        $script:Thresholds = Import-PowerShellDataFile -LiteralPath $path
    }

    $script:Thresholds
}
