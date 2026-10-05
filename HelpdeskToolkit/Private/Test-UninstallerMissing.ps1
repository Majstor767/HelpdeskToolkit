function Test-UninstallerMissing {
    <#
    .SYNOPSIS
        Tells whether an installed program is only an entry in the list: the file that removes it is gone.
    .DESCRIPTION
        A program whose folder was deleted by hand stays in the list of installed
        programs, because the list is kept in the registry. "Uninstall" then fails,
        since the uninstaller was in the deleted folder.

        $true is returned only where that can be said for sure:

        - The entry names its uninstaller with a full path on a local drive
          ("C:\..."). A bare name is found by Windows itself, and a network path may
          just not be reachable right now.
        - The drive is there. A program on an external disk that is not connected is
          not a leftover.
        - The file does not exist.

        Programs installed by Windows Installer (MSI) are removed through their
        product code, not through a file of their own, so they are never reported.
        Apps from the Microsoft Store have no uninstall command at all.

        Only looks whether a file exists; nothing is changed or started.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # A program as returned by Get-InstalledProgram.
        [Parameter(Mandatory)]
        [AllowNull()]
        [PSCustomObject]$Program
    )

    if (-not $Program) {
        return $false
    }

    $code = if ($Program.PSObject.Properties['ProductCode']) { [string]$Program.ProductCode } else { '' }
    $text = if ($Program.PSObject.Properties['UninstallString']) { ([string]$Program.UninstallString).Trim() } else { '' }
    if ($code -or -not $text -or $text -match '^"?msiexec(\.exe)?"?\s') {
        return $false
    }

    $command = Split-UninstallString -Text $text
    if (-not $command -or $command.FilePath -notmatch '^[A-Za-z]:\\') {
        return $false
    }

    $drive = [System.IO.Path]::GetPathRoot($command.FilePath)
    if (-not (Test-Path -LiteralPath $drive)) {
        return $false
    }

    -not (Test-Path -LiteralPath $command.FilePath -PathType Leaf)
}
