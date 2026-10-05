function Write-WindowError {
    <#
    .SYNOPSIS
        Records an error nobody expected and tells the user about it, without ending the application.
    .DESCRIPTION
        Every click, key and timer of the window runs a piece of PowerShell. An error
        in one of them that nothing catches would end the whole application at once,
        without a word, because the window has no console. Show-PCHealthCheck sends
        such errors here instead: the error is written to the log of the application
        (Write-AppLog) and the status line says so and names the file. The window
        stays open; what the user was doing can be tried again.

        The timers of the window catch their errors themselves and pass the error
        record (-ErrorRecord): a timer whose handler fails is never called again by
        Windows, although the application goes on. Everything else arrives as the
        exception the window reports (-Exception).

        A timer that fails keeps failing several times a second. The same error is
        therefore written only once a minute, so the log stays readable.

        Returns $true when the error was written to the log.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Record')]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory, ParameterSetName = 'Record')]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory, ParameterSetName = 'Exception')]
        [System.Exception]$Exception
    )

    $record = $ErrorRecord
    if (-not $record) {
        # An error of PowerShell knows the place in the script; the wrappers .NET puts
        # around it (an event handler that failed) do not.
        $inner = $Exception
        while ($inner -and -not $record) {
            if ($inner -is [System.Management.Automation.IContainsErrorRecord] -and $inner.ErrorRecord) {
                $record = $inner.ErrorRecord
                # A record that only points back at its exception says less than the exception.
                if ($record.Exception -is [System.Management.Automation.ParentContainsErrorRecordException]) {
                    $record = $null
                    $Exception = $inner
                    break
                }
            }
            $inner = $inner.InnerException
        }
    }
    if (-not $record) {
        $record = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $Exception, 'UnexpectedError',
            ([System.Management.Automation.ErrorCategory]::NotSpecified), $null
    }

    $text = [string]$record.Exception.Message
    $last = $Gui['LastError']
    if ($last -and $last.Text -eq $text -and ((Get-Date) - $last.At).TotalSeconds -lt 60) {
        return $false
    }
    $Gui['LastError'] = @{ Text = $text; At = Get-Date }

    $path = Write-AppLog -Message 'An unexpected error in the window' -ErrorRecord $record
    try {
        $Gui.Controls.StatusText.Text = if ($path) {
            (Get-LocalizedText 'Something went wrong; the application keeps running. The details were written to {0}') -f $path
        }
        else {
            (Get-LocalizedText 'Something went wrong; the application keeps running: {0}') -f $text
        }
    }
    catch {
        Write-Verbose "The status line could not be updated: $($_.Exception.Message)"
    }

    [bool]$path
}
