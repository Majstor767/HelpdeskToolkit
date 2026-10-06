@{
    # Where a problem is explained. The window shows a link below the recommended fix
    # of every Warning and Critical result; a click opens the address in the browser.
    #
    # Pages: the page of the maker that explains the problem and how it is fixed. The
    # key is the name of the check, the part of the name before the first colon or
    # parenthesis ("Disk" for "Disk (C:)"), the part before " - " ("Firewall" for
    # "Firewall - Public profile"), "Service:<name>" for a service, or
    # "Category:<name>" for every check of a category that has no entry of its own. The addresses carry no language: Microsoft
    # shows the page in the language of the browser. They were checked when they were
    # added; "tools\Test-HelpLink.ps1" asks every one of them again.
    #
    # An entry with Windows10 and Windows11 instead of an address depends on the
    # Windows version of this computer.
    #
    # SearchUrl: for a problem without a page, and for a single event of the event log,
    # the link is a web search. {0} is replaced with the search words: the name of the
    # check, or the source and the number of the event. The value of a result (names of
    # programs, users, drives) never becomes part of an address.

    SearchUrl  = 'https://www.bing.com/search?q={0}'

    # ArticleUrl: the article of Microsoft about an update. {0} is replaced with the
    # number of the update, without "KB".
    ArticleUrl = 'https://support.microsoft.com/help/{0}'

    Pages      = @{
        # --- System -----------------------------------------------------------------
        'Windows support'               = @{
            Windows10 = 'https://support.microsoft.com/windows/deployment/updates-lifecycle/windows-10-support-has-ended-on-october-14-2025'
            Windows11 = 'https://learn.microsoft.com/windows/release-health/windows11-release-information'
        }
        'Windows activation'            = 'https://support.microsoft.com/windows/activation/activate-windows'
        'Startup programs'              = 'https://support.microsoft.com/windows/configure-startup-applications-in-windows-115a420a-0bff-4a6f-90e0-1934c844e473'
        'Last startup duration'         = 'https://support.microsoft.com/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows'
        'Startup delays'                = 'https://support.microsoft.com/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows'
        'Uptime'                        = 'https://support.microsoft.com/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows'
        'System file check'             = 'https://support.microsoft.com/topic/use-the-system-file-checker-tool-to-repair-missing-or-corrupted-system-files-79aa86cb-ca52-166a-92a3-966e85d4094e'
        'Stability index'               = 'https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2008-r2-and-2008/cc722107(v=ws.10)'

        # --- Hardware ---------------------------------------------------------------
        'Disk'                          = 'https://support.microsoft.com/windows/experience/storage-filemanagement/free-up-drive-space-in-windows'
        'Temporary files'               = 'https://support.microsoft.com/windows/experience/storage-filemanagement/free-up-drive-space-in-windows'
        'System temporary files'        = 'https://support.microsoft.com/windows/experience/storage-filemanagement/free-up-drive-space-in-windows'
        'Recycle Bin'                   = 'https://support.microsoft.com/windows/experience/storage-filemanagement/free-up-drive-space-in-windows'
        'CPU load'                      = 'https://support.microsoft.com/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows'
        'Memory usage'                  = 'https://support.microsoft.com/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows'
        'Page file'                     = 'https://support.microsoft.com/windows/experience/performance-optimization/tips-to-improve-pc-performance-in-windows'
        'Devices with problems'         = 'https://support.microsoft.com/windows/hardware/drivers/error-codes-in-device-manager-in-windows'
        'Unsigned drivers'              = 'https://support.microsoft.com/windows/update-drivers-through-device-manager-in-windows-ec62f46c-ff14-c91d-eead-d7126dc1f7b6'
        'Battery'                       = 'https://support.microsoft.com/windows/caring-for-your-battery-in-windows-2db3e37f-5e7d-488e-9086-ed15320519e4'
        'Battery health'                = 'https://support.microsoft.com/windows/caring-for-your-battery-in-windows-2db3e37f-5e7d-488e-9086-ed15320519e4'
        'Drive'                         = 'https://support.microsoft.com/topic/what-to-do-about-a-critical-warning-for-a-storage-device-258e0042-e091-277d-5fa6-3c710fba70d7'
        'Drive details'                 = 'https://support.microsoft.com/topic/what-to-do-about-a-critical-warning-for-a-storage-device-258e0042-e091-277d-5fa6-3c710fba70d7'
        'File system'                   = 'https://learn.microsoft.com/windows-server/administration/windows-commands/chkdsk'
        'Memory test'                   = 'https://learn.microsoft.com/previous-versions/technet-magazine/ff700221(v=msdn.10)'

        # --- Software ---------------------------------------------------------------
        'Outlook data files'            = 'https://support.microsoft.com/outlook/reduce-the-size-of-your-mailbox-and-outlook-data-files-pst-and-ost'
        'Application crashes'           = 'https://support.microsoft.com/windows/repair-apps-and-programs-in-windows-e90eefe4-d0a2-7c1b-dd59-949a9030f317'
        'Default browser'               = 'https://support.microsoft.com/windows/change-your-default-browser-in-windows-020c58c6-7d77-797a-b74e-8f07946c5db6'
        'Microsoft Office'              = 'https://support.microsoft.com/office/install-office-updates-2ab296f3-7f03-43a2-8e50-46de917611c5'
        'Program updates'               = 'https://learn.microsoft.com/windows/package-manager/winget/upgrade'
        'Unsupported programs'          = 'https://learn.microsoft.com/lifecycle/products/'

        # --- Event Log --------------------------------------------------------------
        'Blue screens'                  = 'https://support.microsoft.com/windows/resolving-blue-screen-errors-in-windows-60b01860-58f2-be66-7516-5c45a66ae3c6'
        'Unexpected shutdowns'          = 'https://support.microsoft.com/windows/resolving-blue-screen-errors-in-windows-60b01860-58f2-be66-7516-5c45a66ae3c6'
        'Disk errors'                   = 'https://learn.microsoft.com/windows-server/administration/windows-commands/chkdsk'
        'Hardware errors'               = 'https://learn.microsoft.com/troubleshoot/windows-client/performance/stop-code-error-troubleshooting'

        # --- Windows Update ---------------------------------------------------------
        'Category:Windows Update'       = 'https://support.microsoft.com/windows/troubleshoot-problems-updating-windows-188c2b0f-10a7-d72f-65b8-32d177eb136c'
        'Service:wuauserv'              = 'https://support.microsoft.com/windows/troubleshoot-problems-updating-windows-188c2b0f-10a7-d72f-65b8-32d177eb136c'
        'Service:BITS'                  = 'https://support.microsoft.com/windows/troubleshoot-problems-updating-windows-188c2b0f-10a7-d72f-65b8-32d177eb136c'

        # --- Security ---------------------------------------------------------------
        'Defender real-time protection' = 'https://support.microsoft.com/windows/security/threat-malware-protection/virus-and-threat-protection-in-the-windows-security-app'
        'Defender definitions'          = 'https://support.microsoft.com/windows/security/threat-malware-protection/virus-and-threat-protection-in-the-windows-security-app'
        'Defender last scan'            = 'https://support.microsoft.com/windows/security/threat-malware-protection/virus-and-threat-protection-in-the-windows-security-app'
        'Threat history'                = 'https://support.microsoft.com/windows/security/threat-malware-protection/virus-and-threat-protection-in-the-windows-security-app'
        'Service:WinDefend'             = 'https://support.microsoft.com/windows/security/threat-malware-protection/virus-and-threat-protection-in-the-windows-security-app'
        'Tamper protection'             = 'https://support.microsoft.com/windows/security/threat-malware-protection/virus-and-threat-protection-in-the-windows-security-app'
        'Firewall'                      = 'https://support.microsoft.com/windows/security/windows-security/firewall-and-network-protection-in-the-windows-security-app'
        'Service:mpssvc'                = 'https://support.microsoft.com/windows/security/windows-security/firewall-and-network-protection-in-the-windows-security-app'
        'Listening ports'               = 'https://support.microsoft.com/windows/security/firewall/risks-of-allowing-apps-through-windows-firewall'
        'User Account Control'          = 'https://support.microsoft.com/windows/security/user-account-control-settings'
        'SmartScreen'                   = 'https://support.microsoft.com/windows/security/windows-security/app-browser-control-in-the-windows-security-app'
        'BitLocker'                     = 'https://support.microsoft.com/windows/security/encryption/bitlocker-overview'
        'TPM'                           = 'https://support.microsoft.com/windows/security/devicesecurity/enable-tpm-2-0-on-your-pc'
        'Secure Boot'                   = 'https://support.microsoft.com/windows/security/windows-security/device-security-in-the-windows-security-app'
        'Memory integrity'              = 'https://support.microsoft.com/windows/security/windows-security/device-security-in-the-windows-security-app'
        'Failed sign-ins'               = 'https://learn.microsoft.com/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4625'
        'Account lockouts'              = 'https://learn.microsoft.com/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-4740'
        'Automatic sign-in'             = 'https://learn.microsoft.com/troubleshoot/windows-server/user-profiles-and-logon/turn-on-automatic-logon'
        'Guest account'                 = 'https://learn.microsoft.com/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/accounts-guest-account-status'
        'SMB 1.0'                       = 'https://learn.microsoft.com/windows-server/storage/file-server/troubleshoot/detect-enable-and-disable-smbv1-v2-v3'

        # --- Network ----------------------------------------------------------------
        'Wi-Fi'                         = 'https://support.microsoft.com/windows/fix-wi-fi-connection-issues-in-windows-9424a1f7-6a3b-65a6-4d78-7f07eee84d2c'
        'Category:Network'              = 'https://support.microsoft.com/windows/experience/connectivity-networking/fix-ethernet-connection-problems-in-windows'
        'Service:Dhcp'                  = 'https://support.microsoft.com/windows/experience/connectivity-networking/fix-ethernet-connection-problems-in-windows'
        'Service:Dnscache'              = 'https://support.microsoft.com/windows/experience/connectivity-networking/fix-ethernet-connection-problems-in-windows'

        # --- Printers ---------------------------------------------------------------
        'Category:Printers'             = 'https://support.microsoft.com/windows/hardware/printer/fix-printer-connection-and-printing-problems-in-windows'
        'Service:Spooler'               = 'https://support.microsoft.com/windows/hardware/printer/fix-print-spooler-service-not-running-errors-in-windows'
    }
}
