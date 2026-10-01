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
    [string]$OutputPath
)

# The default is set here and not in the param block: Windows PowerShell 5.1 does not
# know $PSScriptRoot yet while it evaluates parameter defaults of a script run with -File.
if (-not $OutputPath) {
    $OutputPath = Join-Path -Path $PSScriptRoot -ChildPath '..\docs'
}

$manifest = Join-Path -Path $PSScriptRoot -ChildPath '..\HelpdeskToolkit\HelpdeskToolkit.psd1'
$module = Import-Module -Name $manifest -Force -PassThru

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}
$folder = (Resolve-Path -LiteralPath $OutputPath).Path

# The exporters are private functions, so the block runs inside the module scope.
& $module {
    param($Folder)

    # The sample shows a run without administrator rights. The text of a skipped check
    # is taken from the module, so the sample always shows the current wording.
    $adminOnly = (New-AdminRequiredResult -Category 'Sample' -Check 'Sample').Recommendation

    # Category, Check, Status, Value, Recommendation
    $rows = @(
        , @('System', 'Computer name', 'Info', 'FIN-LT-014', '')
        , @('System', 'Operating system', 'Info', 'Microsoft Windows 11 Pro 24H2 (build 26100)', '')
        , @('System', 'Windows support', 'Warning', 'Supported until 2026-10-13 (13 days left)', 'Support for this Windows version ends soon. Install the newest feature update: Settings > Windows Update.')
        , @('System', 'Windows installed', 'Info', '2024-11-04', '')
        , @('System', 'Manufacturer and model', 'Info', 'Contoso Ltd. ProBook 450', '')
        , @('System', 'Domain or workgroup', 'Info', 'Domain: corp.contoso.example', '')
        , @('System', 'Signed-in user', 'Info', 'CONTOSO\m.horvat', '')
        , @('System', 'Time zone', 'Info', '(UTC+01:00) Sarajevo, Skopje, Warsaw, Zagreb', '')
        , @('System', 'Uptime', 'Warning', '12 d 4 h 37 min', 'Restart the computer; it has been running for more than 7 days. Use Restart, not Shut down: with Fast Startup enabled a shutdown does not reset the uptime.')
        , @('System', 'Stability index', 'OK', '7.4 of 10', '')
        , @('System', 'Windows activation', 'OK', 'Activated', '')
        , @('System', 'Startup programs', 'OK', '12 programs: Chat Client, Cloud Backup, Contoso Updater, Contoso VPN, Mail Notifier, OneDrive, PDF Helper, Printer Assistant and 4 more', '')
        , @('System', 'Scheduled tasks', 'Info', '4 tasks: Cloud Backup Sync, Contoso Updater, PDF Helper Update, Printer Assistant Check', '')
        , @('System', 'Power plan', 'Info', 'Balanced', '')
        , @('System', 'Fast Startup', 'Info', 'Enabled', '')
        , @('System', 'Last startup duration', 'Info', 'Requires admin', $adminOnly)
        , @('System', 'User profiles', 'Info', 'Requires admin', $adminOnly)

        , @('Specifications', 'Processor', 'Info', 'Contoso Core 8 2.40GHz, 8 cores / 16 threads, 2.4 GHz', '')
        , @('Specifications', 'Processor details', 'Info', 'L2 cache 10 MB, L3 cache 24 MB, 64-bit, virtualization enabled in firmware', '')
        , @('Specifications', 'Memory', 'Info', '16 GB (2 x 8 GB DDR4, 3200 MHz), 2 of 2 slots used', '')
        , @('Specifications', 'Memory module', 'Info', 'DIMM A: 8 GB DDR4, 3200 MHz, Contoso CT8G4SFS832A', '')
        , @('Specifications', 'Memory module', 'Info', 'DIMM B: 8 GB DDR4, 3200 MHz, Contoso CT8G4SFS832A', '')
        , @('Specifications', 'Graphics', 'Info', 'Contoso Graphics 770 (driver 31.0.101.5186 from 2025-11-03), 1920 x 1080 @ 60 Hz', '')
        , @('Specifications', 'Display', 'Info', 'Contoso 24W (CTS, 2023)', '')
        , @('Specifications', 'Storage', 'Info', 'Contoso NVMe 256GB, 238.5 GB SSD (NVMe), firmware 2B4QCXM7', '')
        , @('Specifications', 'Storage', 'Info', 'Contoso HDD 500GB, 465.8 GB HDD (SATA), firmware 0001SDM1', '')
        , @('Specifications', 'Audio devices', 'Info', 'Contoso High Definition Audio, Contoso USB Headset and 1 virtual', '')
        , @('Specifications', 'Input devices', 'Info', 'Contoso Precision Touchpad, Contoso Wireless Mouse M2, Standard PS/2 Keyboard', '')
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
        , @('Hardware', 'Largest folders (C:)', 'Info', 'Users\m.horvat\AppData 71.2 GB or more, Windows 28.4 GB or more, Program Files 19.6 GB, Users\m.horvat\Downloads 11.2 GB, Users\m.horvat\Videos 9.7 GB, hiberfil.sys 6.3 GB and 6 more', 'This is where the space of the disk goes. Start cleaning up with the largest folders that hold your own files (Downloads, Videos, Desktop); do not delete anything inside Windows, Program Files or ProgramData by hand. "Or more" means the folder was too large to be measured completely in the time allowed.')
        , @('Hardware', 'Temporary files', 'Warning', '6.8 GB', 'Temporary files take up a lot of space. Remove them in Settings > System > Storage > Temporary files.')
        , @('Hardware', 'Downloads folder', 'Info', '11.2 GB in 348 files', '')
        , @('Hardware', 'Recycle Bin', 'OK', '1.3 GB', '')
        , @('Hardware', 'Hibernation file', 'Info', '6.3 GB', 'The system disk is short of space and this file takes up a good part of it. On a computer that is never put into hibernation, an administrator can remove the file with "powercfg /hibernate off"; this also turns off Fast Startup, so starting Windows takes a little longer.')
        , @('Hardware', 'Page file', 'OK', '34 % (1632 MB of 4800 MB used)', '')
        , @('Hardware', 'Drive details', 'Info', 'Requires admin', $adminOnly)
        , @('Hardware', 'File system', 'Info', 'Requires admin', $adminOnly)
        , @('Hardware', 'System temporary files', 'Info', 'Requires admin', $adminOnly)
        , @('Hardware', 'Devices with problems', 'OK', 'None', '')
        , @('Hardware', 'Unsigned drivers', 'OK', 'None', '')
        , @('Hardware', 'Old drivers', 'Info', '1 driver: Contoso Card Reader (2019-05-14)', 'These drivers are older than 5 years. An old driver that works needs no attention; when the device misbehaves, installing the current driver from the maker is the first thing to try.')
        , @('Hardware', 'Battery', 'OK', '64 % (plugged in)', '')
        , @('Hardware', 'Battery health', 'OK', '86 % of the original capacity (43000 of 50000 mWh), 214 charge cycles', '')

        , @('Software', 'Installed programs', 'Info', '12 programs: 7-Zip 24.08, Chat Client 5.2, Contoso Office 16.0, Contoso VPN 3.1, Mail Client 12.4, PDF Reader 2025.1, Printer Assistant 2.0, Screenshot Tool 4.0 and 4 more', '')
        , @('Software', 'Recently installed', 'Info', '2 in the last 30 days: Screenshot Tool (2026-09-22), PDF Reader (2026-09-11)', '')
        , @('Software', 'Application crashes', 'Warning', '9 in the last 7 days: EXCEL.EXE (6), msedge.exe (2), Teams.exe (1)', 'Programs crash more often than usual. Update or reinstall the program at the top of the list; the details of each crash are in Event Viewer (eventvwr.msc) > Windows Logs > Application, source "Application Error".')
        , @('Software', 'Browser extensions', 'Info', '6 extensions: Chrome (2), Edge (4)', '')
        , @('Software', 'Default browser', 'Info', 'Microsoft Edge', '')

        , @('Event Log', 'Unexpected shutdowns', 'Warning', '2 in the last 7 days', 'The computer lost power or crashed without shutting down properly. Check the power cable or battery, overheating and recently installed drivers.')
        , @('Event Log', 'Blue screens', 'OK', '0 in the last 7 days', '')
        , @('Event Log', 'Disk errors', 'Warning', '3 in the last 7 days', 'The disk or the file system reported problems. Back up important data, check the drive health in the Hardware category and run "chkdsk /scan" as administrator. Repeated errors usually mean the drive or its cable is failing.')
        , @('Event Log', 'Hardware errors', 'OK', '0 in the last 7 days', '')
        , @('Event Log', 'System log - critical events', 'Warning', '2 in the last 7 days', 'Critical events usually mean crashes or unexpected shutdowns. Open Event Viewer (eventvwr.msc) > Windows Logs > System and filter by level Critical.')
        , @('Event Log', 'System log - errors', 'OK', '31 in the last 7 days', '')
        , @('Event Log', 'System log - top sources', 'Info', 'Service Control Manager (14), Microsoft-Windows-DistributedCOM (11), disk (4), Microsoft-Windows-Kernel-Power (2), Netwtw14 (2)', '')
        , @('Event Log', 'Application log - critical events', 'OK', '0 in the last 7 days', '')
        , @('Event Log', 'Application log - errors', 'OK', '12 in the last 7 days', '')
        , @('Event Log', 'Application log - top sources', 'Info', 'Application Error (7), Application Hang (3), MsiInstaller (2)', '')

        , @('Windows Update', 'Last installed update', 'OK', 'KB5000001 on 2026-09-18 (12 days ago)', '')
        , @('Windows Update', 'Pending restart', 'Warning', 'Yes (Windows Update)', 'Restart the computer to finish installing updates.')
        , @('Windows Update', 'Updates paused', 'OK', 'No', '')
        , @('Windows Update', 'Pending updates', 'Info', '1 update: 2026-09 Cumulative Update Preview for Windows 11 (KB5000002)', 'Windows has found updates that are not installed yet. Install them in Settings > Windows Update.')
        , @('Windows Update', 'Failed updates', 'OK', 'None in the last 30 days', '')

        , @('Security', 'Defender real-time protection', 'OK', 'Enabled', '')
        , @('Security', 'Defender definitions', 'OK', '1 day old (updated 2026-09-29 06:12)', '')
        , @('Security', 'Tamper protection', 'OK', 'Enabled', '')
        , @('Security', 'Defender last scan', 'OK', '3 days ago', '')
        , @('Security', 'Threat history', 'OK', 'No threats found', '')
        , @('Security', 'Firewall - Domain profile', 'OK', 'Enabled', '')
        , @('Security', 'Firewall - Private profile', 'OK', 'Enabled', '')
        , @('Security', 'Firewall - Public profile', 'Warning', 'Disabled', 'Turn on Windows Defender Firewall for this profile (Windows Security > Firewall & network protection), unless a third-party firewall is installed.')
        , @('Security', 'User Account Control', 'OK', 'Enabled', '')
        , @('Security', 'Remote Desktop', 'OK', 'Disabled', '')
        , @('Security', 'Account type', 'OK', 'Standard user', '')
        , @('Security', 'Administrators', 'Info', '2 members: Domain Admins, support', '')
        , @('Security', 'Automatic sign-in', 'OK', 'Disabled', '')
        , @('Security', 'Local accounts', 'Info', '1 enabled: support', '')
        , @('Security', 'Guest account', 'OK', 'Disabled', '')
        , @('Security', 'Built-in Administrator account', 'OK', 'Disabled', '')
        , @('Security', 'Shared folders', 'OK', 'None', '')
        , @('Security', 'Listening ports', 'Info', '4 ports open to the network: spoolsv: 49668, svchost: 135, 5040, System: 445', '')
        , @('Security', 'File History', 'Info', 'Not set up', '')
        , @('Security', 'OneDrive', 'Info', 'Signed in and running', '')
        , @('Security', 'System Restore', 'Info', 'On (the restore points are only shown to administrators)', '')
        , @('Security', 'Secure Boot', 'OK', 'Enabled', '')
        , @('Security', 'TPM', 'Info', 'Requires admin', $adminOnly)
        , @('Security', 'BitLocker (C:)', 'Info', 'Requires admin', $adminOnly)
        , @('Security', 'Failed sign-ins', 'Info', 'Requires admin', $adminOnly)
        , @('Security', 'Account lockouts', 'Info', 'Requires admin', $adminOnly)

        , @('Network', 'Adapter: Contoso Wi-Fi 6 AX200 160MHz', 'Info', 'IPv4: 10.20.30.57 | Gateway: 10.20.30.1 | DNS: 10.20.30.10, 10.20.30.11 | DHCP: Yes | MAC: 00:00:5E:00:53:2A | Speed: 867 Mbps', '')
        , @('Network', 'Wi-Fi: CONTOSO-CORP', 'OK', '74 % signal, 5 GHz, 802.11ax, security: WPA2-Enterprise', '')
        , @('Network', 'Network profile', 'Info', 'Wi-Fi: Domain (corp.contoso.example)', '')
        , @('Network', 'Proxy', 'Info', 'Not configured', '')
        , @('Network', 'Hosts file', 'OK', 'No custom entries', '')
        , @('Network', 'Mapped network drives', 'Info', 'H: -> \\fs01.corp.contoso.example\home\m.horvat, S: -> \\fs01.corp.contoso.example\shared', '')
        , @('Network', 'Ping default gateway', 'OK', '10.20.30.1 replied in 3 ms', '')
        , @('Network', 'Ping internet', 'OK', '1.1.1.1 replied in 18 ms', '')
        , @('Network', 'DNS resolution', 'OK', 'microsoft.com -> 203.0.113.25', '')
        , @('Network', 'HTTPS access', 'OK', 'https://www.microsoft.com reachable (HTTP 200)', '')
        , @('Network', 'Clock accuracy', 'OK', 'Differs from internet time by 1 second', '')

        , @('Printers', 'Default printer', 'Info', 'Contoso LaserJet 400 (2nd floor)', '')
        , @('Printers', 'Installed printers', 'Info', '3 printers: Contoso LaserJet 400 (2nd floor), Microsoft Print to PDF, OneNote (Desktop)', '')
        , @('Printers', 'Print queue', 'OK', '0 documents waiting', '')

        , @('Services', 'DHCP Client (Dhcp)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'DNS Client (Dnscache)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Windows Event Log (EventLog)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Workstation (LanmanWorkstation)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Windows Defender Firewall (mpssvc)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Microsoft Defender Antivirus Service (WinDefend)', 'OK', 'Running (start mode: Auto)', '')
        , @('Services', 'Windows Update (wuauserv)', 'Info', 'Stopped (start mode: Manual)', '')
        , @('Services', 'Background Intelligent Transfer Service (BITS)', 'Info', 'Stopped (start mode: Manual)', '')
        , @('Services', 'Print Spooler (Spooler)', 'Warning', 'Stopped (start mode: Auto)', 'The service should start automatically but is not running. Start it in services.msc and check the System event log for the reason it stopped.')
        , @('Services', 'Third-party services', 'Info', '3 services: Cloud Backup Service, Contoso Updater Service, Contoso VPN Service', '')
    )

    # Allowed range and typical value of the measurements, by check name. They are
    # taken from the real configuration so the sample shows the current limits.
    $limits = Get-HealthThreshold
    $references = @{
        'Uptime'                            = @((Format-AllowedRange -Warning $limits.Uptime.WarningDays -Unit 'days'), $limits.Uptime.Typical)
        'Startup programs'                  = @((Format-AllowedRange -Warning $limits.Startup.WarningProgramCount), $limits.Startup.Typical)
        'CPU load'                          = @((Format-AllowedRange -Warning $limits.Cpu.WarningPercent -Critical $limits.Cpu.CriticalPercent -Unit '%'), $limits.Cpu.Typical)
        'Memory usage'                      = @((Format-AllowedRange -Warning $limits.Memory.WarningPercent -Critical $limits.Memory.CriticalPercent -Unit '%'), $limits.Memory.Typical)
        'Disk (C:)'                         = @((Format-AllowedRange -Warning $limits.Disk.WarningFreePercent -Critical $limits.Disk.CriticalFreePercent -Unit '% free' -LowerIsWorse), $limits.Disk.Typical)
        'Disk (D:)'                         = @((Format-AllowedRange -Warning $limits.Disk.WarningFreePercent -Critical $limits.Disk.CriticalFreePercent -Unit '% free' -LowerIsWorse), $limits.Disk.Typical)
        'Battery'                           = @((Format-AllowedRange -Warning $limits.Battery.WarningPercent -Critical $limits.Battery.CriticalPercent -Unit '%' -LowerIsWorse), '')
        'Battery health'                    = @((Format-AllowedRange -Warning $limits.Battery.HealthWarningPercent -Critical $limits.Battery.HealthCriticalPercent -Unit '%' -LowerIsWorse -Maximum 100), $limits.Battery.TypicalHealth)
        'Wi-Fi: CONTOSO-CORP'               = @(('signal {0} - 100 %' -f $limits.Network.WifiSignalWarningPercent), $limits.Network.TypicalWifiSignal)
        'Unexpected shutdowns'              = @((Format-AllowedRange -Warning $limits.EventLog.UnexpectedShutdownWarningAbove), $limits.EventLog.TypicalUnexpectedShutdowns)
        'System log - critical events'      = @((Format-AllowedRange -Warning $limits.EventLog.CriticalEventWarningAbove -Critical $limits.EventLog.CriticalEventCriticalAbove), $limits.EventLog.TypicalCriticalEvents)
        'Application log - critical events' = @((Format-AllowedRange -Warning $limits.EventLog.CriticalEventWarningAbove -Critical $limits.EventLog.CriticalEventCriticalAbove), $limits.EventLog.TypicalCriticalEvents)
        'System log - errors'               = @((Format-AllowedRange -Warning $limits.EventLog.ErrorEventWarningAbove), $limits.EventLog.TypicalErrorEvents)
        'Application log - errors'          = @((Format-AllowedRange -Warning $limits.EventLog.ErrorEventWarningAbove), $limits.EventLog.TypicalErrorEvents)
        'Last installed update'             = @((Format-AllowedRange -Warning $limits.WindowsUpdate.WarningDaysSinceLastUpdate -Unit 'days'), $limits.WindowsUpdate.Typical)
        'Defender definitions'              = @((Format-AllowedRange -Warning $limits.Defender.SignatureWarningDays -Critical $limits.Defender.SignatureCriticalDays -Unit 'days'), $limits.Defender.Typical)
        'Ping default gateway'              = @('', $limits.Network.TypicalGatewayPing)
        'Ping internet'                     = @((Format-AllowedRange -Warning $limits.Network.PingWarningMs -Unit 'ms'), $limits.Network.TypicalInternetPing)
        'Application crashes'               = @((Format-AllowedRange -Warning $limits.Software.CrashWarningAbove), $limits.Software.TypicalCrashes)
        'Blue screens'                      = @((Format-AllowedRange -Warning $limits.EventLog.BlueScreenWarningAbove), $limits.EventLog.TypicalBlueScreens)
        'Defender last scan'                = @((Format-AllowedRange -Warning $limits.Defender.ScanWarningDays -Unit 'days'), $limits.Defender.TypicalScan)
        'Stability index'                   = @((Format-AllowedRange -Warning $limits.Stability.WarningIndex -Critical $limits.Stability.CriticalIndex -LowerIsWorse -Maximum 10), $limits.Stability.Typical)
        'Temporary files'                   = @((Format-AllowedRange -Warning $limits.Cleanup.TempWarningGb -Unit 'GB'), '')
        'Recycle Bin'                       = @((Format-AllowedRange -Warning $limits.Cleanup.RecycleBinWarningGb -Unit 'GB'), '')
        'Page file'                         = @((Format-AllowedRange -Warning $limits.PageFile.WarningPercent -Unit '%'), $limits.PageFile.Typical)
        'Clock accuracy'                    = @((Format-AllowedRange -Warning $limits.Network.ClockWarningSeconds -Unit 'seconds'), $limits.Network.TypicalClock)
        'Disk errors'                       = @((Format-AllowedRange -Warning $limits.EventLog.DiskErrorWarningAbove), '0')
        'Hardware errors'                   = @((Format-AllowedRange -Warning $limits.EventLog.HardwareErrorWarningAbove), '0')
    }

    # Items behind the "Show N more" section, by check name.
    $details = @{
        'Startup programs'   = @('Screenshot Tool', 'SecurityHealth', 'Teams', 'Touchpad Driver')
        'Installed programs' = @('Teams 25.1', 'Touchpad Driver 19.5', 'Video Player 3.0', 'Web Meeting Client 6.2')
        'Largest folders (C:)' = @('ProgramData 5.1 GB', 'Users\m.horvat\Documents 4.4 GB', 'pagefile.sys 4.7 GB', 'Users\m.horvat\Desktop 3.9 GB', 'Program Files (x86) 3.2 GB', 'Users\m.horvat\Pictures 2.6 GB')
        'Browser extensions' = @('Chrome: Ad Blocker 1.60.0', 'Chrome: Password Manager 3.2.1', 'Edge: Ad Blocker 1.60.0', 'Edge: Contoso Web Meeting 6.2', 'Edge: PDF Tools 2.0', 'Edge: Shopping Helper 4.1.3')
        'Audio devices'      = @('Web Meeting Virtual Speaker (virtual)')
    }

    $results = @(
        foreach ($row in $rows) {
            $reference = if ($references.ContainsKey($row[1])) { $references[$row[1]] } else { @('', '') }
            $items = @()
            if ($details.ContainsKey($row[1])) {
                $items = $details[$row[1]]
            }

            # Services are described by their service name, the part in parentheses.
            $description = if ($row[0] -eq 'Services' -and $row[1] -match '\((\w+)\)$') {
                Get-CheckDescription -Key ('Service:{0}' -f $Matches[1])
            }
            else {
                ''
            }

            New-CheckResult -Category $row[0] -Check $row[1] -Status $row[2] -Value $row[3] -Recommendation $row[4] `
                -Allowed $reference[0] -Typical $reference[1] -Details $items -Description $description
        }
    )

    $summary = Get-HealthSummary -Result $results
    $report = [PSCustomObject]@{
        ToolVersion     = Get-ToolVersion
        ComputerName    = 'FIN-LT-014'
        GeneratedAt     = '2026-09-30 09:14:52'
        DurationSeconds = 18.6
        IsElevated      = $false
        EventLogDays    = 7
        Score           = Get-HealthScore -Summary $summary
        Summary         = $summary
        Results         = $results
    }

    Export-HealthReportHtml -Report $report -Path (Join-Path -Path $Folder -ChildPath 'sample-report.html')
    Export-HealthReportJson -Report $report -Path (Join-Path -Path $Folder -ChildPath 'sample-report.json')
} $folder
