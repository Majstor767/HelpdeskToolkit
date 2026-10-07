function Get-StartupProgram {
    <#
    .SYNOPSIS
        Returns the programs that are set to start when the user signs in, and whether each one is switched on.
    .DESCRIPTION
        Reads the places Windows itself reads (see Get-StartupSource): the "Run" keys
        of the user and of the computer, the one for 32-bit programs, and the two
        Startup folders. For every entry the switch under "StartupApproved" is looked
        up, the one Task Manager turns: an entry without a switch is on, and the
        first byte of a switch is even for "on" and odd for "off".

        This is what "Startup apps" of Task Manager lists, without the apps from the
        Microsoft Store, which Windows starts in another way.

        Returns objects with
        - Name:     the name to show; a generated suffix ("Name_0123ABCD...") and the
                    extension of a shortcut are left out
        - Entry:    the name of the value or of the file, which is also the name of
                    the switch
        - Scope:    "User" or "Machine"
        - Source:   "Run", "Run32" or "StartupFolder"
        - Command:  what is started
        - Enabled:  whether the entry is switched on
        - Approved: the registry key that holds its switch

        Only reads. A place that cannot be read is left out.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    foreach ($source in Get-StartupSource) {
        # The switches of this place, by the name of the entry
        $switches = @{}
        try {
            if (Test-Path -LiteralPath $source.Approved) {
                $key = Get-Item -LiteralPath $source.Approved -ErrorAction Stop
                foreach ($name in $key.GetValueNames()) {
                    $switches[$name] = $key.GetValue($name)
                }
            }
        }
        catch {
            Write-Verbose "The switches under $($source.Approved) could not be read: $($_.Exception.Message)"
        }

        $entries = @()
        try {
            if ($source.Path) {
                if (Test-Path -LiteralPath $source.Path) {
                    $key = Get-Item -LiteralPath $source.Path -ErrorAction Stop
                    $entries = @(
                        foreach ($name in $key.GetValueNames()) {
                            # The unnamed value of a key is no program.
                            if ($name) {
                                [PSCustomObject]@{ Entry = $name; Name = $name -replace '_[0-9A-Fa-f]{16,}$', ''; Command = [string]$key.GetValue($name) }
                            }
                        }
                    )
                }
            }
            elseif ($source.Folder -and (Test-Path -LiteralPath $source.Folder)) {
                $entries = @(
                    Get-ChildItem -LiteralPath $source.Folder -File -ErrorAction Stop |
                        Where-Object { $_.Name -ne 'desktop.ini' } |
                        ForEach-Object { [PSCustomObject]@{ Entry = $_.Name; Name = $_.BaseName; Command = $_.FullName } }
                )
            }
        }
        catch {
            Write-Verbose "The startup programs of $($source.Scope) $($source.Source) could not be read: $($_.Exception.Message)"
        }

        foreach ($entry in $entries) {
            # Without a switch the entry is on (2).
            $first = 2
            if ($switches.ContainsKey($entry.Entry)) {
                $bytes = @($switches[$entry.Entry])
                if ($bytes.Count -gt 0 -and $bytes[0] -is [byte]) {
                    $first = [int]$bytes[0]
                }
            }
            [PSCustomObject]@{
                Name     = $entry.Name
                Entry    = $entry.Entry
                Scope    = $source.Scope
                Source   = $source.Source
                Command  = $entry.Command
                Enabled  = ($first % 2) -eq 0
                Approved = $source.Approved
            }
        }
    }
}
