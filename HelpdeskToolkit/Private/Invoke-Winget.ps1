function Invoke-Winget {
    <#
    .SYNOPSIS
        Runs winget, the package manager of Windows, with the given arguments and returns what it printed.
    .DESCRIPTION
        winget comes with Windows 10 (1809 and later) and Windows 11 as part of "App
        Installer". Only its listing commands are used here; nothing is installed,
        updated or removed.

        The program is started by its full path below the profile of the user and is
        never searched for in the PATH: a program with the same name placed somewhere
        else must not be run. Its output is read as UTF-8, which is what winget writes
        when it does not print to a console.

        winget asks the internet, so it can hang; after the given time it is ended.

        Returns an object with ExitCode and Output, or nothing when winget is not
        installed for this user.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Arguments,

        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 30
    )

    $path = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $start = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $start.FileName = $path
    $start.Arguments = $Arguments
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    $process = [System.Diagnostics.Process]::Start($start)
    try {
        # Both streams are read while the program runs; a full, unread stream would block it.
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw ('winget did not answer within {0} seconds' -f $TimeoutSeconds)
        }
        # Waits until the streams are read to their end.
        $process.WaitForExit()
        [void]$errors.Result

        [PSCustomObject]@{
            ExitCode = $process.ExitCode
            Output   = [string]$output.Result
        }
    }
    finally {
        $process.Dispose()
    }
}
