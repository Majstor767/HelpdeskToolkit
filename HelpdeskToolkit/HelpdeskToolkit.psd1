@{
    RootModule           = 'HelpdeskToolkit.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '0e354cc9-7f28-44f2-96b4-5782f88829b9'
    Author               = 'Antonio Majstorovic'
    Copyright            = '(c) 2026 Antonio Majstorovic. Released under the MIT License.'
    Description          = 'Read-only diagnostics for Windows PCs: one command checks system health and produces a report with problems and recommendations for helpdesk technicians.'

    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    # Listed explicitly (no wildcards) so the module auto-loads quickly and
    # nothing internal is exported by accident.
    FunctionsToExport    = @(
        'Get-ComputerSpecification'
        'Get-EventLogHealth'
        'Get-HardwareHealth'
        'Get-NetworkHealth'
        'Get-SecurityHealth'
        'Get-ServiceHealth'
        'Get-SystemHealth'
        'Get-WindowsUpdateHealth'
        'Invoke-PCHealthCheck'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags = @('Helpdesk', 'Diagnostics', 'HealthCheck', 'Windows', 'ITSupport')
        }
    }
}
