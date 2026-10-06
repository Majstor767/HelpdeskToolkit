# Changelog

All notable changes to this project are written down here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

The first public version. It will be released as 1.0.0.

### Checks

- Ten categories of read-only checks: System, Specifications, Hardware, Software,
  Event Log, Windows Update, Security, Network, Printers and Services.
- Every result has a status (OK, Warning, Critical or Info) and an explanation of what
  was checked. Warning and Critical results also say why they are a problem (what
  they lead to when left alone) and have a recommended fix. Measurements show the
  allowed range and a typical value.
- Works without administrator rights; the checks that need them are marked
  "Requires admin" and are included after "Restart as administrator".
- Disk space: the largest folders of a disk that is running full, the hibernation
  file, temporary files, Downloads and the Recycle Bin.
- The drive Windows is installed on is recognized and marked. Why a full drive is a
  problem, and what to do about it, is said differently for that drive and for a
  drive that only holds data or programs.
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
- Taken over after a comparison with other health tools (PC Health Check, Windows
  Security, the support tools of the computer makers, CCleaner, Belarc Advisor):
  - Security: SmartScreen, memory integrity, LSA protection, SMB 1.0, whether the
    screen locks by itself, which programs used the camera, the microphone and the
    location, and the USB storage devices that have been connected.
  - System: Windows 11 readiness on Windows 10 with every requirement, the last
    System File Checker result, and what Windows blamed for a slow startup.
  - Hardware: the result of the last memory test.
  - Software: programs that no longer get security updates, programs for which
    winget knows a newer version, Microsoft Office with its update channel, the
    size of the Outlook mailbox files, and programs that are still listed as
    installed although their uninstaller is gone.
  - Specifications: advice for an old BIOS, and where the warranty is looked up.
- `Get-ChangeTimeline`: the installations, updates, crashes and failures of the last
  weeks on one time line, from what Windows records for Reliability Monitor.

### Memory and reliability

- The Overview draws the health score of the last checks as a line.
- Every check runs in a short-lived process of its own, so its memory goes back to
  Windows when it is done. The open window stays at about 200 to 250 MB instead of
  growing to 500 MB and more; hidden next to the clock it uses 15 to 35 MB.
- The automatic check is repeated less often while the window is hidden (every 30
  minutes at most) or the computer runs on battery (15, and 60 when both apply).
- An unexpected error no longer ends the application without a trace: it is written
  to `app.log` in the folder of the application and the window stays open.
- A check that does not finish is stopped after ten minutes and the window says so,
  instead of showing "Checking ..." for ever. Errors in the menu of the icon next to
  the clock are written to the log like those of the window.
- A check keeps working when Windows does not answer: tests let every source of
  data fail, alone and all at once, and no category is lost. A category that fails
  in the middle keeps what it had found.
- In Croatian the result cards are built fifteen times faster, and the table of
  translated texts no longer grows without end.
- Privacy, notices and security policy: `PRIVACY.md` lists every network connection
  the program makes, `NOTICE.md` the license, the trademarks and what the tool is
  not, `SECURITY.md` how to report a vulnerability.

### The window

- At the start the window asks whether to run with administrator rights and then
  starts the check by itself; the answer can be remembered.
- Overview with the problems and their fixes, a health score from 0 to 100 and the
  changes since the previous check of the same computer.
- A button next to a fix opens the page of Windows where the fix is made.
- Below the fix of every problem, a link to the page of Microsoft that explains it,
  or a web search for its name. The results of the event log list every kind of
  event with its event number under "Show more"; a click looks that event up.
- A link for the exact error: the article of Microsoft about an update that failed,
  and a search for the error code of Windows Update, for the stop code of a blue
  screen (now listed with how often it happened) and for the code Device Manager
  gives a device. Services and the profiles of the firewall get the page that
  explains them, as do fifteen more checks that only had a web search.
- Links open also when Windows cannot open them: when the default browser was removed
  and Windows still names it ("Application not found"), another browser is used; from a
  window with administrator rights the page is opened by the desktop of the user, so
  the browser does not run as administrator. A default browser that is gone is
  reported as a warning under Software.
- A click on a program in "What takes up the space" starts the program's own
  uninstaller, after a question; a program without one opens Installed apps.
- A side bar in the manner of Windows 11: an icon for every page, the check categories
  under a heading of their own, a bar that marks the open page, the number of problems
  per category, and the report actions, the rights and the settings below.
- One page per category: the problems first, each across the whole width with its
  fix next to it, then everything else as tiles that open on a click. Chips at the
  top count the results per status and filter the page. Search over all results and
  a filter by status. In every list, and in the report, the most severe results come
  first.
- A Timeline page with the changes and failures of the last weeks, grouped by day,
  to find the change that came just before the first failure.
- Below the score: which category cost how many points.
- For the result "Warranty and support", a button that opens the support page of the
  maker and copies the serial number.
- "Copy summary" for tickets, export as HTML, PDF, CSV or JSON.
- After the first check the application repeats it in the background and replaces the
  results without interrupting. A problem that is new is announced at the top of the
  window and with a Windows notification; a click leads to the result.
- Optional: closing the window leaves the application running as an icon next to
  the clock (open, run the check, exit from its menu), and it can start with Windows
  that way, through a shortcut in the Startup folder of the user. Only one copy runs
  at a time; a second start brings the window of the first one back. "Run in
  background" in the side bar sends the window there at once.
- A switch in the header (Ctrl+T) turns the light theme into the dark one and back,
  at once and without a restart.
- Settings: English or Croatian, light or dark theme, the interval of the automatic
  check, remembered window size.
- The taskbar shows the icon of the application, not that of PowerShell, which the
  window runs in.
- Keyboard shortcuts for the common actions. Print Screen copies a picture of the
  window, which also works while the window runs with administrator rights and the
  shortcut of a screenshot tool does not.

### Live monitor

- Load of the processor (in total and per logical processor), memory, graphics, disks
  and network, with history graphs.
- How quickly the router and the internet answer, with an Internet tile that shows
  the answer time, its average and the lost answers.
- Sensors: NVIDIA graphics cards, thermal zones, battery and, with administrator
  rights, the drives.
- The programs that use the most processor time, memory and data, with details on click.
- Pause, selectable refresh rate, recording to a CSV file and alerts for values that
  stay high.
- A status dot on the tiles of processor, memory and graphics: green, orange when the
  value approaches its limit or keeps rising, red above the limit, with advice on how
  to bring it down.
- A click on the processor, memory or graphics tile opens a page with everything that
  can be read about that component, down to every property Windows reports.
- What takes up the space of a drive: its largest installed programs and folders. A
  click on a program opens the page of Windows where it is uninstalled.

### Speed

- The check categories run side by side, so a check takes 10 to 20 seconds instead
  of half a minute. `Get-PCHealthReport -ThrottleLimit 1` runs them one after the
  other.
- Folder sizes are measured by several threads and, where the time allows, to their
  end, instead of stopping at a lower bound after a few seconds.
- The repeated checks of the window reuse the folder sizes for half an hour and take
  only a few seconds.
- The module loads in a third of the time: its files are loaded as one block.
- A measurement of the Live monitor takes about half a second instead of two.
- The window shows the results of the last check at the start, until the new check
  has finished, and remembers "Skip network tests" and the number of days.

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
- Setup and the uninstaller stop with a message while the application is open,
  instead of replacing files under it.
- Runs on Windows PowerShell 5.1 and PowerShell 7.
