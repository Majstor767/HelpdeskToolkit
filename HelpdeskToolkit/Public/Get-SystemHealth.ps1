function Get-SystemHealth {
    <#
    .SYNOPSIS
        Collects basic system information and checks support, uptime, stability, activation and startup programs.
    .DESCRIPTION
        Reports the computer name, operating system version and build, manufacturer
        and model, domain or workgroup, the signed-in user, the time zone and the
        Windows install date, and checks these things:

        - A Windows version that no longer receives security updates is Critical; one
          whose support ends within 90 days is a Warning. The dates are in
          Config\Thresholds.psd1.
        - A stability index (the value Reliability Monitor shows) below the limit is a
          Warning or Critical.
        - Uptime above the limit in Config\Thresholds.psd1 (7 days by default) is a
          Warning, because a long-running machine is a common cause of slowness and
          of updates that never finish installing.
        - Windows that is not activated is a Warning.
        - More startup programs that are switched on than the configured limit is a
          Warning, because they
          slow down sign-in.

        - On Windows 10: whether the computer meets the requirements of Windows 11,
          with every requirement listed.
        - The outcome of the last System File Checker run that is still on record;
          damaged files that could not be repaired are a Warning.
        - What Windows blamed for slowing down its startup (a program, a driver, a
          service); a long delay is a Warning.

        Also listed: the scheduled tasks that do not belong to Windows, the active
        power plan and whether Fast Startup is on.

        Everything is read through CIM (WMI), the registry and the logs of Windows, and
        nothing on the system is changed. Three results need administrator rights and
        are otherwise marked "Requires admin": the duration of the last measured
        startup, what delayed it, and the size of every user profile.
    .EXAMPLE
        Get-SystemHealth

        Returns one result object per check in the System category.
    .EXAMPLE
        Get-SystemHealth | Where-Object Status -ne 'Info'

        Shows only the checks that have an actual verdict (OK, Warning or Critical).
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'System'
    $thresholds = Get-HealthThreshold

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        # A broken WMI repository answers without an error and without anything in it.
        if (-not $os -or -not $computer) {
            throw 'Windows returned no information about the operating system and the computer.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'System information' -ErrorRecord $_
        return
    }

    New-CheckResult -Category $category -Check 'Computer name' -Status Info -Value $computer.Name

    $displayVersion = Get-OSDisplayVersion
    $osValue = if ($displayVersion) {
        '{0} {1} (build {2})' -f $os.Caption, $displayVersion, $os.BuildNumber
    }
    else {
        '{0} (build {1})' -f $os.Caption, $os.BuildNumber
    }
    New-CheckResult -Category $category -Check 'Operating system' -Status Info -Value $osValue

    # Does this Windows version still receive security updates?
    $support = Get-WindowsSupportInfo -Caption $os.Caption -BuildNumber $os.BuildNumber `
        -DisplayVersion $displayVersion -ProductType $os.ProductType
    New-CheckResult -Category $category -Check 'Windows support' -Status $support.Status -Value $support.Value `
        -Recommendation $support.Recommendation

    # Can this Windows 10 computer be upgraded to Windows 11? The severity of running
    # Windows 10 is in "Windows support"; this result only answers what comes next.
    if ([string]$os.Caption -match 'Windows 10') {
        try {
            $readiness = Get-Windows11Readiness
            $lines = @($readiness.Requirements | ForEach-Object {
                    $mark = if ($_.Met -eq $true) { 'yes' } elseif ($_.Met -eq $false) { 'no' } else { 'unknown' }
                    '{0}: {1} ({2})' -f $_.Name, $mark, $_.Value
                })

            if ($readiness.Ready -eq $true) {
                New-CheckResult -Category $category -Check 'Windows 11 readiness' -Status OK -Details $lines `
                    -Value 'This computer meets the requirements of Windows 11'
            }
            elseif ($readiness.Ready -eq $false) {
                $failed = @($readiness.Requirements | Where-Object { $_.Met -eq $false } | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Value })
                New-CheckResult -Category $category -Check 'Windows 11 readiness' -Status Info -Details $lines `
                    -Value ('Does not meet the requirements: {0}' -f ($failed -join '; ')) `
                    -Recommendation 'Windows 11 cannot be installed on this computer in the supported way. A TPM and Secure Boot can often be switched on in the UEFI firmware settings; a processor that is not supported or too little memory means new hardware. Until then, Extended Security Updates keep Windows 10 patched for a limited time.'
            }
            else {
                $open = @($readiness.Requirements | Where-Object { $null -eq $_.Met } | ForEach-Object { $_.Name })
                New-CheckResult -Category $category -Check 'Windows 11 readiness' -Status Info -Details $lines `
                    -Value ('Not decided, could not be found out: {0}' -f ($open -join ', ')) `
                    -Recommendation 'Start the tool as administrator, so the TPM can be read. The PC Health Check app of Microsoft gives the final answer, including the processor model.'
            }
        }
        catch {
            New-FailureResult -Category $category -Check 'Windows 11 readiness' -ErrorRecord $_
        }
    }

    if ($os.InstallDate) {
        New-CheckResult -Category $category -Check 'Windows installed' -Status Info -Value ([string]::Format([cultureinfo]::InvariantCulture, '{0:yyyy-MM-dd}', @($os.InstallDate)))
    }

    New-CheckResult -Category $category -Check 'Manufacturer and model' -Status Info `
        -Value ('{0} {1}' -f $computer.Manufacturer, $computer.Model)

    $membership = if ($computer.PartOfDomain) { 'Domain: {0}' -f $computer.Domain } else { 'Workgroup: {0}' -f $computer.Domain }
    New-CheckResult -Category $category -Check 'Domain or workgroup' -Status Info -Value $membership

    # UserName is empty in remote sessions; the environment always knows who runs the tool.
    $user = if ($computer.UserName) { $computer.UserName } else { '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME }
    New-CheckResult -Category $category -Check 'Signed-in user' -Status Info -Value $user

    New-CheckResult -Category $category -Check 'Time zone' -Status Info -Value ([System.TimeZoneInfo]::Local.DisplayName)

    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeValue = '{0} d {1} h {2} min' -f [int][math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes
    $status = Get-ThresholdStatus -Value $uptime.TotalDays -Warning $thresholds.Uptime.WarningDays
    $recommendation = if ($status -eq 'Warning') {
        'Restart the computer; it has been running for more than {0} days. Use Restart, not Shut down: with Fast Startup enabled a shutdown does not reset the uptime.' -f $thresholds.Uptime.WarningDays
    }
    else {
        ''
    }
    New-CheckResult -Category $category -Check 'Uptime' -Status $status -Value $uptimeValue -Recommendation $recommendation `
        -Allowed (Format-AllowedRange -Warning $thresholds.Uptime.WarningDays -Unit 'days') -Typical $thresholds.Uptime.Typical

    # Stability index: the number Reliability Monitor draws as its graph, from 1
    # (unstable) to 10 (stable). It drops after crashes, hangs and failed installations.
    try {
        $latest = Get-CimInstance -ClassName Win32_ReliabilityStabilityMetrics -ErrorAction Stop |
            Select-Object -First 24 |
            Sort-Object -Property TimeGenerated -Descending |
            Select-Object -First 1

        if (-not $latest) {
            New-CheckResult -Category $category -Check 'Stability index' -Status Info -Value 'Not available'
        }
        else {
            $index = [math]::Round([double]$latest.SystemStabilityIndex, 1)
            $status = Get-ThresholdStatus -Value $index -LowerIsWorse `
                -Warning $thresholds.Stability.WarningIndex -Critical $thresholds.Stability.CriticalIndex
            $recommendation = if ($status -ne 'OK') {
                'Windows has recorded many crashes or failures lately. Open Reliability Monitor (run "perfmon /rel") to see which program or device caused them and on which days.'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Stability index' -Status $status `
                -Value ('{0} of 10' -f [string]$index) -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Stability.WarningIndex -Critical $thresholds.Stability.CriticalIndex -LowerIsWorse -Maximum 10) `
                -Typical $thresholds.Stability.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Stability index' -ErrorRecord $_
    }

    # Activation. The filter selects the Windows license that has a product key installed;
    # LicenseStatus 1 means licensed.
    try {
        $filter = "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL"
        $license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter $filter -ErrorAction Stop | Select-Object -First 1

        if ($license -and $license.LicenseStatus -eq 1) {
            New-CheckResult -Category $category -Check 'Windows activation' -Status OK -Value 'Activated'
        }
        else {
            New-CheckResult -Category $category -Check 'Windows activation' -Status Warning -Value 'Not activated' `
                -Recommendation 'Windows is not activated. Open Settings > System > Activation to see the reason and activate it.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Windows activation' -ErrorRecord $_
    }

    # Startup programs: what is set to start at sign-in, and what of it is switched on
    # (see Get-StartupProgram). Only what is switched on counts.
    try {
        $startup = @(Get-StartupProgram)
        $enabled = @($startup | Where-Object { $_.Enabled } | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
        $disabled = @($startup | Where-Object { -not $_.Enabled } | ForEach-Object { [string]$_.Name } | Where-Object { $enabled -notcontains $_ } | Sort-Object -Unique)

        $value = '{0} {1} with Windows' -f $enabled.Count, $(if ($enabled.Count -eq 1) { 'program starts' } else { 'programs start' })
        if ($disabled.Count -gt 0) {
            $value = '{0}, {1} more turned off' -f $value, $disabled.Count
        }
        # Every program is a line of the details: the window makes each of them a
        # switch (see Switch-WindowStartupProgram), the reports list them.
        $names = @($enabled) + @($disabled | ForEach-Object { '{0} (turned off)' -f $_ })

        $status = Get-ThresholdStatus -Value $enabled.Count -Warning $thresholds.Startup.WarningProgramCount
        $recommendation = if ($status -ne 'OK') {
            'Many programs start together with Windows, which slows down sign-in. Turn off the ones that are not needed: open the list and click a program, or use Task Manager > Startup apps.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Startup programs' -Status $status -Value $value -Recommendation $recommendation `
            -Details $names -Allowed (Format-AllowedRange -Warning $thresholds.Startup.WarningProgramCount) -Typical $thresholds.Startup.Typical
    }
    catch {
        New-FailureResult -Category $category -Check 'Startup programs' -ErrorRecord $_
    }

    # Scheduled tasks that do not belong to Windows
    try {
        $tasks = @(Get-ThirdPartyTask | Sort-Object -Property Name |
                ForEach-Object { if ($_.Enabled) { $_.Name } else { '{0} (disabled)' -f $_.Name } })
        $list = ConvertTo-ListValue -Item $tasks -Label 'task' -Shown 6
        New-CheckResult -Category $category -Check 'Scheduled tasks' -Status Info -Value $list.Value -Details $list.Details
    }
    catch {
        New-FailureResult -Category $category -Check 'Scheduled tasks' -ErrorRecord $_
    }

    # Power plan and Fast Startup
    $plan = Get-PowerPlanName
    New-CheckResult -Category $category -Check 'Power plan' -Status Info -Value $(if ($plan) { $plan } else { 'Unknown' })

    # HiberbootEnabled = 1: "Shut down" saves the core of Windows to disk instead of
    # ending it, so the next start is faster but not a fresh one.
    $fastStartup = Get-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled'
    $fastStartupValue = if ($null -eq $fastStartup) { 'Unknown' } elseif ($fastStartup -eq 1) { 'Enabled' } else { 'Disabled' }
    New-CheckResult -Category $category -Check 'Fast Startup' -Status Info -Value $fastStartupValue

    # Outcome of the last "sfc /scannow" that is still in the servicing log
    try {
        $fileCheck = Get-SystemFileCheckResult
        if (-not $fileCheck) {
            New-CheckResult -Category $category -Check 'System file check' -Status Info -Value 'No check on record'
        }
        else {
            switch ($fileCheck.Verdict) {
                'Unrepaired' {
                    New-CheckResult -Category $category -Check 'System file check' -Status Warning `
                        -Value ([string]::Format([cultureinfo]::InvariantCulture, 'Damaged files could not be repaired (checked {0:yyyy-MM-dd})', @($fileCheck.CheckedAt))) `
                        -Recommendation 'Files of Windows are damaged and the System File Checker could not repair them. Open a terminal as administrator and run "DISM /Online /Cleanup-Image /RestoreHealth", then "sfc /scannow" again.'
                }
                'Repaired' {
                    New-CheckResult -Category $category -Check 'System file check' -Status Info `
                        -Value ([string]::Format([cultureinfo]::InvariantCulture, 'Damaged files were found and repaired (checked {0:yyyy-MM-dd})', @($fileCheck.CheckedAt))) `
                        -Recommendation 'Files of Windows were damaged and have been repaired. When that happens again, test the drive and the memory: damaged system files often come from failing hardware or from switching the computer off the hard way.'
                }
                default {
                    New-CheckResult -Category $category -Check 'System file check' -Status OK `
                        -Value ([string]::Format([cultureinfo]::InvariantCulture, 'No damaged files (checked {0:yyyy-MM-dd})', @($fileCheck.CheckedAt)))
                }
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'System file check' -ErrorRecord $_
    }

    # Checks that Windows only allows for administrators.
    if (-not (Test-IsAdministrator)) {
        New-AdminRequiredResult -Category $category -Check 'Last startup duration'
        New-AdminRequiredResult -Category $category -Check 'Startup delays'
        New-AdminRequiredResult -Category $category -Check 'User profiles'
        return
    }

    # How long Windows needed to start, the last time it measured it.
    try {
        $boot = Get-LastBootDuration
        if (-not $boot) {
            New-CheckResult -Category $category -Check 'Last startup duration' -Status Info -Value 'No measurement recorded'
        }
        else {
            $value = [string]::Format([cultureinfo]::InvariantCulture, '{0} seconds (measured {1:yyyy-MM-dd})', $boot.Seconds, $boot.MeasuredAt)
            $allowed = Format-AllowedRange -Warning $thresholds.Boot.WarningSeconds -Unit 'seconds'
            $ageDays = ((Get-Date) - $boot.MeasuredAt).TotalDays

            if ($ageDays -gt $thresholds.Boot.StaleDays) {
                # An old measurement says little about the computer as it is today.
                New-CheckResult -Category $category -Check 'Last startup duration' -Status Info -Value $value `
                    -Allowed $allowed -Typical $thresholds.Boot.Typical
            }
            else {
                $status = Get-ThresholdStatus -Value $boot.Seconds -Warning $thresholds.Boot.WarningSeconds
                $recommendation = if ($status -ne 'OK') {
                    'Windows starts slowly. Turn off startup programs that are not needed (Task Manager > Startup apps); if the system drive is a hard disk, replacing it with an SSD helps the most.'
                }
                else {
                    ''
                }
                New-CheckResult -Category $category -Check 'Last startup duration' -Status $status -Value $value `
                    -Recommendation $recommendation -Allowed $allowed -Typical $thresholds.Boot.Typical
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Last startup duration' -ErrorRecord $_
    }

    # What Windows blamed for a slow startup. The same culprit usually shows up at
    # several startups, so the delays are averaged per culprit.
    try {
        $days = $thresholds.Boot.StaleDays
        $delays = @(Get-BootDegradation -Since (Get-Date).AddDays(-$days) | Where-Object { $_.Milliseconds -gt 0 })
        if ($delays.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Startup delays' -Status OK -Value ('Nothing slowed the startup in the last {0} days' -f $days)
        }
        else {
            $culprits = @($delays | Group-Object -Property Kind, Name | ForEach-Object {
                    [PSCustomObject]@{
                        Name    = $_.Group[0].Name
                        Kind    = $_.Group[0].Kind
                        Seconds = [int][math]::Max(1, [math]::Round(($_.Group | Measure-Object -Property Milliseconds -Average).Average / 1000))
                        Count   = $_.Count
                    }
                } | Sort-Object -Property Seconds -Descending)

            $names = @($culprits | ForEach-Object { '{0} ({1}, {2} s)' -f $_.Name, $_.Kind, $_.Seconds })
            $list = ConvertTo-ListValue -Item $names -Shown 4
            $value = '{0} {1} in the last {2} days: {3}' -f $culprits.Count, $(if ($culprits.Count -eq 1) { 'culprit' } else { 'culprits' }), $days, $list.Value

            $status = Get-ThresholdStatus -Value $culprits[0].Seconds -Warning $thresholds.Boot.DelayWarningSeconds
            $recommendation = if ($status -ne 'OK') {
                'Windows names what held up its startup. A program: turn it off in Task Manager > Startup apps or update it. A driver or a device: install the current driver from the manufacturer. A service: check in services.msc whether it is needed at startup.'
            }
            else {
                ''
            }
            # Short delays are listed for information only.
            New-CheckResult -Category $category -Check 'Startup delays' -Status $(if ($status -eq 'OK') { 'Info' } else { $status }) `
                -Value $value -Details $list.Details -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Boot.DelayWarningSeconds -Unit 'seconds')
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Startup delays' -ErrorRecord $_
    }

    # Size of every user profile. "Special" profiles belong to Windows itself.
    try {
        $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
                Where-Object { -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath) })

        $sizes = @(
            foreach ($userProfile in $profiles) {
                $size = Get-FolderSize -Path $userProfile.LocalPath -TimeoutMs $thresholds.Cleanup.ProfileTimeoutMs
                [PSCustomObject]@{
                    Name     = Split-Path -Path $userProfile.LocalPath -Leaf
                    Bytes    = $size.Bytes
                    Complete = $size.Complete
                }
            }
        )

        $text = @($sizes | Sort-Object -Property Bytes -Descending | ForEach-Object {
                '{0} {1}{2}' -f $_.Name, (Format-Gigabyte -Bytes $_.Bytes), $(if (-not $_.Complete) { ' or more' })
            })
        $value = if ($text.Count -gt 0) { '{0} profiles: {1}' -f $text.Count, ($text -join ', ') } else { 'No user profiles found' }
        New-CheckResult -Category $category -Check 'User profiles' -Status Info -Value $value
    }
    catch {
        New-FailureResult -Category $category -Check 'User profiles' -ErrorRecord $_
    }
}
