function Get-DefaultBrowserPath {
    <#
    .SYNOPSIS
        Returns the path of the default web browser; nothing when it cannot be found.
    .DESCRIPTION
        Windows stores the handler the user chose for http links as a ProgId. The
        ProgId points to the command line of the browser, from which the path of the
        executable is taken.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $choice = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' -ErrorAction Stop
        $commandKey = 'Registry::HKEY_CLASSES_ROOT\{0}\shell\open\command' -f $choice.ProgId
        $command = [string](Get-Item -Path $commandKey -ErrorAction Stop).GetValue('')

        # The command line is either "C:\path\browser.exe" arguments or C:\path\browser.exe arguments.
        $path = if ($command -match '^\s*"([^"]+)"') { $Matches[1] } else { ($command.Trim() -split '\s+')[0] }

        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }
    catch {
        Write-Verbose "Could not determine the default browser: $($_.Exception.Message)"
    }
}
