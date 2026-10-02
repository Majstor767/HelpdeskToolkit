function Get-CapabilityUsage {
    <#
    .SYNOPSIS
        Returns which programs used the camera, the microphone or the location, and when.
    .DESCRIPTION
        Windows writes down for the signed-in user when a program last used one of
        these devices; the Settings app shows the same under Privacy & security. The
        list is in the registry of the user and needs no administrator rights:

        - one key per app from the Store, named after its package
        - below "NonPackaged" one key per ordinary program, named after its path with
          "#" in place of "\"

        Each key holds the start and the end of the last use as Windows file times. An
        end of 0 means that the program is using the device right now.

        Returns one object per program with Program, LastUsed and InUse. A program
        that was installed in several versions (the path contains the version number)
        is returned once, with its newest use.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('webcam', 'microphone', 'location')]
        [string]$Capability
    )

    $root = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\{0}' -f $Capability
    $keys = @(Get-ChildItem -Path $root -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'NonPackaged' })
    $keys += @(Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'NonPackaged') -ErrorAction SilentlyContinue)

    $newest = @{}
    foreach ($key in $keys) {
        $start = $key.GetValue('LastUsedTimeStart')
        if (-not $start) {
            continue
        }
        $stop = $key.GetValue('LastUsedTimeStop')

        $name = [string]$key.PSChildName
        if ($name.Contains('#')) {
            # "C:#Program Files#Contoso#meet.exe" -> "meet.exe"
            $name = $name.Substring($name.LastIndexOf('#') + 1)
        }
        else {
            # "Contoso.Meetings_8wekyb3d8bbwe" -> "Contoso.Meetings"
            $name = $name -replace '_[a-z0-9]{13}$', ''
        }

        $inUse = -not $stop
        $lastUsed = [datetime]::FromFileTime([long]$(if ($inUse) { $start } else { $stop }))

        if (-not $newest.ContainsKey($name) -or $inUse -or (-not $newest[$name].InUse -and $lastUsed -gt $newest[$name].LastUsed)) {
            $newest[$name] = [PSCustomObject]@{
                Program  = $name
                LastUsed = $lastUsed
                InUse    = $inUse
            }
        }
    }

    $newest.Values
}
