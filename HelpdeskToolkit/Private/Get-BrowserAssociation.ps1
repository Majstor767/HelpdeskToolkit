function Get-BrowserAssociation {
    <#
    .SYNOPSIS
        Returns which program the user has chosen for web addresses, as Windows wrote it down.
    .DESCRIPTION
        Windows keeps the choice of the default browser per user, as a "ProgId" (the
        name under which a program registered itself). There are two places:

        - UserChoiceLatest: used by current versions of Windows 11. When it is there,
          it is the one that counts.
        - UserChoice: the older place, still read where the newer one is missing.

        The two can disagree: after a browser was removed, the newer one can still
        name it while the older one names the browser the user chose before or after.

        The choice for "https" is read, and the one for "http" where that is missing.
        Returns an object with Latest and Chosen (an empty text where nothing is set).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $read = {
        param([string]$Path)
        try {
            [string](Get-ItemProperty -Path $Path -ErrorAction Stop).ProgId
        }
        catch {
            ''
        }
    }

    $latest = ''
    $chosen = ''
    foreach ($scheme in 'https', 'http') {
        $base = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\{0}' -f $scheme
        if (-not $latest) {
            $latest = & $read (Join-Path -Path $base -ChildPath 'UserChoiceLatest\ProgId')
        }
        if (-not $chosen) {
            $chosen = & $read (Join-Path -Path $base -ChildPath 'UserChoice')
        }
    }

    [PSCustomObject]@{
        Latest = $latest
        Chosen = $chosen
    }
}
