function Get-SecurityHealth {
    <#
    .SYNOPSIS
        Checks Microsoft Defender, the firewall, the protection features of Windows, accounts, privacy, Secure Boot, TPM and BitLocker.
    .DESCRIPTION
        - Defender real-time protection. When it is off because a third-party
          antivirus is registered in Windows Security Center, that is reported as
          information instead of a problem.
        - Age of the antivirus definitions, tamper protection and time since the last
          quick scan.
        - State of the Domain, Private and Public firewall profiles.
        - User Account Control, Remote Desktop and whether the signed-in user is a
          local administrator.
        - The protection features Windows Security lists: SmartScreen, memory
          integrity (Core isolation) and the protection of the sign-in data (LSA).
          SmartScreen that is switched off is a Warning.
        - SMB 1.0, the outdated file sharing protocol: a Warning while it is enabled.
        - Whether the screen locks by itself after a time without activity.
        - Which programs used the camera, the microphone and the location lately, and
          which USB storage devices have been connected.
        - Threats Defender has found, with a Critical result for one that is still active.
        - The members of the Administrators group, automatic sign-in, local accounts
          (with a warning for an enabled Guest account) and folders shared on the network.
        - Secure Boot state.
        - TPM presence and version, BitLocker protection of every drive, and failed
          sign-ins and account lockouts from the Security log. Windows only exposes
          these to administrators, so without elevation they are skipped and marked
          "Requires admin".

        Nothing is changed on the system. The limits come from Config\Thresholds.psd1.
    .PARAMETER Days
        How many days of the Security log to analyze for failed sign-ins and account
        lockouts. The default is 7. Only used with administrator rights.
    .EXAMPLE
        Get-SecurityHealth

        Returns the security results for the local computer.
    .EXAMPLE
        Get-SecurityHealth | Where-Object Status -in 'Warning', 'Critical'

        Shows only the security findings that need attention.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [ValidateRange(1, 365)]
        [int]$Days = 7
    )

    $category = 'Security'
    $thresholds = (Get-HealthThreshold).Defender

    # Microsoft Defender
    try {
        $defender = Get-DefenderStatus

        if ($defender.RealTimeProtectionEnabled) {
            New-CheckResult -Category $category -Check 'Defender real-time protection' -Status OK -Value 'Enabled'
        }
        else {
            $otherProducts = @(Get-AntivirusProduct | Where-Object { $_ -notmatch 'Defender' })
            if ($otherProducts.Count -gt 0) {
                New-CheckResult -Category $category -Check 'Defender real-time protection' -Status Info `
                    -Value ('Disabled (third-party antivirus: {0})' -f ($otherProducts -join ', '))
            }
            else {
                New-CheckResult -Category $category -Check 'Defender real-time protection' -Status Critical -Value 'Disabled' `
                    -Recommendation 'No active antivirus was found. Turn on real-time protection in Windows Security > Virus & threat protection.'
            }
        }

        # Definitions are only kept up to date while Defender is the active antivirus.
        if ($defender.AntivirusEnabled) {
            $age = [int]$defender.AntivirusSignatureAge
            $status = Get-ThresholdStatus -Value $age -Warning $thresholds.SignatureWarningDays -Critical $thresholds.SignatureCriticalDays
            $recommendation = if ($status -ne 'OK') {
                'Antivirus definitions are out of date. Open Windows Security > Virus & threat protection > Protection updates and check for updates.'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Defender definitions' -Status $status `
                -Value ('{0} {1} old (updated {2:yyyy-MM-dd HH:mm})' -f $age, $(if ($age -eq 1) { 'day' } else { 'days' }), $defender.AntivirusSignatureLastUpdated) `
                -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.SignatureWarningDays -Critical $thresholds.SignatureCriticalDays -Unit 'days') `
                -Typical $thresholds.Typical

            # Tamper protection stops programs (and malware) from switching Defender off.
            if ($defender.IsTamperProtected) {
                New-CheckResult -Category $category -Check 'Tamper protection' -Status OK -Value 'Enabled'
            }
            else {
                New-CheckResult -Category $category -Check 'Tamper protection' -Status Warning -Value 'Disabled' `
                    -Recommendation 'Without tamper protection a program can switch off the antivirus. Turn it on in Windows Security > Virus & threat protection > Manage settings > Tamper Protection.'
            }

            # Last quick scan. Defender reports 4294967295 when it has never scanned.
            $neverScanned = 4294967295
            $scanAge = [double]$defender.QuickScanAge
            $scanAllowed = Format-AllowedRange -Warning $thresholds.ScanWarningDays -Unit 'days'
            $scanAdvice = 'Run a scan: open Windows Security > Virus & threat protection and choose "Quick scan".'
            if ($scanAge -ge $neverScanned) {
                New-CheckResult -Category $category -Check 'Defender last scan' -Status Warning -Value 'Never' `
                    -Recommendation ('The computer has never been scanned. {0}' -f $scanAdvice) -Allowed $scanAllowed -Typical $thresholds.TypicalScan
            }
            else {
                $status = Get-ThresholdStatus -Value $scanAge -Warning $thresholds.ScanWarningDays
                $recommendation = if ($status -ne 'OK') { 'The last scan was a long time ago. {0}' -f $scanAdvice } else { '' }
                New-CheckResult -Category $category -Check 'Defender last scan' -Status $status `
                    -Value ('{0} {1} ago' -f $scanAge, $(if ($scanAge -eq 1) { 'day' } else { 'days' })) `
                    -Recommendation $recommendation -Allowed $scanAllowed -Typical $thresholds.TypicalScan
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Microsoft Defender' -ErrorRecord $_
    }

    # Threats Defender has found so far
    try {
        $threats = @(Get-DefenderThreat)
        $active = @($threats | Where-Object { $_.IsActive })

        if ($active.Count -gt 0) {
            New-CheckResult -Category $category -Check 'Threat history' -Status Critical `
                -Value ('{0} active: {1}' -f $active.Count, (($active | ForEach-Object { $_.Name }) -join ', ')) `
                -Recommendation 'Malware is active on this computer. Open Windows Security > Virus & threat protection > Protection history, apply the recommended action and run a full scan. Disconnect the computer from the network if it holds sensitive data.'
        }
        elseif ($threats.Count -gt 0) {
            $names = @($threats | ForEach-Object { $_.Name })
            $shown = 3
            $remaining = @($names | Select-Object -Skip $shown)
            $value = '{0} found earlier and handled: {1}' -f $threats.Count, (($names | Select-Object -First $shown) -join ', ')
            if ($remaining.Count -gt 0) {
                $value = '{0} and {1} more' -f $value, $remaining.Count
            }
            New-CheckResult -Category $category -Check 'Threat history' -Status Info -Value $value -Details $remaining
        }
        else {
            New-CheckResult -Category $category -Check 'Threat history' -Status OK -Value 'No threats found'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Threat history' -ErrorRecord $_
    }

    # Firewall profiles
    try {
        $firewallProfiles = @(Get-FirewallProfileState)
        foreach ($firewallProfile in $firewallProfiles) {
            $check = 'Firewall - {0} profile' -f $firewallProfile.Name
            if ($firewallProfile.Enabled) {
                New-CheckResult -Category $category -Check $check -Status OK -Value 'Enabled'
            }
            else {
                New-CheckResult -Category $category -Check $check -Status Warning -Value 'Disabled' `
                    -Recommendation 'Turn on Windows Defender Firewall for this profile (Windows Security > Firewall & network protection), unless a third-party firewall is installed.'
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Firewall' -ErrorRecord $_
    }

    # User Account Control. EnableLUA = 0 switches UAC off completely.
    $uac = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA'
    if ($null -eq $uac) {
        New-CheckResult -Category $category -Check 'User Account Control' -Status Info -Value 'Unknown'
    }
    elseif ($uac -eq 0) {
        New-CheckResult -Category $category -Check 'User Account Control' -Status Critical -Value 'Disabled' `
            -Recommendation 'With UAC off every program runs with full rights without asking. Turn it on: Control Panel > User Accounts > Change User Account Control settings, move the slider up and restart the computer.'
    }
    else {
        New-CheckResult -Category $category -Check 'User Account Control' -Status OK -Value 'Enabled'
    }

    # SmartScreen for programs and files ("Check apps and files" in Windows Security).
    # A policy decides when it is set; otherwise the setting of Windows Security counts.
    $smartScreenPolicy = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableSmartScreen'
    $smartScreen = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'SmartScreenEnabled'
    if ($smartScreenPolicy -eq 0 -or ($null -eq $smartScreenPolicy -and [string]$smartScreen -eq 'Off')) {
        New-CheckResult -Category $category -Check 'SmartScreen' -Status Warning -Value 'Disabled' `
            -Recommendation 'Windows does not check downloaded programs against the list of known malware. Turn it on in Windows Security > App & browser control > Reputation-based protection > "Check apps and files".'
    }
    else {
        New-CheckResult -Category $category -Check 'SmartScreen' -Status OK -Value 'Enabled'
    }

    # Memory integrity (Core isolation). 2 is its number among the running features.
    $guardServices = @(Get-DeviceGuardService)
    $memoryIntegrity = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' -Name 'Enabled'
    if ($guardServices -contains 2) {
        New-CheckResult -Category $category -Check 'Memory integrity' -Status OK -Value 'Enabled'
    }
    elseif ($memoryIntegrity -eq 1 -and $guardServices.Count -gt 0) {
        New-CheckResult -Category $category -Check 'Memory integrity' -Status Info -Value 'Turned on, but not running' `
            -Recommendation 'Memory integrity is switched on but does not run. Restart the computer; when it still does not run, an incompatible driver blocks it, which Windows Security > Device security > Core isolation names.'
    }
    elseif ($memoryIntegrity -eq 1) {
        New-CheckResult -Category $category -Check 'Memory integrity' -Status OK -Value 'Enabled'
    }
    else {
        New-CheckResult -Category $category -Check 'Memory integrity' -Status Info -Value 'Disabled' `
            -Recommendation 'Memory integrity stops malicious drivers from getting into the core of Windows. It can be turned on in Windows Security > Device security > Core isolation; a restart is needed, and very old drivers may have to be updated first.'
    }

    # Protection of the process that holds the sign-in data (LSA). 1 and 2 both mean on.
    $lsaProtection = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RunAsPPL'
    if ($lsaProtection -eq 1 -or $lsaProtection -eq 2) {
        New-CheckResult -Category $category -Check 'LSA protection' -Status OK -Value 'Enabled'
    }
    else {
        New-CheckResult -Category $category -Check 'LSA protection' -Status Info -Value 'Disabled' `
            -Recommendation 'Without this protection a program with administrator rights can read the saved sign-in data out of the memory. It can be turned on in Windows Security > Device security > Core isolation > Local Security Authority protection.'
    }

    # SMB 1.0, the file sharing protocol of the 1990s. The client is a driver of its
    # own (mrxsmb10; start type 4 = disabled, no key = not installed), the server part
    # is switched with one value.
    $smbClient = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' -Name 'Start'
    $smbServer = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -Name 'SMB1'
    $smbParts = @(
        if ($null -ne $smbClient -and $smbClient -ne 4) { 'client' }
        if ($smbServer -eq 1) { 'server' }
    )
    if ($smbParts.Count -gt 0) {
        New-CheckResult -Category $category -Check 'SMB 1.0' -Status Warning -Value ('Enabled ({0})' -f ($smbParts -join ', ')) `
            -Recommendation 'SMB 1.0 is an outdated file sharing protocol with known security holes; the WannaCry ransomware spread through it. Remove it in "Turn Windows features on or off" > "SMB 1.0/CIFS File Sharing Support", unless a very old device (an old NAS or scanner) still needs it.'
    }
    else {
        New-CheckResult -Category $category -Check 'SMB 1.0' -Status OK -Value 'Disabled'
    }

    # Remote Desktop. fDenyTSConnections = 0 means incoming connections are accepted.
    $denyRemoteDesktop = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections'
    if ($null -eq $denyRemoteDesktop) {
        New-CheckResult -Category $category -Check 'Remote Desktop' -Status Info -Value 'Unknown'
    }
    elseif ($denyRemoteDesktop -eq 0) {
        New-CheckResult -Category $category -Check 'Remote Desktop' -Status Info -Value 'Enabled' `
            -Recommendation 'The computer accepts Remote Desktop connections. If nobody needs to connect to it remotely, turn it off in Settings > System > Remote Desktop.'
    }
    else {
        New-CheckResult -Category $category -Check 'Remote Desktop' -Status OK -Value 'Disabled'
    }

    # Account type of the user running the tool
    if (Test-IsAdministratorMember) {
        New-CheckResult -Category $category -Check 'Account type' -Status Info -Value 'Administrator' `
            -Recommendation 'The signed-in user is a local administrator, so malware started by this user can take over the whole computer. For daily work a standard account is safer.'
    }
    else {
        New-CheckResult -Category $category -Check 'Account type' -Status OK -Value 'Standard user'
    }

    # Who has full control over this computer
    try {
        $administrators = @(Get-AdministratorGroupMember)
        New-CheckResult -Category $category -Check 'Administrators' -Status Info `
            -Value ('{0} members: {1}' -f $administrators.Count, $(if ($administrators.Count -gt 0) { $administrators -join ', ' } else { 'none' }))
    }
    catch {
        New-FailureResult -Category $category -Check 'Administrators' -ErrorRecord $_
    }

    # Automatic sign-in. AutoAdminLogon = 1 signs a stored account in at every start.
    $autoSignIn = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoAdminLogon'
    if ([string]$autoSignIn -eq '1') {
        New-CheckResult -Category $category -Check 'Automatic sign-in' -Status Warning -Value 'Enabled' `
            -Recommendation 'Windows signs in without asking for a password, so anyone who switches the computer on can use that account. Turn it off: run "netplwiz" and tick "Users must enter a user name and password to use this computer".'
    }
    else {
        New-CheckResult -Category $category -Check 'Automatic sign-in' -Status OK -Value 'Disabled'
    }

    # Does the screen lock by itself? Two things can do that after a time without
    # activity: a limit set for the whole computer, or a screen saver that asks for the
    # password (set by a policy or by the user).
    $lockSeconds = 0
    $machineLimit = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'InactivityTimeoutSecs'
    if ($machineLimit -as [int] -gt 0) {
        $lockSeconds = [int]$machineLimit
    }
    foreach ($desktop in 'HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop', 'HKCU:\Control Panel\Desktop') {
        if ($lockSeconds -gt 0) {
            break
        }
        $active = Get-RegistryValue -Path $desktop -Name 'ScreenSaveActive'
        $secure = Get-RegistryValue -Path $desktop -Name 'ScreenSaverIsSecure'
        $program = Get-RegistryValue -Path $desktop -Name 'SCRNSAVE.EXE'
        $timeout = Get-RegistryValue -Path $desktop -Name 'ScreenSaveTimeOut'
        if ([string]$active -eq '1' -and [string]$secure -eq '1' -and $program -and $timeout -as [int] -gt 0) {
            $lockSeconds = [int]$timeout
        }
    }

    if ($lockSeconds -gt 0) {
        $minutes = [int][math]::Ceiling($lockSeconds / 60)
        New-CheckResult -Category $category -Check 'Screen lock' -Status OK `
            -Value ('Locks after {0} {1} without activity' -f $minutes, $(if ($minutes -eq 1) { 'minute' } else { 'minutes' }))
    }
    else {
        New-CheckResult -Category $category -Check 'Screen lock' -Status Info -Value 'Does not lock by itself after a time without activity' `
            -Recommendation 'Anyone who passes by an unattended computer can use the signed-in account. Lock the screen with the Windows key + L when leaving, or let Windows do it: Settings > Personalization > Lock screen > Screen saver, choose a waiting time and tick "On resume, display logon screen".'
    }

    # Local accounts. The built-in accounts are recognized by the end of their security
    # identifier (SID), because their names are translated and can be renamed.
    try {
        $accounts = @(Get-CimInstance -ClassName Win32_UserAccount -Filter 'LocalAccount = True' -ErrorAction Stop)

        $enabled = @($accounts | Where-Object { -not $_.Disabled } | ForEach-Object { $_.Name })
        New-CheckResult -Category $category -Check 'Local accounts' -Status Info `
            -Value ('{0} enabled: {1}' -f $enabled.Count, $(if ($enabled.Count -gt 0) { $enabled -join ', ' } else { 'none' }))

        $guest = $accounts | Where-Object { $_.SID -like '*-501' } | Select-Object -First 1
        if ($guest -and -not $guest.Disabled) {
            New-CheckResult -Category $category -Check 'Guest account' -Status Warning -Value 'Enabled' `
                -Recommendation 'Anyone can sign in with the Guest account without a password. An administrator should disable it: Computer Management > Local Users and Groups > Users > Guest > "Account is disabled".'
        }
        else {
            New-CheckResult -Category $category -Check 'Guest account' -Status OK -Value 'Disabled'
        }

        $builtInAdministrator = $accounts | Where-Object { $_.SID -like '*-500' } | Select-Object -First 1
        if ($builtInAdministrator -and -not $builtInAdministrator.Disabled) {
            New-CheckResult -Category $category -Check 'Built-in Administrator account' -Status Info -Value 'Enabled' `
                -Recommendation 'The built-in Administrator account is a well-known target and is not protected by UAC prompts. Use a separate administrator account and keep this one disabled.'
        }
        else {
            New-CheckResult -Category $category -Check 'Built-in Administrator account' -Status OK -Value 'Disabled'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Local accounts' -ErrorRecord $_
    }

    # Folders shared on the network. Type 0 is a disk share; names ending in $ are the
    # hidden administrative shares that Windows creates itself.
    try {
        $shares = @(Get-CimInstance -ClassName Win32_Share -ErrorAction Stop |
                Where-Object { $_.Type -eq 0 -and $_.Name -notlike '*$' } |
                ForEach-Object { '{0} ({1})' -f $_.Name, $_.Path })

        if ($shares.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Shared folders' -Status OK -Value 'None'
        }
        else {
            New-CheckResult -Category $category -Check 'Shared folders' -Status Info -Value ('{0}: {1}' -f $shares.Count, ($shares -join ', ')) `
                -Recommendation 'These folders can be reached from other computers on the network. Stop sharing the ones that are no longer needed: right-click the folder > Properties > Sharing.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Shared folders' -ErrorRecord $_
    }

    # Ports on which programs of this computer wait for connections from the network
    try {
        $ports = @(Get-ListeningPort | Where-Object { -not $_.LocalOnly })
        $risky = (Get-HealthThreshold).Ports.Risky
        $exposed = @($ports | Where-Object { $risky.ContainsKey([int]$_.Port) } |
                ForEach-Object { '{0} ({1}, {2})' -f $_.Port, $risky[[int]$_.Port], $_.Process })

        # "svchost: 135, 5040" - one entry per program
        $byProgram = @($ports | Group-Object -Property Process | Sort-Object -Property Name |
                ForEach-Object { '{0}: {1}' -f $_.Name, (($_.Group | ForEach-Object { $_.Port }) -join ', ') })
        $list = ConvertTo-ListValue -Item $byProgram -Shown 4
        $value = if ($ports.Count -gt 0) { '{0} ports open to the network: {1}' -f $ports.Count, $list.Value } else { 'None open to the network' }

        if ($exposed.Count -gt 0) {
            New-CheckResult -Category $category -Check 'Listening ports' -Status Warning -Value $value -Details $list.Details `
                -Recommendation ('A program accepts connections on a port that should not be open: {0}. These services send passwords unencrypted or are a common way into a computer. Stop or uninstall the program unless it is really needed, and make sure the firewall is on.' -f ($exposed -join ', '))
        }
        else {
            New-CheckResult -Category $category -Check 'Listening ports' -Status Info -Value $value -Details $list.Details
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Listening ports' -ErrorRecord $_
    }

    # Which programs used the camera, the microphone and the location lately
    $privacyDays = (Get-HealthThreshold).Privacy.RecentDays
    $capabilities = [ordered]@{
        'Camera use'     = 'webcam'
        'Microphone use' = 'microphone'
        'Location use'   = 'location'
    }
    foreach ($check in $capabilities.Keys) {
        $capability = $capabilities[$check]
        try {
            $consent = Get-RegistryValue -Name 'Value' `
                -Path ('HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\{0}' -f $capability)
            if ([string]$consent -eq 'Deny') {
                New-CheckResult -Category $category -Check $check -Status Info -Value 'Turned off for this account'
                continue
            }

            $since = (Get-Date).AddDays(-$privacyDays)
            $recent = @(Get-CapabilityUsage -Capability $capability | Where-Object { $_.InUse -or $_.LastUsed -ge $since } |
                    Sort-Object -Property @{ Expression = 'InUse'; Descending = $true }, @{ Expression = 'LastUsed'; Descending = $true })

            if ($recent.Count -eq 0) {
                New-CheckResult -Category $category -Check $check -Status Info -Value ('Not used in the last {0} days' -f $privacyDays)
            }
            else {
                $names = @($recent | ForEach-Object {
                        if ($_.InUse) { '{0} (in use right now)' -f $_.Program } else { '{0} ({1:yyyy-MM-dd})' -f $_.Program, $_.LastUsed }
                    })
                $list = ConvertTo-ListValue -Item $names -Shown 4
                New-CheckResult -Category $category -Check $check -Status Info -Details $list.Details `
                    -Value ('{0} {1} in the last {2} days: {3}' -f $recent.Count, $(if ($recent.Count -eq 1) { 'program' } else { 'programs' }), $privacyDays, $list.Value)
            }
        }
        catch {
            New-FailureResult -Category $category -Check $check -ErrorRecord $_
        }
    }

    # USB sticks and USB disks that have been connected to this computer
    try {
        $usbDevices = @(Get-UsbStorageDevice | Sort-Object -Unique)
        if ($usbDevices.Count -eq 0) {
            New-CheckResult -Category $category -Check 'USB storage devices' -Status Info -Value 'None on record'
        }
        else {
            $list = ConvertTo-ListValue -Item $usbDevices -Shown 5
            New-CheckResult -Category $category -Check 'USB storage devices' -Status Info -Details $list.Details `
                -Value ('{0} {1} connected so far: {2}' -f $usbDevices.Count, $(if ($usbDevices.Count -eq 1) { 'device' } else { 'devices' }), $list.Value)
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'USB storage devices' -ErrorRecord $_
    }

    # Backup of personal files: File History and OneDrive
    $fileHistory = Get-FileHistoryTarget
    $oneDriveAccounts = @(Get-ChildItem -Path 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue |
            Where-Object { $_.GetValue('UserFolder') })
    $oneDriveRunning = @(Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue).Count -gt 0

    if ($fileHistory) {
        New-CheckResult -Category $category -Check 'File History' -Status Info -Value ('Set up, saves to {0}' -f $fileHistory)
    }
    else {
        # Without any sign of a backup the advice is given; another backup program may
        # of course be in use, which is why this is not a warning.
        $recommendation = if ($oneDriveAccounts.Count -eq 0) {
            'No backup of the personal files was found (neither File History nor OneDrive). If no other backup program is used, set one up: a disk can fail without warning. File History is in Control Panel > File History.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'File History' -Status Info -Value 'Not set up' -Recommendation $recommendation
    }

    $oneDriveValue = if ($oneDriveAccounts.Count -eq 0) {
        'Not signed in'
    }
    elseif ($oneDriveRunning) {
        'Signed in and running'
    }
    else {
        'Signed in, but not running'
    }
    New-CheckResult -Category $category -Check 'OneDrive' -Status Info -Value $oneDriveValue

    # System Restore. RPSessionInterval = 1 means protection is on for at least one drive.
    $protection = Get-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'RPSessionInterval'
    if ($protection -ne 1) {
        New-CheckResult -Category $category -Check 'System Restore' -Status Info -Value 'Off' `
            -Recommendation 'System Restore is off, so Windows cannot be taken back to an earlier state after a bad driver or update. It can be turned on in System Properties > System Protection.'
    }
    elseif (-not (Test-IsAdministrator)) {
        New-CheckResult -Category $category -Check 'System Restore' -Status Info -Value 'On (the restore points are only shown to administrators)'
    }
    else {
        try {
            $points = @(Get-RestorePoint | Sort-Object -Descending)
            $value = if ($points.Count -gt 0) {
                'On, {0} restore points, newest from {1:yyyy-MM-dd}' -f $points.Count, $points[0]
            }
            else {
                'On, no restore point yet'
            }
            New-CheckResult -Category $category -Check 'System Restore' -Status Info -Value $value
        }
        catch {
            New-FailureResult -Category $category -Check 'System Restore' -ErrorRecord $_
        }
    }

    # Secure Boot
    switch (Get-SecureBootState) {
        'Enabled' {
            New-CheckResult -Category $category -Check 'Secure Boot' -Status OK -Value 'Enabled'
        }
        'Disabled' {
            New-CheckResult -Category $category -Check 'Secure Boot' -Status Info -Value 'Disabled' `
                -Recommendation 'Secure Boot protects the startup process from tampering and is required by Windows 11. It can be turned on in the UEFI firmware settings.'
        }
        default {
            New-CheckResult -Category $category -Check 'Secure Boot' -Status Info -Value 'Not supported (legacy BIOS mode)'
        }
    }

    # TPM (administrators only; without elevation the query just waits and fails)
    if (-not (Test-IsAdministrator)) {
        New-AdminRequiredResult -Category $category -Check 'TPM'
    }
    else {
        try {
            $tpm = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop |
                Select-Object -First 1

            if (-not $tpm) {
                New-CheckResult -Category $category -Check 'TPM' -Status Info -Value 'Not present' `
                    -Recommendation 'No TPM was found. Windows 11 and BitLocker need TPM 2.0; it can often be enabled in the UEFI firmware settings.'
            }
            else {
                # SpecVersion looks like "2.0, 0, 1.59"; the first part is the TPM version.
                $version = ([string]$tpm.SpecVersion -split ',')[0].Trim()
                if ($tpm.IsEnabled_InitialValue) {
                    New-CheckResult -Category $category -Check 'TPM' -Status OK -Value ('Enabled, version {0}' -f $version)
                }
                else {
                    New-CheckResult -Category $category -Check 'TPM' -Status Warning -Value ('Present but disabled, version {0}' -f $version) `
                        -Recommendation 'Enable the TPM in the UEFI firmware settings.'
                }
            }
        }
        catch {
            New-FailureResult -Category $category -Check 'TPM' -ErrorRecord $_
        }
    }

    # BitLocker on every drive (administrators only)
    if (-not (Test-IsAdministrator)) {
        New-AdminRequiredResult -Category $category -Check ('BitLocker ({0})' -f $env:SystemDrive)
    }
    else {
        try {
            $volumes = @(Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftVolumeEncryption' `
                    -ClassName Win32_EncryptableVolume -ErrorAction Stop |
                    Where-Object { $_.DriveLetter } | Sort-Object -Property DriveLetter)

            if ($volumes.Count -eq 0) {
                New-CheckResult -Category $category -Check 'BitLocker' -Status Info -Value 'Not available on this system'
            }

            foreach ($volume in $volumes) {
                $check = 'BitLocker ({0})' -f $volume.DriveLetter
                if ($volume.ProtectionStatus -eq 1) {
                    New-CheckResult -Category $category -Check $check -Status OK -Value 'Protection on'
                }
                else {
                    New-CheckResult -Category $category -Check $check -Status Info -Value 'Protection off' `
                        -Recommendation 'The drive is not encrypted, so its data can be read by anyone who removes it from the computer. Consider turning on BitLocker, especially on laptops.'
                }
            }
        }
        catch {
            New-FailureResult -Category $category -Check 'BitLocker' -ErrorRecord $_
        }
    }

    # Sign-in problems from the Security log (administrators only). Without elevation
    # Windows does not answer "access denied" for this log but finds no events, which
    # would look like a clean result, so the check is not attempted at all.
    if (-not (Test-IsAdministrator)) {
        New-AdminRequiredResult -Category $category -Check 'Failed sign-ins'
        New-AdminRequiredResult -Category $category -Check 'Account lockouts'
    }
    else {
        $since = (Get-Date).AddDays(-$Days)
        $period = if ($Days -eq 1) { 'in the last day' } else { 'in the last {0} days' -f $Days }
        $signIn = (Get-HealthThreshold).SignIn

        try {
            $failed = @(Get-SignInEvent -Kind FailedSignIn -Since $since)
            $value = '{0} {1}' -f $failed.Count, $period
            if ($failed.Count -gt 0) {
                $byAccount = @($failed | Group-Object | Sort-Object -Property Count -Descending | Select-Object -First 3 |
                        ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count })
                $value = '{0}, most for: {1}' -f $value, ($byAccount -join ', ')
            }

            $status = Get-ThresholdStatus -Value $failed.Count -Warning $signIn.FailedWarningAbove
            $recommendation = if ($status -ne 'OK') {
                'There were unusually many sign-ins with a wrong password. If the user did not cause them, someone may be guessing the password: change it and check which device keeps trying (Event Viewer > Windows Logs > Security, event 4625).'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Failed sign-ins' -Status $status -Value $value -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $signIn.FailedWarningAbove) -Typical $signIn.TypicalFailed
        }
        catch {
            New-FailureResult -Category $category -Check 'Failed sign-ins' -ErrorRecord $_
        }

        try {
            $lockouts = @(Get-SignInEvent -Kind Lockout -Since $since)
            if ($lockouts.Count -gt 0) {
                $accounts = @($lockouts | Sort-Object -Unique)
                New-CheckResult -Category $category -Check 'Account lockouts' -Status Warning `
                    -Value ('{0} {1}: {2}' -f $lockouts.Count, $period, ($accounts -join ', ')) `
                    -Recommendation 'An account was locked after too many wrong passwords. A common cause is an old password saved on a phone, in a mapped drive or in a scheduled task; update or remove it there.'
            }
            else {
                New-CheckResult -Category $category -Check 'Account lockouts' -Status OK -Value ('0 {0}' -f $period)
            }
        }
        catch {
            New-FailureResult -Category $category -Check 'Account lockouts' -ErrorRecord $_
        }
    }
}
