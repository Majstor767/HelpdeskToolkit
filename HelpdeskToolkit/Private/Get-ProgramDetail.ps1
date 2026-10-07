function Get-ProgramDetail {
    <#
    .SYNOPSIS
        Returns what Windows knows about a running program: where it is, who made it and since when it runs.
    .DESCRIPTION
        The Live monitor lists programs by name. This function looks up all processes
        of that name and returns the details as pairs of a label and a text, ready for
        display: number of processes, threads and memory in total, the time the first
        of them was started, and the path, product, maker and version of the program
        file.

        Windows does not tell a standard user the path and the start time of system
        processes and of programs of other users. Those values are then reported as
        "not available without administrator rights" instead of being left out.

        Returns nothing when no process of that name runs any more.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Name of the program as the Live monitor shows it, without ".exe".
        [Parameter(Mandatory)]
        [string]$Name
    )

    $processes = @(Get-Process -Name $Name -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    $unknown = Get-LocalizedText 'not available without administrator rights'
    $row = { param($Label, $Text) [PSCustomObject]@{ Name = Get-LocalizedText $Label; Text = [string]$Text } }

    # Reading these properties of a protected process throws; that is not an error here.
    $read = {
        param($Process, [string]$Property)
        try { $Process.$Property } catch { $null }
    }

    $paths = @($processes | ForEach-Object { & $read $_ 'Path' } | Where-Object { $_ } | Select-Object -Unique)
    $started = @($processes | ForEach-Object { & $read $_ 'StartTime' } | Where-Object { $_ } | Sort-Object) | Select-Object -First 1
    $threads = ($processes | ForEach-Object { @($_.Threads).Count } | Measure-Object -Sum).Sum
    $memory = ($processes | Measure-Object -Property WorkingSet64 -Sum).Sum

    & $row 'Processes' $processes.Count
    & $row 'Threads' $threads
    & $row 'Memory in use' (Format-Gigabyte -Bytes $memory)
    & $row 'Running since' $(if ($started) { [string]::Format([cultureinfo]::InvariantCulture, '{0:yyyy-MM-dd HH:mm:ss}', @($started)) } else { $unknown })
    & $row 'Program file' $(if ($paths.Count -gt 0) { $paths -join "`n" } else { $unknown })

    if ($paths.Count -gt 0) {
        try {
            $version = (Get-Item -LiteralPath $paths[0] -ErrorAction Stop).VersionInfo
            if ($version.ProductName) { & $row 'Product' $version.ProductName }
            if ($version.CompanyName) { & $row 'Maker' $version.CompanyName }
            if ($version.ProductVersion) { & $row 'Version' $version.ProductVersion }
        }
        catch {
            Write-Verbose "No file details for $($paths[0]): $($_.Exception.Message)"
        }
    }
}
