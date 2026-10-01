@{
    # A short explanation of every check: what the thing is and what it does for the
    # computer. The text is shown under the check name in the report.
    #
    # The key is the check name. Checks whose name contains a changing part use the
    # text before the colon or parenthesis: "Disk (C:)" -> "Disk", "Adapter: ..." ->
    # "Adapter". Services are stored as "Service:<service name>".

    # System
    'Computer name'                     = 'The name that identifies this computer on the network. Helpdesk uses it to find the right machine in the inventory and in remote support tools.'
    'Operating system'                  = 'The Windows edition, feature release and build. It decides which features and security updates the computer can receive.'
    'Windows installed'                 = 'The date this Windows installation was set up. An old installation tends to collect leftover software and settings.'
    'Manufacturer and model'            = 'Who made the computer and which model it is. Needed to find drivers, spare parts and warranty information.'
    'Domain or workgroup'               = 'Whether the computer is managed centrally in a company domain or stands alone in a workgroup. It decides where user accounts and policies come from.'
    'Signed-in user'                    = 'The account that is using the computer right now. Problems are often tied to one user profile rather than to the whole machine.'
    'Uptime'                            = 'The time since Windows was last started. A restart clears the memory, finishes updates and resets drivers, so a long uptime is a common cause of slowness.'
    'Windows activation'                = 'Activation confirms that this copy of Windows has a valid license. Without it Windows shows reminders and locks the personalization settings.'
    'Startup programs'                  = 'Programs that start automatically when the user signs in. Each one makes sign-in slower and keeps using memory in the background.'

    # Specifications
    'Processor'                         = 'The processor (CPU) executes every program. More cores and a higher clock speed let the computer do more work at the same time.'
    'Memory'                            = 'RAM is the short-term working memory of running programs. The module layout and the free slots show whether more memory can be added.'
    'Graphics'                          = 'The graphics adapter draws everything shown on the screen. The driver version matters when the picture flickers or video and games misbehave.'
    'Motherboard'                       = 'The main board that all other components plug into. Its model decides which processors, memory and expansion cards are supported.'
    'BIOS'                              = 'The firmware that starts the hardware before Windows loads. An outdated version can cause compatibility and stability problems.'
    'Serial number'                     = 'The unique number the manufacturer gave this computer. It is used for warranty claims and asset tracking.'

    # Hardware
    'CPU load'                          = 'How busy the processor was while the check ran. Constantly high load makes the whole computer slow and the fans loud.'
    'Memory usage'                      = 'How much of the installed RAM is in use. When it is nearly full, Windows moves data to the much slower disk and everything starts to lag.'
    'Top memory consumers'              = 'The programs that hold the most RAM right now. This is the first place to look when memory usage is high.'
    'Drive'                             = 'A physical SSD or hard disk and the health state it reports about itself. A drive that reports problems can fail and take the data with it.'
    'Disk'                              = 'A drive letter (partition) and its free space. Windows needs free space for updates, temporary files and virtual memory.'
    'Battery'                           = 'The charge of the laptop battery and whether the charger is connected.'

    # Event Log
    'Unexpected shutdowns'              = 'How often the computer went off without a proper shutdown (power loss, crash, forced power-off). It risks data loss and points to power or stability problems.'
    'System log - critical events'      = 'The most severe events recorded by Windows itself and its drivers, such as crashes and sudden power loss.'
    'System log - errors'               = 'Errors recorded by Windows components, drivers and services. A few are normal; many from one source point to a recurring problem.'
    'System log - top sources'          = 'The components that logged the most errors. They show where to start looking in Event Viewer.'
    'Application log - critical events' = 'The most severe events recorded by installed programs.'
    'Application log - errors'          = 'Errors recorded by installed programs, for example crashes and hangs.'
    'Application log - top sources'     = 'The programs that logged the most errors. They show which application is causing trouble.'

    # Windows Update
    'Last installed update'             = 'The most recent Windows update on this computer. Updates close security holes, so a long gap leaves the computer exposed.'
    'Pending restart'                   = 'Whether Windows is waiting for a restart to finish installing updates. Until then the updates are not fully applied.'

    # Security
    'Microsoft Defender'                = 'The antivirus built into Windows.'
    'Defender real-time protection'     = 'The part of Microsoft Defender Antivirus that scans files and programs the moment they are opened. Without it malware is not stopped in time.'
    'Defender definitions'              = 'The list of known threats the antivirus uses to recognize malware. It has to be updated often to catch new threats.'
    'Firewall'                          = 'Windows Defender Firewall blocks unwanted incoming network connections.'
    'Firewall - Domain profile'         = 'The firewall rules used while the computer is connected to the company domain network. The firewall blocks unwanted incoming connections.'
    'Firewall - Private profile'        = 'The firewall rules used on networks marked as private, such as a home or small office network.'
    'Firewall - Public profile'         = 'The firewall rules used on public networks such as cafes and airports, where the protection matters most.'
    'Secure Boot'                       = 'A UEFI feature that lets only trusted, signed software start the computer. It protects against malware that loads before Windows.'
    'TPM'                               = 'A security chip that stores encryption keys safely. BitLocker and Windows Hello rely on it, and Windows 11 requires version 2.0.'
    'BitLocker'                         = 'Full-disk encryption built into Windows. If the computer is lost or stolen, the data on the drive cannot be read without the key.'

    # Network
    'Network adapters'                  = 'The network cards of the computer. Without an active adapter there is no network connection.'
    'Adapter'                           = 'A network card (cable or Wi-Fi) and its settings: the IP address identifies the computer, the gateway is the router, DNS servers translate names and DHCP hands all of this out automatically.'
    'Proxy'                             = 'A server that web traffic can be routed through. A wrong or leftover proxy setting stops browsers from reaching the internet.'
    'Connectivity tests'                = 'Ping, DNS and HTTPS tests that show how far the network connection reaches.'
    'Ping default gateway'              = 'A test message sent to the router. A reply means the connection between the computer and the local network works.'
    'Ping internet'                     = 'A test message sent to a public server. A reply means traffic gets past the router and out to the internet.'
    'DNS resolution'                    = 'DNS translates names such as microsoft.com into IP addresses. If it fails, web sites do not open even though the connection itself works.'
    'HTTPS access'                      = 'A real web request over an encrypted connection. It confirms that the computer can actually reach web sites.'

    # Services
    'Service:Dhcp'                      = 'DHCP Client asks the router for an IP address and network settings. If it is stopped, the computer cannot join a network automatically.'
    'Service:Dnscache'                  = 'DNS Client translates names into IP addresses and remembers the answers. Without it web sites and network shares cannot be found by name.'
    'Service:EventLog'                  = 'Windows Event Log records what happens on the system. Many other services and all troubleshooting tools depend on it.'
    'Service:LanmanWorkstation'         = 'Workstation lets the computer connect to shared folders and printers on other computers.'
    'Service:mpssvc'                    = 'Windows Defender Firewall filters network traffic and blocks unwanted incoming connections.'
    'Service:WinDefend'                 = 'Microsoft Defender Antivirus Service protects the computer from malware. It is stopped when another antivirus is installed.'
    'Service:wuauserv'                  = 'Windows Update finds, downloads and installs updates. It only runs when needed, so finding it stopped is normal.'
    'Service:BITS'                      = 'Background Intelligent Transfer Service downloads updates in the background using idle bandwidth. It only runs when needed.'
    'Service:Spooler'                   = 'Print Spooler manages print jobs and sends them to the printers. If it is stopped, nothing can be printed.'
}
