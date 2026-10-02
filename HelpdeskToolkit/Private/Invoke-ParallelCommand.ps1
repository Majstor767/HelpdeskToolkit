function Invoke-ParallelCommand {
    <#
    .SYNOPSIS
        Runs several commands of this module side by side and returns what each one produced.
    .DESCRIPTION
        The check categories do not depend on each other and spend most of their time
        waiting for Windows to answer. Run one after the other they take the sum of
        their times; run side by side they take about as long as the slowest one.

        Every command runs in a runspace of its own, which is a separate thread with
        its own copy of the module, taken from a pool of at most -ThrottleLimit
        runspaces. The commands are called inside the module, so private functions
        can be run as well.

        A command that fails does not stop the others: its error is returned in place
        of its output.

        Returns an ordered table with one entry per job, in the order of -Job. Each
        entry is an object with Output (what the command returned) and Error (the
        error record when it failed, otherwise nothing).
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        # Name of the job -> a table with Command (name of the function) and Parameters.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Job,

        # The manifest the runspaces load the module from.
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        # How many commands run at the same time.
        [ValidateRange(1, 64)]
        [int]$ThrottleLimit = 4,

        # Called in the session of the caller at the start and whenever a job has
        # finished, with the number of finished jobs, the number of all jobs and the
        # names of the ones that are not finished yet.
        [scriptblock]$OnProgress
    )

    $work = {
        param($ManifestPath, $Command, $Parameters)
        try {
            $module = Import-Module -Name $ManifestPath -PassThru -ErrorAction Stop
            $output = @(& $module { param($Name, $Arguments) & $Name @Arguments -ErrorAction Stop } $Command $Parameters)
            [PSCustomObject]@{ Output = $output; Error = $null }
        }
        catch {
            [PSCustomObject]@{ Output = @(); Error = $_ }
        }
    }

    $names = @($Job.Keys)
    $outcome = [ordered]@{}
    $running = @{}
    $pool = [runspacefactory]::CreateRunspacePool(1, [math]::Min($ThrottleLimit, [math]::Max(1, $names.Count)))
    $pool.Open()

    try {
        foreach ($name in $names) {
            $parameters = if ($Job[$name].ContainsKey('Parameters') -and $Job[$name].Parameters) { $Job[$name].Parameters } else { @{} }
            $shell = [powershell]::Create()
            $shell.RunspacePool = $pool
            [void]$shell.AddScript($work.ToString()).AddArgument($ManifestPath).AddArgument([string]$Job[$name].Command).AddArgument($parameters)
            $running[$name] = @{ Shell = $shell; Handle = $shell.BeginInvoke() }
        }

        if ($OnProgress) {
            & $OnProgress 0 $names.Count $names
        }

        $collected = @{}
        while ($collected.Count -lt $names.Count) {
            $finished = @($names | Where-Object { -not $collected.ContainsKey($_) -and $running[$_].Handle.IsCompleted })
            foreach ($name in $finished) {
                try {
                    $collected[$name] = @($running[$name].Shell.EndInvoke($running[$name].Handle)) | Select-Object -Last 1
                }
                catch {
                    # The runspace itself failed, for example because it was closed.
                    $collected[$name] = [PSCustomObject]@{ Output = @(); Error = $_ }
                }
                if (-not $collected[$name]) {
                    $collected[$name] = [PSCustomObject]@{ Output = @(); Error = $null }
                }
            }

            if ($finished.Count -gt 0 -and $OnProgress) {
                & $OnProgress $collected.Count $names.Count @($names | Where-Object { -not $collected.ContainsKey($_) })
            }
            if ($collected.Count -lt $names.Count) {
                Start-Sleep -Milliseconds 40
            }
        }

        foreach ($name in $names) {
            $outcome[$name] = $collected[$name]
        }
    }
    finally {
        foreach ($entry in $running.Values) {
            $entry.Shell.Dispose()
        }
        $pool.Dispose()
    }

    $outcome
}
