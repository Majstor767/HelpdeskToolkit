function Get-SoftwareHealth {
    <#
    .SYNOPSIS
        Reports installed programs, unsupported and outdated ones, Microsoft Office, application crashes, browser extensions, the default browser and leftover entries.
    .DESCRIPTION
        - Installed programs: how many there are and their names with versions. The
          first few are part of the value, the rest is returned in the Details property.
        - Recently installed: programs installed in the last 30 days. "What changed
          recently?" is often the fastest way to the cause of a new problem.
        - Application crashes: how often programs crashed in the selected period and
          which ones. More crashes than the limit in Config\Thresholds.psd1 is a Warning.
        - Unsupported programs: installed programs whose maker no longer releases
          security updates for them (the list is in Config\EndOfLife.psd1). A Warning.
        - Program updates: programs for which winget knows a newer version. More of
          them than the limit is a Warning. This asks the internet and is left out
          with -SkipUpdateCheck.
        - Microsoft Office: version, update channel, and a Warning when its automatic
          updates are switched off.
        - Outlook data files: the mailbox files of the signed-in user. A file near
          the size limit of Outlook is a Warning or Critical.
        - Browser extensions of Chrome, Edge, Brave and Opera, with their versions.
        - Default browser.
        - Leftover program entries: programs that are still listed as installed
          although the file that removes them is gone (reported as Info).

        Everything is read from the registry, the Application event log and the list
        of winget, without administrator rights. Nothing is installed, updated,
        removed or changed.
    .PARAMETER Days
        How many days of crash history to analyze. The default is 7.
    .PARAMETER SkipUpdateCheck
        Do not ask winget for newer versions of the installed programs. Use it on a
        computer without an internet connection; the check is then marked "Skipped".
    .EXAMPLE
        Get-SoftwareHealth

        Returns the software results for the local computer.
    .EXAMPLE
        Get-SoftwareHealth -Days 30 | Where-Object Check -eq 'Application crashes'

        Shows which programs crashed in the last 30 days and how often.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [ValidateRange(1, 365)]
        [int]$Days = 7,

        [switch]$SkipUpdateCheck
    )

    $category = 'Software'
    $thresholds = (Get-HealthThreshold).Software
    $shown = 8

    # Installed programs and recent installations
    try {
        $programs = @(Get-InstalledProgram | Sort-Object -Property Name)
        $list = @($programs | ForEach-Object { ('{0} {1}' -f $_.Name, $_.Version).Trim() })
        $remaining = @($list | Select-Object -Skip $shown)
        $value = '{0} programs' -f $programs.Count
        if ($list.Count -gt 0) {
            $value = '{0}: {1}' -f $value, (($list | Select-Object -First $shown) -join ', ')
        }
        if ($remaining.Count -gt 0) {
            $value = '{0} and {1} more' -f $value, $remaining.Count
        }
        New-CheckResult -Category $category -Check 'Installed programs' -Status Info -Value $value -Details $remaining

        $since = (Get-Date).Date.AddDays(-$thresholds.RecentDays)
        $recent = @($programs | Where-Object { $_.InstallDate -and $_.InstallDate -ge $since } |
                Sort-Object -Property InstallDate -Descending |
                ForEach-Object { [string]::Format([cultureinfo]::InvariantCulture, '{0} ({1:yyyy-MM-dd})', $_.Name, $_.InstallDate) })

        if ($recent.Count -eq 0) {
            $value = 'None in the last {0} days' -f $thresholds.RecentDays
        }
        else {
            $value = '{0} in the last {1} days: {2}' -f $recent.Count, $thresholds.RecentDays, (($recent | Select-Object -First $shown) -join ', ')
        }
        $remaining = @($recent | Select-Object -Skip $shown)
        if ($remaining.Count -gt 0) {
            $value = '{0} and {1} more' -f $value, $remaining.Count
        }
        New-CheckResult -Category $category -Check 'Recently installed' -Status Info -Value $value -Details $remaining

        # Entries of programs that are no longer there: their folder was deleted by
        # hand, so the uninstaller is gone and "Uninstall" fails.
        $leftover = @($programs | Where-Object { Test-UninstallerMissing -Program $_ } | ForEach-Object { $_.Name })
        if ($leftover.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Leftover program entries' -Status OK -Value 'None found'
        }
        else {
            $list = ConvertTo-ListValue -Item $leftover -Shown 4
            $value = '{0} {1} whose uninstaller is gone: {2}' -f $leftover.Count, $(if ($leftover.Count -eq 1) { 'entry' } else { 'entries' }), $list.Value
            New-CheckResult -Category $category -Check 'Leftover program entries' -Status Info -Value $value -Details $list.Details `
                -Recommendation 'These programs are still listed under Installed apps, but the file that removes them no longer exists, usually because their folder was deleted by hand. "Uninstall" fails for them. They do no harm and take up next to no space. To get rid of an entry, install the program again and then uninstall it properly, or use the "Program Install and Uninstall troubleshooter" of Microsoft.'
        }

        # Programs whose maker no longer releases security updates for them
        $unsupported = @(Get-UnsupportedProgram -Program $programs | Sort-Object -Property @{ Expression = 'Level'; Descending = $true }, Name)
        if ($unsupported.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Unsupported programs' -Status OK -Value 'None found'
        }
        else {
            $names = @($unsupported | ForEach-Object { [string]::Format([cultureinfo]::InvariantCulture, '{0} (support ended {1:yyyy-MM-dd})', $_.Name, $_.EndDate) })
            $list = ConvertTo-ListValue -Item $names -Shown 4
            $value = '{0} {1} without security updates: {2}' -f $unsupported.Count, $(if ($unsupported.Count -eq 1) { 'program' } else { 'programs' }), $list.Value

            if (@($unsupported | Where-Object { $_.Level -eq 'Warning' }).Count -gt 0) {
                New-CheckResult -Category $category -Check 'Unsupported programs' -Status Warning -Value $value -Details $list.Details `
                    -Recommendation 'These programs no longer get security updates from their maker. Replace them with a supported version or remove them (Settings > Apps > Installed apps), above all the ones that open files or pages from the internet.'
            }
            else {
                # Only runtimes that other programs brought along
                New-CheckResult -Category $category -Check 'Unsupported programs' -Status Info -Value $value -Details $list.Details `
                    -Recommendation 'These runtimes no longer get security updates. They were usually installed together with another program: update that program, and remove the runtime once nothing needs it any more.'
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Installed programs' -ErrorRecord $_
    }

    # Programs for which a newer version exists (asks winget, which asks the internet)
    if ($SkipUpdateCheck) {
        New-CheckResult -Category $category -Check 'Program updates' -Status Info -Value 'Skipped'
    }
    else {
        try {
            $available = Get-ProgramUpdate -TimeoutSeconds $thresholds.UpdateTimeoutSeconds
            if (-not $available) {
                New-CheckResult -Category $category -Check 'Program updates' -Status Info -Value 'Not checked (winget is not installed for this user)'
            }
            elseif ($available.Updates.Count -eq 0) {
                New-CheckResult -Category $category -Check 'Program updates' -Status OK -Value 'Every program winget knows is up to date' `
                    -Allowed (Format-AllowedRange -Warning $thresholds.UpdateWarningAbove) -Typical $thresholds.TypicalUpdates
            }
            else {
                # A name that ends with its version ("Contoso Edit 2.0.19") is shown without it.
                $names = @($available.Updates | Sort-Object -Property Name | ForEach-Object {
                        $name = $_.Name -replace ('\s+v?{0}$' -f [regex]::Escape($_.Version)), ''
                        '{0} {1} -> {2}' -f $name, $_.Version, $_.Available
                    })
                $list = ConvertTo-ListValue -Item $names -Shown 5
                $value = '{0} {1} can be updated: {2}' -f $names.Count, $(if ($names.Count -eq 1) { 'program' } else { 'programs' }), $list.Value

                $status = Get-ThresholdStatus -Value $names.Count -Warning $thresholds.UpdateWarningAbove
                $recommendation = if ($status -ne 'OK') {
                    'Many programs are out of date. Old versions keep security holes that are already fixed in the new ones. Update them from within each program, or all at once in a terminal with "winget upgrade --all".'
                }
                else {
                    'Newer versions exist. Update the programs from within each program, or all at once in a terminal with "winget upgrade --all".'
                }
                New-CheckResult -Category $category -Check 'Program updates' -Status $(if ($status -eq 'OK') { 'Info' } else { $status }) `
                    -Value $value -Details $list.Details -Recommendation $recommendation `
                    -Allowed (Format-AllowedRange -Warning $thresholds.UpdateWarningAbove) -Typical $thresholds.TypicalUpdates
            }
        }
        catch {
            # winget without an internet connection is not a problem of this computer.
            New-CheckResult -Category $category -Check 'Program updates' -Status Info `
                -Value ('Could not be checked: {0}' -f $_.Exception.Message.Trim())
        }
    }

    # Microsoft Office (Click-to-Run): version, update channel and whether it updates itself
    try {
        $office = Get-OfficeInstallation
        if ($office) {
            $bits = switch ($office.Platform) { 'x64' { '64-bit' } 'x86' { '32-bit' } default { '' } }
            $value = 'Version {0}{1}, {2}' -f $office.Version, $(if ($bits) { ' ({0})' -f $bits }), $office.Channel
            if ($office.UpdatesEnabled) {
                New-CheckResult -Category $category -Check 'Microsoft Office' -Status Info -Value ('{0}, automatic updates on' -f $value)
            }
            else {
                New-CheckResult -Category $category -Check 'Microsoft Office' -Status Warning -Value ('{0}, automatic updates off' -f $value) `
                    -Recommendation 'Office does not update itself, so security fixes for Word, Excel and Outlook never arrive. Turn the updates on in any Office program: File > Account > Update Options > Enable Updates. In a company the setting may come from a policy.'
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Microsoft Office' -ErrorRecord $_
    }

    # Mailbox files of Outlook. Outlook gets slow with a large file, and a file at its
    # size limit (50 GB by default) takes no new mail.
    try {
        $mailboxes = @(Get-OutlookDataFile | Sort-Object -Property Bytes -Descending)
        if ($mailboxes.Count -gt 0) {
            $outlook = (Get-HealthThreshold).Outlook
            $names = @($mailboxes | ForEach-Object { '{0} ({1})' -f $_.Name, (Format-Gigabyte -Bytes $_.Bytes) })
            $list = ConvertTo-ListValue -Item $names -Shown 3
            $value = '{0} {1}: {2}' -f $mailboxes.Count, $(if ($mailboxes.Count -eq 1) { 'file' } else { 'files' }), $list.Value

            $status = Get-ThresholdStatus -Value ($mailboxes[0].Bytes / 1GB) -Warning $outlook.WarningGb -Critical $outlook.CriticalGb
            $recommendation = switch ($status) {
                'Critical' { 'A mailbox file is close to the size limit of Outlook (50 GB); at the limit Outlook stops storing new mail. Archive or delete old mail now, empty Deleted Items, and for an Exchange account shorten "Download email for the past" (File > Account Settings > Account Settings > Change).' }
                'Warning' { 'A mailbox file this large makes Outlook slow and prone to errors. Archive or delete old mail, empty Deleted Items, and for an Exchange account shorten "Download email for the past" (File > Account Settings > Account Settings > Change).' }
                default { '' }
            }
            New-CheckResult -Category $category -Check 'Outlook data files' -Status $status -Value $value -Details $list.Details `
                -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $outlook.WarningGb -Critical $outlook.CriticalGb -Unit 'GB') -Typical $outlook.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Outlook data files' -ErrorRecord $_
    }

    # Application crashes. Event 1000 of the source "Application Error" is written every
    # time a program crashes; its first property is the name of the program.
    try {
        try {
            $filter = @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = (Get-Date).AddDays(-$Days) }
            $crashes = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
        catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                throw
            }
            $crashes = @()
        }

        $period = if ($Days -eq 1) { 'in the last day' } else { 'in the last {0} days' -f $Days }
        $byProgram = @(
            $crashes |
                Group-Object -Property { [string]$_.Properties[0].Value } |
                Sort-Object -Property Count -Descending |
                ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count }
        )

        $value = '{0} {1}' -f $crashes.Count, $period
        if ($byProgram.Count -gt 0) {
            $value = '{0}: {1}' -f $value, (($byProgram | Select-Object -First 5) -join ', ')
        }
        $remaining = @($byProgram | Select-Object -Skip 5)
        if ($remaining.Count -gt 0) {
            $value = '{0} and {1} more' -f $value, $remaining.Count
        }

        $status = Get-ThresholdStatus -Value $crashes.Count -Warning $thresholds.CrashWarningAbove
        $recommendation = if ($status -ne 'OK') {
            'Programs crash more often than usual. Update or reinstall the program at the top of the list; the details of each crash are in Event Viewer (eventvwr.msc) > Windows Logs > Application, source "Application Error".'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Application crashes' -Status $status -Value $value -Details $remaining `
            -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $thresholds.CrashWarningAbove) -Typical $thresholds.TypicalCrashes
    }
    catch {
        New-FailureResult -Category $category -Check 'Application crashes' -ErrorRecord $_
    }

    # Browser extensions. They run inside the browser and see the pages the user
    # opens, which makes them a frequent cause of slow, odd or ad-filled browsing.
    try {
        $extensions = @(Get-BrowserExtension)
        if ($extensions.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Browser extensions' -Status Info -Value 'None found'
        }
        else {
            $perBrowser = @($extensions | Group-Object -Property Browser | Sort-Object -Property Name | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count })
            $names = @($extensions | Sort-Object -Property Browser, Name | ForEach-Object { ('{0}: {1} {2}' -f $_.Browser, $_.Name, $_.Version).Trim() })
            New-CheckResult -Category $category -Check 'Browser extensions' -Status Info `
                -Value ('{0} extensions: {1}' -f $extensions.Count, ($perBrowser -join ', ')) -Details $names
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Browser extensions' -ErrorRecord $_
    }

    # Default browser. Windows can go on naming a browser that was removed; every link
    # in every program then fails with "Application not found".
    $browser = Get-DefaultBrowser
    if ($browser.IsBroken) {
        New-CheckResult -Category $category -Check 'Default browser' -Status Warning `
            -Value ('Set to a program that is no longer installed ({0})' -f $browser.ProgId) `
            -Recommendation 'Windows hands every link to a browser that is no longer on this computer, so a click on a link in another program fails with "Application not found". Choose a browser again: Settings > Apps > Default apps.'
    }
    elseif ($browser.Exists) {
        New-CheckResult -Category $category -Check 'Default browser' -Status Info -Value (Get-FileProductName -Path $browser.Path)
    }
    else {
        New-CheckResult -Category $category -Check 'Default browser' -Status Info -Value 'Not set'
    }
}
