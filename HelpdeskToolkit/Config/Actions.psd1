@{
    # Where in Windows the problem of a check is fixed. The window shows the entry as a
    # button next to the recommendation of a result.
    #
    # The key is the name of the check, the part of the name before the first colon or
    # parenthesis ("Disk" for "Disk (C:)"), or "Category:<name>" for every check of a
    # category that has no entry of its own.
    #
    # Target is what Windows opens: a page of the Settings app (ms-settings:...), a
    # management console (.msc) or a program. Arguments are optional.

    # --- System ---------------------------------------------------------------------
    'Windows support'                   = @{ Label = 'Open Windows Update'; Target = 'ms-settings:windowsupdate' }
    'Stability index'                   = @{ Label = 'Open Reliability Monitor'; Target = 'perfmon.exe'; Arguments = '/rel' }
    'Windows activation'                = @{ Label = 'Open Activation settings'; Target = 'ms-settings:activation' }
    'Startup programs'                  = @{ Label = 'Open Startup apps'; Target = 'ms-settings:startupapps' }
    'Last startup duration'             = @{ Label = 'Open Startup apps'; Target = 'ms-settings:startupapps' }
    'Scheduled tasks'                   = @{ Label = 'Open Task Scheduler'; Target = 'taskschd.msc' }
    'Power plan'                        = @{ Label = 'Open Power settings'; Target = 'ms-settings:powersleep' }
    'Fast Startup'                      = @{ Label = 'Open Power Options'; Target = 'control.exe'; Arguments = '/name Microsoft.PowerOptions' }
    'Time zone'                         = @{ Label = 'Open Date and time settings'; Target = 'ms-settings:dateandtime' }
    'User profiles'                     = @{ Label = 'Open Storage settings'; Target = 'ms-settings:storagesense' }

    # --- Hardware -------------------------------------------------------------------
    'CPU load'                          = @{ Label = 'Open Task Manager'; Target = 'taskmgr.exe' }
    'Memory usage'                      = @{ Label = 'Open Task Manager'; Target = 'taskmgr.exe' }
    'Top memory consumers'              = @{ Label = 'Open Task Manager'; Target = 'taskmgr.exe' }
    'Page file'                         = @{ Label = 'Open Task Manager'; Target = 'taskmgr.exe' }
    'Disk'                              = @{ Label = 'Open Storage settings'; Target = 'ms-settings:storagesense' }
    'Largest folders'                   = @{ Label = 'Open Storage settings'; Target = 'ms-settings:storagesense' }
    'Temporary files'                   = @{ Label = 'Open Storage settings'; Target = 'ms-settings:storagesense' }
    'Hibernation file'                  = @{ Label = 'Open Power Options'; Target = 'control.exe'; Arguments = '/name Microsoft.PowerOptions' }
    'Downloads folder'                  = @{ Label = 'Open the Downloads folder'; Target = 'explorer.exe'; Arguments = 'shell:Downloads' }
    'Recycle Bin'                       = @{ Label = 'Open the Recycle Bin'; Target = 'explorer.exe'; Arguments = 'shell:RecycleBinFolder' }
    'System temporary files'            = @{ Label = 'Open Disk Cleanup'; Target = 'cleanmgr.exe' }
    'Drive'                             = @{ Label = 'Open Disk Management'; Target = 'diskmgmt.msc' }
    'Drive details'                     = @{ Label = 'Open Disk Management'; Target = 'diskmgmt.msc' }
    'Drive health'                      = @{ Label = 'Open Disk Management'; Target = 'diskmgmt.msc' }
    'File system'                       = @{ Label = 'Open Disk Management'; Target = 'diskmgmt.msc' }
    'Devices with problems'             = @{ Label = 'Open Device Manager'; Target = 'devmgmt.msc' }
    'Unsigned drivers'                  = @{ Label = 'Open Device Manager'; Target = 'devmgmt.msc' }
    'Old drivers'                       = @{ Label = 'Open Device Manager'; Target = 'devmgmt.msc' }
    'Drivers'                           = @{ Label = 'Open Device Manager'; Target = 'devmgmt.msc' }
    'Battery'                           = @{ Label = 'Open Power settings'; Target = 'ms-settings:powersleep' }
    'Battery health'                    = @{ Label = 'Open Power settings'; Target = 'ms-settings:powersleep' }

    # --- Software -------------------------------------------------------------------
    'Installed programs'                = @{ Label = 'Open Installed apps'; Target = 'ms-settings:appsfeatures' }
    'Recently installed'                = @{ Label = 'Open Installed apps'; Target = 'ms-settings:appsfeatures' }
    'Application crashes'               = @{ Label = 'Open Event Viewer'; Target = 'eventvwr.msc' }
    'Default browser'                   = @{ Label = 'Open Default apps'; Target = 'ms-settings:defaultapps' }

    # --- Event Log, Windows Update, Printers, Services: one place for the category ---
    'Category:Event Log'                = @{ Label = 'Open Event Viewer'; Target = 'eventvwr.msc' }
    'Category:Windows Update'           = @{ Label = 'Open Windows Update'; Target = 'ms-settings:windowsupdate' }
    'Category:Printers'                 = @{ Label = 'Open Printers and scanners'; Target = 'ms-settings:printers' }
    'Category:Services'                 = @{ Label = 'Open Services'; Target = 'services.msc' }

    # --- Security -------------------------------------------------------------------
    'Antivirus'                         = @{ Label = 'Open Windows Security'; Target = 'windowsdefender:' }
    'Defender real-time protection'     = @{ Label = 'Open Windows Security'; Target = 'windowsdefender://threat' }
    'Defender definitions'              = @{ Label = 'Open Windows Security'; Target = 'windowsdefender://threat' }
    'Defender last scan'                = @{ Label = 'Open Windows Security'; Target = 'windowsdefender://threat' }
    'Tamper protection'                 = @{ Label = 'Open Windows Security'; Target = 'windowsdefender://threat' }
    'Threat history'                    = @{ Label = 'Open Windows Security'; Target = 'windowsdefender://threat' }
    'Firewall - Domain profile'         = @{ Label = 'Open Firewall settings'; Target = 'windowsdefender://network' }
    'Firewall - Private profile'        = @{ Label = 'Open Firewall settings'; Target = 'windowsdefender://network' }
    'Firewall - Public profile'         = @{ Label = 'Open Firewall settings'; Target = 'windowsdefender://network' }
    'Firewall'                          = @{ Label = 'Open Firewall settings'; Target = 'windowsdefender://network' }
    'User Account Control'              = @{ Label = 'Open User Account Control settings'; Target = 'UserAccountControlSettings.exe' }
    'Remote Desktop'                    = @{ Label = 'Open Remote Desktop settings'; Target = 'ms-settings:remotedesktop' }
    'Account type'                      = @{ Label = 'Open account settings'; Target = 'ms-settings:otherusers' }
    'Administrators'                    = @{ Label = 'Open account settings'; Target = 'ms-settings:otherusers' }
    'Local accounts'                    = @{ Label = 'Open account settings'; Target = 'ms-settings:otherusers' }
    'Guest account'                     = @{ Label = 'Open account settings'; Target = 'ms-settings:otherusers' }
    'Built-in Administrator account'    = @{ Label = 'Open account settings'; Target = 'ms-settings:otherusers' }
    'Automatic sign-in'                 = @{ Label = 'Open User Accounts'; Target = 'netplwiz.exe' }
    'Shared folders'                    = @{ Label = 'Open Shared Folders'; Target = 'fsmgmt.msc' }
    'Listening ports'                   = @{ Label = 'Open Firewall settings'; Target = 'windowsdefender://network' }
    'File History'                      = @{ Label = 'Open File History'; Target = 'control.exe'; Arguments = '/name Microsoft.FileHistory' }
    'System Restore'                    = @{ Label = 'Open System Protection'; Target = 'SystemPropertiesProtection.exe' }
    'Secure Boot'                       = @{ Label = 'Open System Information'; Target = 'msinfo32.exe' }
    'TPM'                               = @{ Label = 'Open TPM management'; Target = 'tpm.msc' }
    'BitLocker'                         = @{ Label = 'Open BitLocker'; Target = 'control.exe'; Arguments = '/name Microsoft.BitLockerDriveEncryption' }
    'Failed sign-ins'                   = @{ Label = 'Open Event Viewer'; Target = 'eventvwr.msc' }
    'Account lockouts'                  = @{ Label = 'Open Event Viewer'; Target = 'eventvwr.msc' }

    # --- Network --------------------------------------------------------------------
    'Network adapters'                  = @{ Label = 'Open Network settings'; Target = 'ms-settings:network-status' }
    'Adapter'                           = @{ Label = 'Open Network settings'; Target = 'ms-settings:network-status' }
    'Wi-Fi'                             = @{ Label = 'Open Wi-Fi settings'; Target = 'ms-settings:network-wifi' }
    'Network profile'                   = @{ Label = 'Open Network settings'; Target = 'ms-settings:network-status' }
    'Proxy'                             = @{ Label = 'Open Proxy settings'; Target = 'ms-settings:network-proxy' }
    'Ping default gateway'              = @{ Label = 'Open Network settings'; Target = 'ms-settings:network-status' }
    'Ping internet'                     = @{ Label = 'Open Network settings'; Target = 'ms-settings:network-status' }
    'DNS resolution'                    = @{ Label = 'Open Network settings'; Target = 'ms-settings:network-status' }
    'HTTPS access'                      = @{ Label = 'Open Proxy settings'; Target = 'ms-settings:network-proxy' }
    'Clock accuracy'                    = @{ Label = 'Open Date and time settings'; Target = 'ms-settings:dateandtime' }
}
