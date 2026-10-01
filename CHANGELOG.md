# Changelog

All notable changes to this project are written down here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

The first public version. It will be released as 1.0.0.

### Checks

- Ten categories of read-only checks: System, Specifications, Hardware, Software,
  Event Log, Windows Update, Security, Network, Printers and Services.
- Every result has a status (OK, Warning, Critical or Info), an explanation of what
  was checked and, for Warning and Critical, a recommended fix. Measurements show the
  allowed range and a typical value.
- Works without administrator rights; the checks that need them are marked
  "Requires admin" and are included after "Restart as administrator".
- Disk space: the largest folders of a disk that is running full, the hibernation
  file, temporary files, Downloads and the Recycle Bin.
- Drivers and hardware: devices without a working driver, unsigned and old drivers,
  battery health, health of the drives and, with administrator rights, their
  temperature and wear.
- Updates: the last installed update, pending and failed updates, pending restart.
- Security: Microsoft Defender, firewall, User Account Control, accounts, shared
  folders, ports open to the network, backup (File History, OneDrive, System Restore),
  Secure Boot, TPM and BitLocker.
- Network: adapters, Wi-Fi signal and security, proxy, hosts file, connectivity tests.
- What starts with the computer besides Windows itself: startup programs, scheduled
  tasks, services and browser extensions.

### The window

- Overview with the problems and their fixes, a health score from 0 to 100 and the
  changes since the previous check of the same computer.
- A button next to a fix opens the page of Windows where the fix is made.
- One page per category, search over all results and a filter by status.
- "Copy summary" for tickets, export as HTML, PDF, CSV or JSON.
- Settings: English or Croatian, light or dark theme, remembered window size.
- Keyboard shortcuts for the common actions.

### Live monitor

- Load of the processor (in total and per logical processor), memory, graphics, disks
  and network, with history graphs.
- Sensors: NVIDIA graphics cards, thermal zones, battery and, with administrator
  rights, the drives.
- The programs that use the most processor time, memory and data, with details on click.
- Pause, selectable refresh rate, recording to a CSV file and alerts for values that
  stay high.

### Command line and automation

- `Invoke-PCHealthCheck` runs everything and saves the report; one command per
  category for scripts; `Get-PCHealthReport` returns everything as one object.
- `Compare-PCHealthReport` compares two reports.
- `Get-PerformanceSnapshot` returns the data of the Live monitor.
- `Invoke-HealthCheck.ps1` reports the result as an exit code for monitoring systems
  and scheduled tasks.
- `-ComputerName` checks another computer through PowerShell remoting (experimental).

### Distribution

- Installer for the current user (no administrator rights), portable ZIP, or use as a
  PowerShell module.
- Runs on Windows PowerShell 5.1 and PowerShell 7.
