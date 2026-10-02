function Get-OfficeInstallation {
    <#
    .SYNOPSIS
        Returns version, update channel and update setting of Microsoft Office (Click-to-Run); nothing when it is not installed.
    .DESCRIPTION
        Microsoft 365 Apps and the retail editions of Office 2016 and later are
        installed with "Click-to-Run" and keep their configuration under one registry
        key, readable without administrator rights:

        VersionToReport    the installed build, for example 16.0.17928.20156
        CDNBaseUrl         the address Office updates from; its last part is the
                           identifier of the update channel
        UpdatesEnabled     "False" when automatic updates were switched off in Office
        Platform           x64 or x86
        ProductReleaseIds  the installed products, for example O365ProPlusRetail

        A policy of the company can switch the updates off as well; it is looked at too.
        Office that was installed from an MSI package (volume licenses up to 2016) has
        no such key and is not returned.

        Returns an object with Version, Channel, UpdatesEnabled, Platform and Products.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $key = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $version = Get-RegistryValue -Path $key -Name 'VersionToReport'
    if (-not $version) {
        return
    }

    # Identifiers of the update channels, from the Office deployment documentation.
    $channels = @{
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' = 'Current Channel'
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' = 'Current Channel (Preview)'
        '5440fd1f-7ecb-4221-8110-145efaa6372f' = 'Beta Channel'
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' = 'Monthly Enterprise Channel'
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' = 'Semi-Annual Enterprise Channel'
        'b8f9b850-328d-4355-9145-c59439a0c4cf' = 'Semi-Annual Enterprise Channel (Preview)'
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' = 'Office 2019 (volume license)'
        '5030841d-c919-4594-8d2d-84ae4f96e58e' = 'Office LTSC 2021'
        '2e148de9-61c8-4051-b103-4af54baffbb4' = 'Office LTSC 2024'
    }
    $channel = 'Unknown channel'
    $address = [string](Get-RegistryValue -Path $key -Name 'CDNBaseUrl')
    $identifier = ($address -split '/')[-1].ToLowerInvariant()
    if ($channels.ContainsKey($identifier)) {
        $channel = $channels[$identifier]
    }

    $setting = Get-RegistryValue -Path $key -Name 'UpdatesEnabled'
    $policy = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\common\officeupdate' -Name 'EnableAutomaticUpdates'

    [PSCustomObject]@{
        Version        = [string]$version
        Channel        = $channel
        UpdatesEnabled = ([string]$setting -ne 'False') -and ($policy -ne 0)
        Platform       = [string](Get-RegistryValue -Path $key -Name 'Platform')
        Products       = @([string](Get-RegistryValue -Path $key -Name 'ProductReleaseIds') -split ',' | Where-Object { $_ })
    }
}
