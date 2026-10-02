function Get-CimInstanceBatch {
    <#
    .SYNOPSIS
        Reads several WMI classes at the same time and returns the instances of each.
    .DESCRIPTION
        The performance classes of Windows (Win32_PerfFormattedData_...) need about a
        quarter of a second each, because Windows works their values out when it is
        asked. The Live monitor reads seven of them for one measurement: one after the
        other that takes almost two seconds, all at once less than half a second. The
        values then also describe the same moment instead of being spread over two
        seconds.

        Each class is read by Get-CimInstance in a small runspace of its own. The
        runspaces are kept for the next call (in $script:CimPool), so only the first
        measurement pays for creating them.

        A class that cannot be read does not stop the others: its error is returned in
        place of its instances.

        Returns a table with one entry per class: an object with Rows (the instances)
        and Error (the error record, or nothing).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]]$ClassName
    )

    $result = @{}

    # In the session of the caller, one class after the other: for the tests, whose
    # mocks only exist there (see $script:CheckThrottleLimit), and for a single class.
    if ($script:CheckThrottleLimit -eq 1 -or $ClassName.Count -le 1) {
        foreach ($class in $ClassName) {
            try {
                $result[$class] = [PSCustomObject]@{ Rows = @(Get-CimInstance -ClassName $class -ErrorAction Stop); Error = $null }
            }
            catch {
                $result[$class] = [PSCustomObject]@{ Rows = @(); Error = $_ }
            }
        }
        return $result
    }

    if (-not $script:CimPool -or $script:CimPool.RunspacePoolStateInfo.State -ne [System.Management.Automation.Runspaces.RunspacePoolState]::Opened) {
        $script:CimPool = [runspacefactory]::CreateRunspacePool(1, 8)
        $script:CimPool.Open()
    }

    $jobs = foreach ($class in $ClassName) {
        $shell = [powershell]::Create()
        $shell.RunspacePool = $script:CimPool
        [void]$shell.AddCommand('Get-CimInstance').AddParameter('ClassName', $class).AddParameter('ErrorAction', 'Stop')
        @{ Class = $class; Shell = $shell; Handle = $shell.BeginInvoke() }
    }

    foreach ($job in $jobs) {
        try {
            $result[$job.Class] = [PSCustomObject]@{ Rows = @($job.Shell.EndInvoke($job.Handle)); Error = $null }
        }
        catch {
            # EndInvoke wraps the error of the command; the check wants the error itself.
            $record = $_
            if ($_.Exception.InnerException -is [System.Management.Automation.IContainsErrorRecord]) {
                $record = $_.Exception.InnerException.ErrorRecord
            }
            $result[$job.Class] = [PSCustomObject]@{ Rows = @(); Error = $record }
        }
        finally {
            $job.Shell.Dispose()
        }
    }

    $result
}
