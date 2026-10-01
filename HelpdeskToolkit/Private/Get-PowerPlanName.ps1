function Get-PowerPlanName {
    <#
    .SYNOPSIS
        Returns the name of the active power plan, for example "Balanced".
    .DESCRIPTION
        The registry holds the identifier of the active plan and, for every plan, its
        name. The names of the plans that come with Windows are stored as a reference
        into a system file followed by the English name, such as
        "@%SystemRoot%\system32\powrprof.dll,-15,Balanced"; the part after the last
        comma is returned. A plan created by the user has a plain name.

        Returns nothing when the plan cannot be read.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $schemes = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
    $active = Get-RegistryValue -Path $schemes -Name 'ActivePowerScheme'
    if (-not $active) {
        return
    }

    $name = [string](Get-RegistryValue -Path (Join-Path -Path $schemes -ChildPath $active) -Name 'FriendlyName')
    if ($name -match '^@.*,([^,]+)$') {
        $name = $Matches[1]
    }

    # The plans of Windows, in case the name is missing
    if (-not $name) {
        $known = @{
            '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Balanced'
            '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = 'High performance'
            'a1841308-3541-4fab-bc81-f71556f20b4a' = 'Power saver'
            'e9a42b02-d5df-448d-aa00-03f14749eb61' = 'Ultimate performance'
        }
        $name = $known[$active.ToLowerInvariant()]
    }

    if ($name) {
        $name.Trim()
    }
}
