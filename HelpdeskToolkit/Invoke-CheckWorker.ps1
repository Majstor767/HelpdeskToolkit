<#
.SYNOPSIS
    Runs one health check in a process of its own and saves the report as a JSON file.

.DESCRIPTION
    Started by the application window for every check (see Private\Invoke-WindowCheck.ps1);
    it is not meant to be run by hand. Use Invoke-HealthCheck.ps1 or Get-PCHealthReport
    for that.

    Why a process of its own: a check loads a dozen Windows modules and reads a lot of
    data. PowerShell does not give that memory back while the process lives, so a
    window that checked the computer inside its own process stayed several hundred
    megabytes large for as long as it was open. This process ends with the check, and
    Windows gets all of its memory back.

    The check itself is the public command Get-PCHealthReport. It runs in a second
    runspace, so this script can pass its progress on while it works.

    What is written to standard output, one line each:

        P|<percent>|<categories that are still running>|<how many are done>
        E|<why the check failed>

    The exit code is 0 when the report was written and 1 when it was not.

.PARAMETER OutputPath
    Full path of the JSON file to write. The file has the format of the JSON reports
    of the tool (UTF-8 without a byte order mark).

.PARAMETER Days
    How many days of the event logs are examined.

.PARAMETER SkipNetwork
    Leaves out the tests that need the network.

.PARAMETER AllowCached
    Lets the check reuse measurements that take long and change slowly (the sizes of
    the folders of a full drive), when they are young enough.

.PARAMETER CachePath
    Folder in which those measurements are kept from one check to the next. Without
    it they are only remembered inside this process, which is of no use here.

.PARAMETER Activity
    The name of the progress records of Get-PCHealthReport. Windows cmdlets write
    progress of their own, which is not passed on.

.EXAMPLE
    powershell.exe -NoProfile -File Invoke-CheckWorker.ps1 -OutputPath C:\Temp\report.json

    Checks this computer and writes the report to C:\Temp\report.json.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath,

    [int]$Days = 7,

    [switch]$SkipNetwork,

    [switch]$AllowCached,

    [string]$CachePath = '',

    [string]$Activity = 'PC Health Check'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$exitCode = 1
$shell = $null
try {
    # The lines are read as UTF-8 by the window; a message of Windows may contain
    # letters that the code page of the console does not have.
    try {
        [Console]::OutputEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    }
    catch {
        Write-Verbose "The output stays in the code page of the console: $($_.Exception.Message)"
    }

    if ($CachePath) {
        $env:HELPDESKTOOLKIT_CACHE = $CachePath
    }

    $work = {
        param($ManifestPath, $Days, $SkipNetwork, $AllowCached)
        Import-Module -Name $ManifestPath
        Get-PCHealthReport -Days $Days -SkipNetwork:$SkipNetwork -AllowCached:$AllowCached | ConvertTo-Json -Depth 5
    }

    $manifest = Join-Path -Path $PSScriptRoot -ChildPath 'HelpdeskToolkit.psd1'
    $shell = [powershell]::Create()
    [void]$shell.AddScript($work.ToString()).AddArgument($manifest).AddArgument($Days).AddArgument($SkipNetwork.IsPresent).AddArgument($AllowCached.IsPresent)
    $handle = $shell.BeginInvoke()

    # Every progress record of the check becomes one line, as soon as it is there.
    $seen = 0
    do {
        $finished = $handle.AsyncWaitHandle.WaitOne(100)
        $records = $shell.Streams.Progress
        while ($seen -lt $records.Count) {
            $record = $records[$seen]
            $seen++
            if ($record.Activity -eq $Activity -and $record.PercentComplete -ge 0) {
                [Console]::Out.WriteLine(('P|{0}|{1}|{2}' -f $record.PercentComplete, $record.StatusDescription, $record.CurrentOperation))
                [Console]::Out.Flush()
            }
        }
    } until ($finished)

    $json = @($shell.EndInvoke($handle)) | Where-Object { $_ -is [string] -and $_ } | Select-Object -Last 1
    if (-not $json) {
        $reason = if ($shell.Streams.Error.Count -gt 0) { $shell.Streams.Error[0].ToString() } else { 'No report was returned.' }
        throw $reason
    }

    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($OutputPath, [string]$json, $encoding)
    $exitCode = 0
}
catch {
    # One line: the window shows it as the reason.
    [Console]::Out.WriteLine('E|{0}' -f (([string]$_.Exception.GetBaseException().Message) -replace '\s+', ' '))
    [Console]::Out.Flush()
}
finally {
    if ($shell) {
        $shell.Dispose()
    }
}

exit $exitCode
