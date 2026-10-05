function Get-UninstallCommand {
    <#
    .SYNOPSIS
        Returns the program and the arguments that start the uninstaller of an installed program.
    .DESCRIPTION
        Every installer writes down how its program is removed: the "UninstallString"
        of its entry in the registry. It is what Windows runs when "Uninstall" is
        chosen under Installed apps. This function turns that text into a file and
        its arguments, so the window can start the same thing (see Open-WindowUninstall):

        - A program installed by Windows Installer (an MSI package) is removed with
          "msiexec.exe /x {product code}", also where the registry says "/I", which
          would open the dialog for changing the installation instead.
        - Otherwise the text is a command line: the file in quotes, or everything up
          to the first ".exe", and what follows as its arguments.

        Nothing is returned when there is no such text (apps from the Microsoft Store
        have none), when it cannot be read as a command line, or when it names a file
        that is no longer there. Nothing is started here.

        Returns a table with FilePath and Arguments.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # A program as returned by Get-InstalledProgram.
        [Parameter(Mandatory)]
        [AllowNull()]
        [PSCustomObject]$Program
    )

    if (-not $Program) {
        return
    }

    $installer = Join-Path -Path ([string]$env:WINDIR) -ChildPath 'System32\msiexec.exe'
    $code = if ($Program.PSObject.Properties['ProductCode']) { [string]$Program.ProductCode } else { '' }
    $text = if ($Program.PSObject.Properties['UninstallString']) { ([string]$Program.UninstallString).Trim() } else { '' }

    if (-not $code -and $text -match '^"?msiexec(\.exe)?"?\s+/[ix]\s*(?<code>\{[0-9a-f-]{36}\})') {
        $code = $Matches['code']
    }
    if ($code) {
        return @{ FilePath = $installer; Arguments = '/x {0}' -f $code }
    }

    if (-not $text) {
        return
    }

    if ($text -match '^"(?<file>[^"]+)"\s*(?<arguments>.*)$' -or $text -match '^(?<file>.+?\.exe)(\s+(?<arguments>.*))?$') {
        $file = [Environment]::ExpandEnvironmentVariables($Matches['file'])
        $arguments = if ($Matches.ContainsKey('arguments')) { ([string]$Matches['arguments']).Trim() } else { '' }

        # A file given with its folder has to be there; a bare name is found by Windows.
        if ($file -match '[\\/]' -and -not (Test-Path -LiteralPath $file -PathType Leaf)) {
            return
        }
        return @{ FilePath = $file; Arguments = $arguments }
    }
}
