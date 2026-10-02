@{
    # Why a problem matters: what it leads to when it is left as it is. The window and
    # the HTML report show the text next to every result with the status Warning or
    # Critical, between the explanation of the check and the recommended fix.
    #
    # The key is looked up like the descriptions (see Get-CheckRisk): the name of the
    # check, the part of the name before the first colon or parenthesis ("Disk" for
    # "Disk (C:)"), the part before " - " ("Firewall" for "Firewall - Public profile"),
    # "Service:<name>" for a Windows service, and at last "Category:<name>" for every
    # check of a category that has no entry of its own.

    # --- System ---------------------------------------------------------------------
    'Uptime'                            = 'Windows that runs for many days without a restart gets slower: the memory fills up with leftovers, updates stay half installed and small faults pile up. In the end programs hang, and security updates that wait for the restart are not active.'
    'Windows support'                   = 'A Windows version without support gets no more security updates. Every weakness found from then on stays open for good, and newer programs and devices gradually stop working with it.'
    'Stability index'                   = 'A low index means that crashes and failed installations keep happening. Left alone they tend to become more frequent, and every crash can cost unsaved work or damage a file.'
    'Windows activation'                = 'Windows that is not activated shows reminders and locks the personalization settings. In a company it can also mean an installation without a license, which is a problem at an audit.'
    'Startup programs'                  = 'Every program that starts with Windows makes signing in slower and keeps using memory and processor time all day. The more of them there are, the slower the whole computer feels.'
    'Last startup duration'             = 'A slow start costs time every day. It usually comes from too many startup programs or from a disk that struggles, and a disk problem gets worse with time.'
    'Startup delays'                    = 'What holds up the startup today will do so at every start, and a driver or device that answers slowly is often one that is about to fail.'
    'System file check'                 = 'Damaged files of Windows cause errors that are hard to explain: features that do not open, updates that fail, crashes. The damage does not repair itself and tends to spread with every failed update.'
    'Category:System'                   = 'A problem with Windows itself affects everything that runs on it. Left alone it shows up as a slower computer, as programs that fail, or as protection that is no longer complete.'

    # --- Hardware -------------------------------------------------------------------
    'CPU load'                          = 'A processor that stays close to its limit makes everything slow and jerky, keeps the fans loud and heats the computer up. Constant heat shortens the life of the hardware.'
    'Memory usage'                      = 'When the memory is full, Windows moves data to the much slower disk. Programs freeze for seconds, and in the end Windows closes them without warning, with the unsaved work lost.'
    'Page file'                         = 'A page file that is almost full means Windows is running out of room for the memory it has promised to programs. Programs then stop with "out of memory" or close by themselves.'
    'Disk'                              = 'A full disk stops Windows updates from installing, makes programs fail when they save, and slows the computer down. With no space left at all, Windows may not start properly and files can be damaged.'
    'Drive'                             = 'A drive that reports problems can fail completely at any time. Everything stored on it is then gone, unless there is a backup.'
    'Drive details'                     = 'A drive that runs too hot or is worn out is close to failing. A failed drive takes all its data with it, usually without another warning.'
    'File system'                       = 'Errors in the file system grow: files become unreadable, programs crash when they touch them, and in the worst case Windows no longer starts.'
    'Temporary files'                   = 'These files only take up space. On a disk that is getting full they take away the room Windows needs for updates and for its own work.'
    'System temporary files'            = 'These files only take up space. On a disk that is getting full they take away the room Windows needs for updates and for its own work.'
    'Recycle Bin'                       = 'Deleted files stay on the disk until the Recycle Bin is emptied. On a disk that is getting full they take away the room Windows needs for updates and for its own work.'
    'Devices with problems'             = 'A device without a working driver does not work, or works badly: no sound, no network, no camera. A faulty driver can also make Windows crash.'
    'Unsigned drivers'                  = 'A driver without a valid signature cannot be traced to its maker and may have been changed. Drivers run with full rights, so a bad one can crash Windows or be used to take over the computer.'
    'Battery'                           = 'A battery this low switches the computer off within minutes. Work that is not saved by then is lost.'
    'Battery health'                    = 'A worn battery holds less and less charge: the computer runs for a shorter time and can switch off suddenly although the display still shows some charge. A badly worn battery can swell and damage the case.'
    'Memory test'                       = 'Faulty memory corrupts whatever happens to be stored in it: programs crash at random, files are saved damaged, and Windows itself can be destroyed by an update written through bad memory.'
    'Category:Hardware'                 = 'A hardware problem rarely goes away by itself. Left alone it leads to a slower computer, to crashes, or to a part that fails and takes data with it.'

    # --- Software -------------------------------------------------------------------
    'Application crashes'               = 'Every crash can lose unsaved work and damage the file that was open. Crashes that keep coming back point to a faulty program, add-in or driver, and they rarely stop by themselves.'
    'Unsupported programs'              = 'A program without support keeps every security hole that is found from now on. Attackers study the fixes of the newer versions to learn where the old ones are weak, and a prepared document or web page is then enough to take over the computer.'
    'Program updates'                   = 'Old versions keep security holes that are already fixed, and publicly described, in the new ones. The longer a program stays behind, the more of them pile up.'
    'Microsoft Office'                  = 'Office opens documents from e-mail and the internet every day. Without updates, a prepared Word or Excel file can use a weakness that was fixed long ago.'
    'Outlook data files'                = 'A mailbox file that keeps growing makes Outlook slower and slower, with pauses while typing and searching. At its size limit Outlook stores no new mail, and a very large file is more easily damaged, which can cost the whole mailbox.'
    'Category:Software'                 = 'A program that does not work properly costs time and can damage the files it works with. The cause usually stays until the program is updated, repaired or removed.'

    # --- Event Log ------------------------------------------------------------------
    'Unexpected shutdowns'              = 'When the computer goes off without a proper shutdown, files that were being written can be damaged, including those of Windows itself. Repeated, it can end with a Windows that no longer starts.'
    'Blue screens'                      = 'A blue screen is Windows stopping itself to prevent damage. Whatever was open is lost, and blue screens that repeat point to a faulty driver or to failing hardware, which gets worse.'
    'Disk errors'                       = 'Disk errors in the log are often the first sign of a failing drive. Ignored, they lead to unreadable files and finally to a drive that no longer works.'
    'Hardware errors'                   = 'The hardware itself reports faults of the processor, the memory or the motherboard. They cause crashes and can silently corrupt data, and they usually become more frequent.'
    'System log - critical events'      = 'Critical events are serious failures of Windows. As long as their cause is there, crashes and lost work will repeat.'
    'Application log - critical events' = 'Critical events are serious failures of a program. As long as their cause is there, crashes and lost work will repeat.'
    'System log - errors'               = 'Many errors mean that something keeps failing in the background: a service or a driver. That costs performance and often shows up later as a fault the user can see.'
    'Application log - errors'          = 'Many errors mean that a program keeps failing in the background. That costs performance and often shows up later as a fault the user can see.'
    'Category:Event Log'                = 'Windows writes down what goes wrong. A log that keeps filling with the same failure means its cause is still there and will sooner or later become a fault the user can see.'

    # --- Windows Update -------------------------------------------------------------
    'Last installed update'             = 'Without recent updates the computer misses security fixes that are already public, so known weaknesses stay open to attackers. The longer it lasts, the more updates pile up and the more likely they are to fail.'
    'Pending restart'                   = 'Updates that wait for a restart are not active yet: the weaknesses they fix are still open. Windows may also restart by itself at a bad moment.'
    'Updates paused'                    = 'While updates are paused the computer gets no security fixes at all. Every week adds weaknesses that attackers know already.'
    'Failed updates'                    = 'An update that keeps failing leaves its security fix uninstalled and can block the updates that build on it. Windows tries again and again, which costs time and disk space.'
    'Category:Windows Update'           = 'A computer that does not get its updates keeps weaknesses that are publicly known. Attackers look for exactly those.'

    # --- Security -------------------------------------------------------------------
    'Defender real-time protection'     = 'Without real-time protection nothing checks files while they are opened or downloaded. Malware can then run unnoticed: steal passwords, encrypt the files for ransom or spread to other computers.'
    'Defender definitions'              = 'With old definitions the antivirus does not know the newest malware and lets it pass.'
    'Defender last scan'                = 'Without regular scans, malware that got past the real-time protection can stay on the computer unnoticed for a long time.'
    'Tamper protection'                 = 'Without tamper protection a malicious program can switch the antivirus off before it does its damage.'
    'Threat history'                    = 'A threat that is still active can steal data, damage files or spread to other computers until it is removed.'
    'Firewall'                          = 'With the firewall off, other computers on the same network can reach every program on this one that accepts connections. On a public network that is an open door.'
    'SmartScreen'                       = 'Without SmartScreen nothing warns before a program downloaded from the internet is started for the first time. A fake installer or an attachment made to look like a document then runs without any question.'
    'SMB 1.0'                           = 'SMB 1.0 has weaknesses that let malware spread from one computer to the next without anybody doing anything; whole company networks were encrypted that way. As long as it is enabled, one infected device on the network is enough.'
    'User Account Control'              = 'With User Account Control off, any program can change Windows without asking. Malware has full control the moment it is started.'
    'Automatic sign-in'                 = 'With automatic sign-in, anybody who switches the computer on is signed in, with all files and saved passwords at hand. The password is also stored on the computer in a form that can be read out.'
    'Guest account'                     = 'An enabled Guest account lets anybody use the computer without a password and reach whatever is not locked down.'
    'Listening ports'                   = 'A port of a service that is unencrypted or made for remote control is open to the network. Passwords sent to it can be read on the way, and such services are a common way into a computer.'
    'TPM'                               = 'Without a working TPM, BitLocker and Windows Hello cannot protect their keys properly, and Windows 11 does not officially support the computer.'
    'BitLocker'                         = 'Without encryption, anybody who gets hold of the computer or its drive can read every file on it without knowing a password.'
    'Failed sign-ins'                   = 'Many failed sign-ins can mean that somebody is trying out passwords. When one is guessed, that person has the account; until then the account can get locked and keep its real user out.'
    'Account lockouts'                  = 'A locked account stops its user from working. Lockouts that repeat come from an old password saved somewhere, or from somebody guessing.'
    'Category:Security'                 = 'A gap in the protection of the computer gives malware or an intruder an easier way in. The longer it stays open, the more likely it is to be found.'

    # --- Network --------------------------------------------------------------------
    'Network adapters'                  = 'Without a connected network adapter the computer has no network at all: no internet, no e-mail, no shared files or printers.'
    'Adapter'                           = 'An adapter without a valid address cannot talk to the network. Nothing that needs the network works through it.'
    'Wi-Fi'                             = 'A weak signal makes the connection slow and unreliable: calls break up, downloads stall and cloud files stop synchronizing. On a network without encryption, others nearby can read what is sent.'
    'Ping default gateway'              = 'When the router does not answer, nothing beyond this computer can be reached: no internet and no other device on the network.'
    'Ping internet'                     = 'Without a working connection to the internet, websites, e-mail, cloud files and updates do not work. A slow one makes calls and remote work unreliable.'
    'DNS resolution'                    = 'Without name resolution, websites and servers cannot be found by their names. Almost nothing on the internet works then, although the connection itself is up.'
    'HTTPS access'                      = 'When secure websites cannot be reached, browsing, signing in, updates and cloud services all fail. The cause is often a proxy, a firewall or a wrong clock.'
    'Clock accuracy'                    = 'With a wrong clock, secure websites show certificate errors, signing in to a company network fails and files get wrong dates.'
    'Category:Network'                  = 'A network problem cuts the computer off from what it needs: the internet, e-mail, shared files, printers and updates.'

    # --- Printers -------------------------------------------------------------------
    'Installed printers'                = 'A printer that is offline does not print. Documents sent to it wait in the queue and come out all at once later, or never.'
    'Print queue'                       = 'A document that is stuck blocks everything behind it: nobody can print on that printer until the queue is cleared.'
    'Category:Printers'                 = 'As long as the printer problem stays, documents are not printed and pile up in the queue.'

    # --- Services -------------------------------------------------------------------
    'Service:Dhcp'                      = 'Without this service the computer gets no address from the network, so after the next start it may have no network at all.'
    'Service:Dnscache'                  = 'Without this service the names of websites and servers are not resolved, so almost nothing on the network can be reached.'
    'Service:EventLog'                  = 'Without this service Windows writes down nothing that goes wrong. Faults then cannot be traced, and other services that depend on it do not start.'
    'Service:LanmanWorkstation'         = 'Without this service the computer cannot open shared folders or network printers of other computers.'
    'Service:mpssvc'                    = 'Without this service the firewall of Windows does not work, and other computers on the network can reach programs on this one.'
    'Service:WinDefend'                 = 'Without this service the antivirus does not run. Malware can then be opened and run without anything stopping it.'
    'Service:wuauserv'                  = 'Without this service Windows installs no updates, so security fixes that are already public never arrive.'
    'Service:BITS'                      = 'Without this service Windows cannot download updates in the background, and other programs that use it for their downloads fail as well.'
    'Service:Spooler'                   = 'Without this service nothing can be printed, and the printers disappear from the programs.'
    'Category:Services'                 = 'A Windows service that should be running and is not takes its function away. Programs that rely on it fail in ways that are hard to explain.'
}
