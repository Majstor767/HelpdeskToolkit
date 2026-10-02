function Invoke-WindowComponentDetail {
    <#
    .SYNOPSIS
        Starts reading everything about a component, in the background.
    .DESCRIPTION
        Some of the sources measure for a moment before they answer, which is too long
        for the thread that draws the window. Like the health check, the work is done
        in a second PowerShell runspace with its own copy of the module;
        Receive-WindowComponentDetail picks up the result.

        Get-ComponentDetail is an internal function of the module, so the runspace
        calls it inside the scope of the module.

        A reading that is already under way is not started a second time. While a
        component is read again, what was read before stays on the screen.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [ValidateSet('Cpu', 'Memory', 'Gpu')]
        [string]$Name
    )

    $state = $Gui.ComponentDetail[$Name]
    if (-not $state) {
        $state = @{ State = 'None'; Detail = $null; Error = ''; Worker = $null; Handle = $null; FinishedAt = $null }
        $Gui.ComponentDetail[$Name] = $state
    }
    if ($state.Worker) {
        return
    }

    $work = {
        param($ManifestPath, $Name)
        $module = Import-Module -Name $ManifestPath -PassThru
        & $module { param($Name) Get-ComponentDetail -Name $Name } $Name
    }

    $worker = [powershell]::Create()
    [void]$worker.AddScript($work.ToString()).AddArgument($Gui.ManifestPath).AddArgument($Name)

    if ($state.State -ne 'Done') {
        $state.State = 'Loading'
    }
    $state.Worker = $worker
    $state.Handle = $worker.BeginInvoke()
}
