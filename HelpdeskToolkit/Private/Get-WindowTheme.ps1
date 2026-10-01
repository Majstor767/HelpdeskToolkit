function Get-WindowTheme {
    <#
    .SYNOPSIS
        Decides whether the window is shown in the light or in the dark theme.
    .DESCRIPTION
        "Light" and "Dark" are taken as they are. "System" follows Windows: Settings >
        Personalization > Colors stores the choice for applications in the registry of
        the user, in AppsUseLightTheme (0 = dark). Without that value, as on older
        Windows versions, the light theme is used.

        Returns "Light" or "Dark".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # The setting chosen by the user.
        [ValidateSet('System', 'Light', 'Dark')]
        [string]$Setting = 'System'
    )

    if ($Setting -ne 'System') {
        return $Setting
    }

    $light = Get-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme'
    if ($null -ne $light -and [int]$light -eq 0) {
        return 'Dark'
    }
    'Light'
}
