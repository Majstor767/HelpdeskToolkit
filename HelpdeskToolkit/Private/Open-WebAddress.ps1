function Open-WebAddress {
    <#
    .SYNOPSIS
        Opens a web address in the browser of the user, also when Windows itself cannot.
    .DESCRIPTION
        Handing an address to Windows ("open this") is how a program normally opens a
        page. Two things can go wrong with that, and both are handled here:

        - The default browser is gone. Windows still names a browser that was removed
          (see Get-DefaultBrowser) and answers "Application not found". The address
          is then given to a browser that exists, as an argument.
        - The window runs with administrator rights. The browser would be started
          with those rights too. The request is therefore handed to the desktop of
          the user, which opens it with ordinary rights (see Invoke-DesktopShell).

        The ways are tried one after the other until one works.

        Only addresses that begin with "https://" and contain no spaces or quotes are
        opened: the addresses come from the configuration files of the module, and
        anything else in their place is a mistake there, not something to hand to
        Windows.

        Returns $true when the address was handed over, $false for an address that is
        not opened, and throws the first error when no way worked.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url
    )

    if ($Url -notmatch '^https://[^\s"]+$') {
        return $false
    }

    $browser = Get-DefaultBrowser
    $elevated = Test-IsAdministrator
    $program = [string]$browser.Usable
    $quoted = '"{0}"' -f $Url

    $ways = @(
        # Windows knows a browser that exists: it opens the address itself.
        if ($browser.Exists -or -not $program) {
            if ($elevated) {
                { Invoke-DesktopShell -FilePath $Url }
            }
            { Start-Process -FilePath $Url -ErrorAction Stop }
        }
        # A browser that exists, with the address as its argument
        if ($program) {
            if ($elevated) {
                { Invoke-DesktopShell -FilePath $program -Arguments $quoted }
            }
            { Start-Process -FilePath $program -ArgumentList $quoted -ErrorAction Stop }
        }
    )

    $failure = $null
    foreach ($way in $ways) {
        try {
            & $way
            return $true
        }
        catch {
            Write-Verbose "The address could not be opened this way: $($_.Exception.Message)"
            if (-not $failure) {
                $failure = $_
            }
        }
    }
    throw $failure
}
