function Get-RemoteHealthReport {
    <#
    .SYNOPSIS
        Runs all health checks on another computer and returns its report.
    .DESCRIPTION
        Uses PowerShell remoting (WinRM), the standard way to manage Windows computers
        over the network. Remoting must be enabled on the other computer ("Enable-
        PSRemoting", which is the default on Windows Server and is usually switched on
        by group policy in a company), and the account in use must be an administrator
        there. Because of that, the checks marked "Requires admin" are included.

        Nothing is installed on the other computer: the functions are loaded into the
        memory of the remote session (see Get-RemoteModuleScript), the checks run
        there, and the report travels back as JSON text. JSON is used because the
        objects of a remote session lose their nested lists on the way.

        The connectivity tests (ping, DNS, HTTPS) are made from the other computer, so
        they describe its network connection, not the one of this computer.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.HealthReport')]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [int]$Days = 7,

        [switch]$SkipNetwork
    )

    $configFolder = Join-Path -Path $script:ModuleRoot -ChildPath 'Config'
    $thresholdText = [System.IO.File]::ReadAllText((Join-Path -Path $configFolder -ChildPath 'Thresholds.psd1'))
    $descriptionText = [System.IO.File]::ReadAllText((Join-Path -Path $configFolder -ChildPath 'Descriptions.psd1'))

    # Runs on the other computer: loads the functions as a module that only exists in
    # memory, runs the checks and returns the report as text.
    $remoteWork = {
        param($Source, $ThresholdText, $DescriptionText, $ToolVersion, $Days, $SkipNetwork)

        $module = New-Module -Name HelpdeskToolkitRemote -ScriptBlock ([scriptblock]::Create($Source)) -ArgumentList $ThresholdText, $DescriptionText, $ToolVersion
        $report = & $module { param($Days, $SkipNetwork) Get-PCHealthReport -Days $Days -SkipNetwork:$SkipNetwork } $Days $SkipNetwork
        $report | ConvertTo-Json -Depth 6 -Compress
    }

    $parameters = @{
        ComputerName = $ComputerName
        ScriptBlock  = $remoteWork
        ArgumentList = @((Get-RemoteModuleScript), $thresholdText, $descriptionText, (Get-ToolVersion), $Days, [bool]$SkipNetwork)
        ErrorAction  = 'Stop'
    }
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $parameters.Credential = $Credential
    }

    try {
        $json = Invoke-Command @parameters | Select-Object -Last 1
    }
    catch {
        throw ('The checks could not be run on {0}: {1} PowerShell remoting must be enabled on that computer and the account must be an administrator there.' -f $ComputerName, $_.Exception.Message)
    }

    ConvertTo-HealthReport -InputObject ([string]$json | ConvertFrom-Json)
}
