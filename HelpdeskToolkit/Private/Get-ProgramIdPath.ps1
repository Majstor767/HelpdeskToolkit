function Get-ProgramIdPath {
    <#
    .SYNOPSIS
        Returns the program file behind a ProgId, the name under which a program registered itself in Windows.
    .DESCRIPTION
        A ProgId such as "ChromeHTML" leads to the command line Windows runs to open
        something with that program. The path of the program is taken from it.

        A program registers itself for one user or for everybody. Both places are
        looked at one after the other, the one of the user first. The combined view
        Windows offers is not used: it leaves the part of the user out for a program
        that runs with administrator rights.

        Returns the path as it is written there, whether the file exists or not, or
        an empty text when the ProgId is not registered.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ProgId
    )

    if (-not $ProgId) {
        return ''
    }

    foreach ($root in 'HKCU:\Software\Classes', 'HKLM:\Software\Classes') {
        try {
            $key = Get-Item -LiteralPath ('{0}\{1}\shell\open\command' -f $root, $ProgId) -ErrorAction Stop
            $command = [string]$key.GetValue('')
        }
        catch {
            continue
        }

        # The command line is either "C:\path\browser.exe" arguments or C:\path\browser.exe arguments.
        $path = if ($command -match '^\s*"([^"]+)"') { $Matches[1] } else { ($command.Trim() -split '\s+')[0] }
        if ($path) {
            return [Environment]::ExpandEnvironmentVariables($path)
        }
    }
    ''
}
