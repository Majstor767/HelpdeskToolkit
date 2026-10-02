function Get-ProgramUpdate {
    <#
    .SYNOPSIS
        Returns the installed programs for which winget knows a newer version.
    .DESCRIPTION
        Asks winget for its list of available upgrades ("winget upgrade"). That
        command only compares the installed versions with the catalog on the internet;
        nothing is downloaded or installed.

        Only the community catalog ("winget") is asked. The Microsoft Store catalog
        would need an agreement to be accepted first, and Store apps update themselves.
        Programs whose installed version winget cannot read are left out, because
        nothing can be said about them.

        Returns an object with Updates (objects with Name, Id, Version and Available),
        or nothing when winget is not installed for this user. Throws when winget fails,
        for example without an internet connection.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 30
    )

    $result = Invoke-Winget -Arguments 'upgrade --source winget --disable-interactivity' -TimeoutSeconds $TimeoutSeconds
    if (-not $result) {
        return
    }

    $updates = @(ConvertFrom-WingetTable -Text $result.Output)
    if ($updates.Count -eq 0 -and $result.ExitCode -ne 0) {
        # Without a table the last line says what went wrong.
        $message = @($result.Output -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last 1
        throw ('winget reported an error ({0}): {1}' -f $result.ExitCode, ([string]$message).Trim())
    }

    [PSCustomObject]@{
        Updates = $updates
    }
}
