function Get-InstalledProgram {
    <#
    .SYNOPSIS
        Returns the programs listed in "Installed apps", with version, install date, size and folder.
    .DESCRIPTION
        Installers register themselves under three Uninstall keys in the registry:
        64-bit programs, 32-bit programs and programs installed for the current user
        only. All three are readable without administrator rights.

        Win32_Product is deliberately not used: querying it makes Windows verify, and
        possibly repair, every installed MSI package, which is slow and changes the system.

        Entries without a name and entries marked as system components are skipped,
        like in the Windows list. The install date, the size (the estimate the
        installer wrote down) and the folder are optional in the registry, so they can
        be empty.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $entries = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue
    $seen = @{}

    foreach ($entry in $entries) {
        $names = $entry.PSObject.Properties.Name
        if ($names -notcontains 'DisplayName' -or -not $entry.DisplayName) {
            continue
        }
        if ($names -contains 'SystemComponent' -and $entry.SystemComponent -eq 1) {
            continue
        }

        $version = if ($names -contains 'DisplayVersion') { [string]$entry.DisplayVersion } else { '' }

        # The same program can be registered under more than one key.
        $key = '{0}|{1}' -f $entry.DisplayName, $version
        if ($seen.ContainsKey($key)) {
            continue
        }
        $seen[$key] = $true

        # InstallDate is stored as text in the form yyyyMMdd.
        $installed = $null
        if ($names -contains 'InstallDate' -and $entry.InstallDate -match '^\d{8}$') {
            try {
                $installed = [datetime]::ParseExact($entry.InstallDate, 'yyyyMMdd', [cultureinfo]::InvariantCulture)
            }
            catch {
                Write-Verbose "Unreadable install date for $($entry.DisplayName): $($entry.InstallDate)"
            }
        }

        # EstimatedSize is a number of kilobytes.
        $size = $null
        if ($names -contains 'EstimatedSize' -and $entry.EstimatedSize -gt 0) {
            $size = [long]$entry.EstimatedSize * 1KB
        }

        $location = ''
        if ($names -contains 'InstallLocation' -and $entry.InstallLocation) {
            $location = ([string]$entry.InstallLocation).Trim().Trim('"').TrimEnd('\')
        }

        [PSCustomObject]@{
            Name        = ([string]$entry.DisplayName).Trim()
            Version     = $version.Trim()
            InstallDate = $installed
            SizeBytes   = $size
            Location    = $location
        }
    }
}
