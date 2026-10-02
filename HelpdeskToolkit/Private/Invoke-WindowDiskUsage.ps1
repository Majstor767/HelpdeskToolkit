function Invoke-WindowDiskUsage {
    <#
    .SYNOPSIS
        Starts measuring what takes up the space of a drive, in the background.
    .DESCRIPTION
        Measuring folders can take up to half a minute, far too long for the thread
        that draws the window. Like the health check, the work is done in a second
        PowerShell runspace with its own copy of the module; Receive-WindowDiskUsage
        picks up the result.

        Get-DiskUsageDetail is an internal function of the module, so the runspace
        calls it inside the scope of the module.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Drive letter with colon, for example "C:".
        [Parameter(Mandatory)]
        [string]$Drive
    )

    $usage = $Gui.DiskUsage[$Drive]
    if (-not $usage -or $usage.Worker) {
        return
    }

    $work = {
        param($ManifestPath, $Drive)
        $module = Import-Module -Name $ManifestPath -PassThru
        & $module { param($Drive) Get-DiskUsageDetail -Drive $Drive } $Drive
    }

    $worker = [powershell]::Create()
    [void]$worker.AddScript($work.ToString()).AddArgument($Gui.ManifestPath).AddArgument($Drive)

    $usage.State = 'Loading'
    $usage.Error = ''
    $usage.Worker = $worker
    $usage.Handle = $worker.BeginInvoke()
}
