function Get-CheckDescription {
    <#
    .SYNOPSIS
        Returns the short explanation of a check from Config\Descriptions.psd1.
    .DESCRIPTION
        The file is read once and cached. The key is looked up as given first; when
        that fails, the part before the first colon or parenthesis is tried, so
        "Disk (C:)" and "Disk (D:)" share the text stored under "Disk". An unknown key
        returns an empty string, so a missing description never breaks a check.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if (-not $script:Descriptions) {
        $path = Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Descriptions.psd1'
        $script:Descriptions = Import-PowerShellDataFile -Path $path
    }

    if ($script:Descriptions.ContainsKey($Key)) {
        return $script:Descriptions[$Key]
    }

    $baseKey = $Key -replace '\s*[:(].*$', ''
    if ($script:Descriptions.ContainsKey($baseKey)) {
        return $script:Descriptions[$baseKey]
    }

    ''
}
