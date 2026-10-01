function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Returns $true when the current PowerShell session is elevated.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object -TypeName System.Security.Principal.WindowsPrincipal -ArgumentList $identity
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}
