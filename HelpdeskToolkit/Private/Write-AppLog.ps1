function Write-AppLog {
    <#
    .SYNOPSIS
        Adds an entry to the log file of the application and returns the path of the file.
    .DESCRIPTION
        The window runs without a console, so an error nobody expected would otherwise
        leave no trace: the application would do nothing, or be gone, and nobody could
        say why. Such errors are written to app.log in the folder of the application
        (see Get-AppDataPath), which the Settings page opens with "Open the folder".

        An entry holds the time, the version of the tool, the version of PowerShell,
        whether the application had administrator rights, the message and, for an
        error, where in the code it happened. Nothing about the computer that is
        examined is written, and the file never leaves the computer.

        The file cannot grow without end: when it is larger than half a megabyte it
        becomes app.old.log (replacing the one before) and a new file is started.

        Writing the log must never be the reason something fails. When the file cannot
        be written, nothing is returned and nothing else happens.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # What happened, in one sentence.
        [Parameter(Mandatory)]
        [string]$Message,

        # The error, when there is one: its message and the place in the code are added.
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [ValidateSet('Error', 'Warning', 'Info')]
        [string]$Level = 'Error'
    )

    try {
        $path = Get-AppDataPath -ChildPath 'app.log'
        $folder = Split-Path -Path $path -Parent
        if (-not (Test-Path -LiteralPath $folder)) {
            [void](New-Item -Path $folder -ItemType Directory -Force)
        }

        if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 512KB) {
            Move-Item -LiteralPath $path -Destination (Get-AppDataPath -ChildPath 'app.old.log') -Force
        }

        $lines = New-Object -TypeName System.Collections.Generic.List[string]
        $lines.Add(('{0} [{1}] {2} (HelpdeskToolkit {3}, PowerShell {4}, administrator: {5})' -f
                (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message, (Get-ToolVersion), $PSVersionTable.PSVersion, (Test-IsAdministrator)))

        if ($ErrorRecord) {
            $exception = $ErrorRecord.Exception
            $lines.Add(('    {0}: {1}' -f $exception.GetType().FullName, (([string]$exception.Message) -replace '\s+', ' ')))
            foreach ($line in ([string]$ErrorRecord.ScriptStackTrace) -split "`r?`n" | Where-Object { $_ }) {
                $lines.Add("    $line")
            }
        }

        $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::AppendAllText($path, (($lines -join [Environment]::NewLine) + [Environment]::NewLine), $encoding)
        $path
    }
    catch {
        Write-Verbose "The log could not be written: $($_.Exception.Message)"
    }
}
