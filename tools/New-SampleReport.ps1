<#
.SYNOPSIS
    Generates the sample report in docs/ from fictional data.
.DESCRIPTION
    Real reports contain the computer name, IP addresses and hardware of the machine
    they were run on, so they are never committed to the repository. This script
    builds a report by hand from invented data and renders it with the module's own
    HTML and JSON exporters, so the sample always matches the current report layout.
.PARAMETER OutputPath
    Folder for the sample files. Defaults to the docs folder of the repository.
.EXAMPLE
    .\tools\New-SampleReport.ps1

    Rewrites docs\sample-report.html and docs\sample-report.json.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\docs')
)

$manifest = Join-Path -Path $PSScriptRoot -ChildPath '..\HelpdeskToolkit\HelpdeskToolkit.psd1'
$module = Import-Module -Name $manifest -Force -PassThru

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}
$folder = (Resolve-Path -LiteralPath $OutputPath).Path

# The exporters are private functions, so the block runs inside the module scope.
& $module {
    param($Folder)

    # Category, Check, Status, Value, Recommendation
    $rows = @(
        , @('System', 'Computer name', 'Info', 'FIN-LT-014', '')
        , @('System', 'Operating system', 'Info', 'Microsoft Windows 11 Pro 24H2 (build 26100)', '')
        , @('System', 'Windows installed', 'Info', '2024-11-04', '')
        , @('System', 'Manufacturer and model', 'Info', 'Contoso Ltd. ProBook 450', '')
        , @('System', 'Domain or workgroup', 'Info', 'Domain: corp.contoso.example', '')
        , @('System', 'Signed-in user', 'Info', 'CONTOSO\m.horvat', '')
        , @('System', 'Uptime', 'Warning', '12 d 4 h 37 min', 'Restart the computer; it has been running for more than 7 days. Use Restart, not Shut down: with Fast Startup enabled a shutdown does not reset the uptime.')
        , @('System', 'Windows activation', 'OK', 'Activated', '')
        , @('System', 'Startup programs', 'OK', '6 programs: Contoso VPN, OneDrive, SecurityHealth, Teams, Printer Assistant, Updater', '')

        , @('Specifications', 'Processor', 'Info', 'Contoso Core 8 2.40GHz, 8 cores / 16 threads, 2.4 GHz', '')
        , @('Specifications', 'Memory', 'Info', '16 GB (2 x 8 GB DDR4, 3200 MHz), 2 of 2 slots used', '')
        , @('Specifications', 'Graphics', 'Info', 'Contoso Graphics 770 (driver 31.0.101.5186), 1920 x 1080 @ 60 Hz', '')
        , @('Specifications', 'Motherboard', 'Info', 'Contoso Ltd. 0A1B2C', '')
        , @('Specifications', 'BIOS', 'Info', 'Contoso Ltd. 1.14.2 (2025-03-18), UEFI mode', '')
        , @('Specifications', 'Serial number', 'Info', 'CNT4012XYZ', '')

        , @('Hardware', 'CPU load', 'OK', '23 % (Contoso Core 8 2.40GHz)', '')
        , @('Hardware', 'Memory usage', 'Warning', '88 % (14 GB of 15.8 GB used)', 'Memory is almost full. Close unused applications and browser tabs; if this happens regularly, the computer needs more RAM.')
        , @('Hardware', 'Top memory consumers', 'Info', 'msedge (4.9 GB), Teams (2.1 GB), EXCEL (1.6 GB), OUTLOOK (1.2 GB), Memory Compression (0.9 GB)', '')
        , @('Hardware', 'Drive: Contoso NVMe 256GB', 'OK', 'SSD, NVMe, 238.5 GB, health: Healthy', '')
        , @('Hardware', 'Drive: Contoso HDD 500GB', 'Warning', 'HDD, SATA, 465.8 GB, health: Warning', 'The drive reports a problem and may fail. Back up the data now and plan to replace the drive.')
        , @('Hardware', 'Disk (C:)', 'Critical', '3.1 % free (7.4 GB of 237.9 GB)', 'The disk is almost full. Free up space now: Windows updates and applications can fail without free space.')
        , @('Hardware', 'Disk (D:)', 'OK', '61.4 % free (286.1 GB of 465.8 GB)', '')
        , @('Hardware', 'Battery', 'OK', '64 % (plugged in)', '')

        , @('Event Log', 'Unexpected shutdowns', 'Warning', '2 in the last 7 days', 'The computer lost power or crashed without shutting down properly. Check the power cable or battery, overheating and recently installed drivers.')
        , @('Event Log', 'System log - critical events', 'Warning', '2 in the last 7 days', 'Critical events usually mean crashes or unexpected shutdowns. Open Event Viewer (eventvwr.msc) > Windows Logs > System and filter by level Critical.')
        , @('Event Log', 'System log - errors', 'OK', '31 in the last 7 days', '')
        , @('Event Log', 'System log - top sources', 'Info', 'Service Control Manager (14), Microsoft-Windows-DistributedCOM (11), disk (4), Microsoft-Windows-Kernel-Power (2), Netwtw14 (2)', '')
        , @('Event Log', 'Application log - critical events', 'OK', '0 in the last 7 days', '')
        , @('Event Log', 'Application log - errors', 'OK', '12 in the last 7 days', '')
        , @('Event Log', 'Application log - top sources', 'Info', 'Application Error (7), Application Hang (3), MsiInstaller (2)', '')

        , @('Windows Update', 'Last installed update', 'OK', 'KB5000001 on 2026-09-18 (12 days ago)', '')
        , @('Windows Update', 'Pending restart', 'Warning', 'Yes (Windows Update)', 'Restart the computer to finish installing updates.')

        , @('Security', 'Defender real-time protection', 'OK', 'Enabled', '')
        , @('Security', 'Defender definitions', 'OK', '1 day old (updated 2026-09-29 06:12)', '')
        , @('Security', 'Firewall - Domain profile', 'OK', 'Enabled', '')
        , @('Security', 'Firewall - Private profile', 'OK', 'Enabled', '')
        , @('Security', 'Firewall - Public profile', 'Warning', 'Disabled', 'Turn on Windows Defender Firewall for this profile (Windows Security > Firewall & network protection), unless a third-party firewall is installed.')
        , @('Security', 'Secure Boot', 'OK', 'Enabled', '')
        , @('Security', 'TPM', 'Info', 'Requires admin', 'Run PowerShell as administrator to include this check.')
        , @('Security', 'BitLocker (C:)', 'Info', 'Requires admin', 'Run PowerShell as administrator to include this check.')

        , @('Network', 'Adapter: Contoso Wi-Fi 6 AX200 160MHz', 'Info', 'IPv4: 10.20.30.57 | Gateway: 10.20.30.1 | DNS: 10.20.30.10, 10.20.30.11 | DHCP: Yes | MAC: 00:00:5E:00:53:2A', '')
        , @('Network', 'Proxy', 'Info', 'Not configured', '')
        , @('Network', 'Ping default gateway', 'OK', '10.20.30.1 replied in 3 ms', '')
        , @('Network', 'Ping internet', 'OK', '1.1.1.1 replied in 18 ms', '')
        , @('Network', 'DNS resolution', 'OK', 'microsoft.com -> 203.0.113.25', '')
        , @('Network', 'HTTPS access', 'OK', 'https://www.microsoft.com reachable (HTTP 200)', '')

        , @('Services', 'DHCP Client (Dhcp)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'DNS Client (Dnscache)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Windows Event Log (EventLog)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Workstation (LanmanWorkstation)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Windows Defender Firewall (mpssvc)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Microsoft Defender Antivirus Service (WinDefend)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Windows Update (wuauserv)', 'Info', 'Stopped (start mode: Manual)', '')
        , @('Services', 'Background Intelligent Transfer Service (BITS)', 'Info', 'Stopped (start mode: Manual)', '')
        , @('Services', 'Print Spooler (Spooler)', 'Warning', 'Stopped (start mode: Auto)', 'The service should start automatically but is not running. Start it in services.msc and check the System event log for the reason it stopped.')
    )

    $results = @(
        foreach ($row in $rows) {
            New-CheckResult -Category $row[0] -Check $row[1] -Status $row[2] -Value $row[3] -Recommendation $row[4]
        }
    )

    $report = [PSCustomObject]@{
        ToolVersion     = $ExecutionContext.SessionState.Module.Version.ToString()
        ComputerName    = 'FIN-LT-014'
        GeneratedAt     = '2026-09-30 09:14:52'
        DurationSeconds = 6.3
        IsElevated      = $false
        EventLogDays    = 7
        Summary         = Get-HealthSummary -Result $results
        Results         = $results
    }

    Export-HealthReportHtml -Report $report -Path (Join-Path -Path $Folder -ChildPath 'sample-report.html')
    Export-HealthReportJson -Report $report -Path (Join-Path -Path $Folder -ChildPath 'sample-report.json')
} $folder
