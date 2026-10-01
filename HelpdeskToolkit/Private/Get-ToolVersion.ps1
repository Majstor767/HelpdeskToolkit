function Get-ToolVersion {
    <#
    .SYNOPSIS
        Returns the version of HelpdeskToolkit, as written into every report.
    .DESCRIPTION
        Normally the version comes from the module manifest. When the checks run on
        another computer (see Get-RemoteHealthReport), the functions are sent there
        without the manifest; the version is then handed over in $script:ToolVersion.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($script:ToolVersion) {
        return [string]$script:ToolVersion
    }

    $ExecutionContext.SessionState.Module.Version.ToString()
}
