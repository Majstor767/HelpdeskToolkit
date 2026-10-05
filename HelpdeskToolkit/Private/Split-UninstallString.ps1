function Split-UninstallString {
    <#
    .SYNOPSIS
        Splits the uninstall command of a program into its file and its arguments.
    .DESCRIPTION
        Every installer writes down how its program is removed: the "UninstallString"
        of its entry in the registry. It is a command line, written in one of two ways:

        - the file in quotes, followed by the arguments:  "C:\Program Files\App\unins000.exe" /SILENT
        - without quotes; the file then ends at the first ".exe":  C:\Program Files\App\uninstall.exe /S

        Names like %ProgramFiles% inside the file are replaced with their folders.
        Nothing is looked up on the disk and nothing is started.

        Returns a table with FilePath and Arguments, or nothing when the text is empty
        or cannot be read as a command line.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $line = $Text.Trim()
    if (-not $line) {
        return
    }

    if ($line -match '^"(?<file>[^"]+)"\s*(?<arguments>.*)$' -or $line -match '^(?<file>.+?\.exe)(\s+(?<arguments>.*))?$') {
        @{
            FilePath  = [Environment]::ExpandEnvironmentVariables($Matches['file'])
            Arguments = if ($Matches.ContainsKey('arguments')) { ([string]$Matches['arguments']).Trim() } else { '' }
        }
    }
}
