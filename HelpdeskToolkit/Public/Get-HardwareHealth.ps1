function Get-HardwareHealth {
    <#
    .SYNOPSIS
        Checks CPU load, memory usage, free disk space and the battery.
    .DESCRIPTION
        Reads everything through CIM (WMI) and changes nothing on the system:

        - CPU load at the time of the check
        - used physical memory and the five programs that use the most of it
        - health reported by every physical drive (SSD/HDD)
        - space that could be freed: temporary files, the Downloads folder and the Recycle Bin
        - what takes up the space on a disk that is running full, and the size of the
          hibernation file
        - page file usage
        - devices without a working driver, unsigned drivers and old drivers
        - the result of the last memory test (Windows Memory Diagnostic) on record
        - how much of its original capacity the battery still has

        Three checks need administrator rights and are otherwise marked "Requires
        admin": the details every drive reports about itself (temperature, wear,
        power-on hours, uncorrected errors), drives flagged for a disk check and the
        size of the temporary files of Windows.
        - free space on every local fixed disk, with the drive Windows is installed on
          marked as such; a full data drive gets other advice than a full Windows drive
        - battery charge, when the computer has a battery

        The limits for Warning and Critical come from Config\Thresholds.psd1.
    .PARAMETER LoadSample
        Processor load, memory and running programs as they were measured a moment
        ago. Get-PCHealthReport hands this in when it runs the categories side by
        side: measured during that time, the load would be the one of the check
        itself. Without it the values are measured by this command.
    .PARAMETER AllowCached
        Use what was measured earlier in this process for the things that take long
        and change slowly: the largest folders of a drive that is running full, when
        they were measured within the time set in Config\Thresholds.psd1. The window
        uses this for the checks it repeats by itself. Without the switch everything
        is measured anew.
    .EXAMPLE
        Get-HardwareHealth

        Returns one result per check, including one per local disk.
    .EXAMPLE
        Get-HardwareHealth | Where-Object Check -like 'Disk*'

        Shows only the disk space results.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [PSCustomObject]$LoadSample,

        [switch]$AllowCached
    )

    $category = 'Hardware'
    $thresholds = Get-HealthThreshold

    # What was measured earlier, when it was handed in; otherwise it is measured here.
    $sampledProcessors = @(if ($LoadSample) { $LoadSample.Processors })
    $sampledSystem = if ($LoadSample) { $LoadSample.OperatingSystem }
    $sampledProcesses = @(if ($LoadSample) { $LoadSample.Processes })

    # CPU. Win32_Processor is used instead of performance counters because counter
    # names are translated on non-English Windows and would break the query.
    try {
        $processors = @($sampledProcessors | Where-Object { $_ })
        if ($processors.Count -eq 0) {
            $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
        }
        $loads = @($processors | Where-Object { $null -ne $_.LoadPercentage } | ForEach-Object { $_.LoadPercentage })

        if ($loads.Count -eq 0) {
            New-CheckResult -Category $category -Check 'CPU load' -Status Info -Value 'Unavailable'
        }
        else {
            $load = [int][math]::Round(($loads | Measure-Object -Average).Average)
            $status = Get-ThresholdStatus -Value $load -Warning $thresholds.Cpu.WarningPercent -Critical $thresholds.Cpu.CriticalPercent
            $recommendation = if ($status -ne 'OK') {
                'CPU load was high at the time of the check. Open Task Manager (Ctrl+Shift+Esc) and look for the process using the most CPU.'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'CPU load' -Status $status `
                -Value ('{0} % ({1})' -f $load, ([string]$processors[0].Name).Trim()) -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Cpu.WarningPercent -Critical $thresholds.Cpu.CriticalPercent -Unit '%') `
                -Typical $thresholds.Cpu.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'CPU load' -ErrorRecord $_
    }

    # Memory. Both values are reported by WMI in kilobytes.
    try {
        $os = $sampledSystem
        if (-not $os) {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        }
        $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
        $usedBytes = $totalBytes - ([double]$os.FreePhysicalMemory * 1KB)
        $usedPercent = [int][math]::Round($usedBytes / $totalBytes * 100)

        $status = Get-ThresholdStatus -Value $usedPercent -Warning $thresholds.Memory.WarningPercent -Critical $thresholds.Memory.CriticalPercent
        $recommendation = if ($status -ne 'OK') {
            'Memory is almost full. Close unused applications and browser tabs; if this happens regularly, the computer needs more RAM.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Memory usage' -Status $status `
            -Value ('{0} % ({1} of {2} used)' -f $usedPercent, (Format-Gigabyte -Bytes $usedBytes), (Format-Gigabyte -Bytes $totalBytes)) `
            -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $thresholds.Memory.WarningPercent -Critical $thresholds.Memory.CriticalPercent -Unit '%') `
            -Typical $thresholds.Memory.Typical
    }
    catch {
        New-FailureResult -Category $category -Check 'Memory usage' -ErrorRecord $_
    }

    # Which programs hold the memory. Processes are grouped by name because browsers
    # and similar applications run as many processes.
    try {
        $processes = @($sampledProcesses | Where-Object { $_ })
        if ($processes.Count -eq 0) {
            $processes = @(Get-Process -ErrorAction Stop)
        }
        $consumers = @(
            $processes |
                Group-Object -Property ProcessName |
                ForEach-Object {
                    [PSCustomObject]@{
                        Name  = $_.Name
                        Bytes = ($_.Group | Measure-Object -Property WorkingSet64 -Sum).Sum
                    }
                } |
                Sort-Object -Property Bytes -Descending |
                Select-Object -First 5 |
                ForEach-Object { '{0} ({1})' -f $_.Name, (Format-Gigabyte -Bytes $_.Bytes) }
        )
        New-CheckResult -Category $category -Check 'Top memory consumers' -Status Info -Value ($consumers -join ', ')
    }
    catch {
        New-FailureResult -Category $category -Check 'Top memory consumers' -ErrorRecord $_
    }

    # Physical drives and the health state they report themselves (based on SMART).
    # The numbers are read with Get-CimPropertyValue: once the Storage module of
    # Windows is loaded in the process, $drive.HealthStatus is the text "Healthy".
    try {
        $mediaTypes = @{ 3 = 'HDD'; 4 = 'SSD' }
        $busTypes = @{ 7 = 'USB'; 11 = 'SATA'; 17 = 'NVMe' }
        $drives = @(Get-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop)

        foreach ($drive in $drives) {
            $media = $mediaTypes[[int](Get-CimPropertyValue -InputObject $drive -Name MediaType)]
            $bus = $busTypes[[int](Get-CimPropertyValue -InputObject $drive -Name BusType)]
            $kind = (@($media, $bus) | Where-Object { $_ }) -join ', '
            if (-not $kind) {
                $kind = 'Unknown type'
            }

            switch ([int](Get-CimPropertyValue -InputObject $drive -Name HealthStatus)) {
                0 { $status = 'OK'; $health = 'Healthy' }
                1 { $status = 'Warning'; $health = 'Warning' }
                2 { $status = 'Critical'; $health = 'Unhealthy' }
                default { $status = 'Info'; $health = 'Unknown' }
            }
            $recommendation = if ($status -in 'Warning', 'Critical') {
                'The drive reports a problem and may fail. Back up the data now and plan to replace the drive.'
            }
            else {
                ''
            }

            New-CheckResult -Category $category -Check ('Drive: {0}' -f $drive.FriendlyName) -Status $status `
                -Value ('{0}, {1}, health: {2}' -f $kind, (Format-Gigabyte -Bytes $drive.Size), $health) `
                -Recommendation $recommendation
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Drive health' -ErrorRecord $_
    }

    # Disks. DriveType 3 = local fixed disk (no USB sticks, network or optical drives).
    $lowDisks = @()
    try {
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop)
        foreach ($disk in $disks) {
            $check = 'Disk ({0})' -f $disk.DeviceID

            # The drive Windows is installed on is a different matter than a data drive:
            # when it runs full, Windows itself is in trouble. The result says which one
            # it is (", Windows drive" at the end of the value), and the explanation, the
            # reason why a full drive matters and the advice are chosen to fit.
            $isWindowsDrive = [string]$disk.DeviceID -eq [string]$env:SystemDrive
            $description = if ($isWindowsDrive) { Get-CheckDescription -Key 'Disk:Windows drive' } else { '' }

            if (-not $disk.Size) {
                New-CheckResult -Category $category -Check $check -Status Info -Value 'Size unknown' -Description $description
                continue
            }

            $freePercent = [math]::Round([double]$disk.FreeSpace / [double]$disk.Size * 100, 1)
            $status = Get-ThresholdStatus -Value $freePercent -LowerIsWorse `
                -Warning $thresholds.Disk.WarningFreePercent -Critical $thresholds.Disk.CriticalFreePercent
            if ($status -ne 'OK') {
                $lowDisks += [string]$disk.DeviceID
            }
            $recommendation = switch ($status) {
                'Critical' {
                    if ($isWindowsDrive) {
                        'The disk is almost full. Free up space now: Windows updates and applications can fail without free space.'
                    }
                    else {
                        'This drive is almost full, so nothing more can be saved on it. Windows is not installed here and keeps working; move files to another drive or delete what is no longer needed.'
                    }
                }
                'Warning' {
                    if ($isWindowsDrive) {
                        'Free space is low. Run Disk Cleanup, empty the Recycle Bin and remove programs and files that are no longer needed.'
                    }
                    else {
                        'Free space on this drive is low. Move files to another drive or delete what is no longer needed, and empty the Recycle Bin.'
                    }
                }
                default { '' }
            }
            $value = '{0} % free ({1} of {2})' -f [string]$freePercent, (Format-Gigabyte -Bytes $disk.FreeSpace), (Format-Gigabyte -Bytes $disk.Size)
            if ($isWindowsDrive) {
                $value = '{0}, Windows drive' -f $value
            }
            New-CheckResult -Category $category -Check $check -Status $status -Value $value -Description $description `
                -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Disk.WarningFreePercent -Critical $thresholds.Disk.CriticalFreePercent -Unit '% free' -LowerIsWorse) `
                -Typical $thresholds.Disk.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Disk space' -ErrorRecord $_
    }

    # What takes up the space, for every disk that is running full. Measuring takes a
    # while, so it is only done where the answer is needed.
    $cleanup = $thresholds.Cleanup

    foreach ($letter in $lowDisks) {
        $check = 'Largest folders ({0})' -f $letter
        try {
            # Walking through a whole drive takes seconds and its result changes slowly.
            # A check that is repeated by itself may use what was measured a while ago
            # in this process (see Get-ProcessCache); a check somebody asked for measures.
            $cacheKey = 'LargestFolders:{0}' -f $letter
            $folders = $null
            $cached = if ($AllowCached) { Get-ProcessCache -Key $cacheKey -MaxAgeMinutes $cleanup.LargestFolderCacheMinutes }
            if ($cached) {
                $folders = @($cached.Value)
            }
            else {
                $folders = @(Get-LargestFolder -Path ('{0}\' -f $letter) -BudgetMs $cleanup.LargestFolderBudgetMs)
                Set-ProcessCache -Key $cacheKey -Value $folders
            }
            $largest = @($folders |
                    Select-Object -First 15 |
                    ForEach-Object { '{0} {1}{2}' -f $_.Name, (Format-Gigabyte -Bytes $_.Bytes), $(if (-not $_.Complete) { ' or more' }) })

            if ($largest.Count -eq 0) {
                New-CheckResult -Category $category -Check $check -Status Info -Value 'Nothing could be measured'
            }
            else {
                $list = ConvertTo-ListValue -Item $largest -Shown 6
                # The folders of Windows are only on the drive Windows is installed on.
                $recommendation = if ([string]$letter -eq [string]$env:SystemDrive) {
                    'This is where the space of the disk goes. Start cleaning up with the largest folders that hold your own files (Downloads, Videos, Desktop); do not delete anything inside Windows, Program Files or ProgramData by hand. "Or more" means the folder was too large to be measured completely in the time allowed.'
                }
                else {
                    'This is where the space of the drive goes. Start cleaning up with the largest folders that hold your own files; a folder that belongs to an installed program or a game is removed by uninstalling it, not by deleting the folder. "Or more" means the folder was too large to be measured completely in the time allowed.'
                }
                New-CheckResult -Category $category -Check $check -Status Info -Value $list.Value -Details $list.Details -Recommendation $recommendation
            }
        }
        catch {
            New-FailureResult -Category $category -Check $check -ErrorRecord $_
        }
    }

    # Space that could be freed. These three places are where a full disk is usually
    # recovered first, so their sizes are reported next to the free space.
    try {
        $temp = Get-FolderSize -Path $env:TEMP -TimeoutMs $cleanup.TimeoutMs
        $status = Get-ThresholdStatus -Value ($temp.Bytes / 1GB) -Warning $cleanup.TempWarningGb
        $recommendation = if ($status -ne 'OK') {
            'Temporary files take up a lot of space. Remove them in Settings > System > Storage > Temporary files.'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Temporary files' -Status $status `
            -Value ('{0}{1}' -f (Format-Gigabyte -Bytes $temp.Bytes), $(if (-not $temp.Complete) { ' or more' })) `
            -Recommendation $recommendation -Allowed (Format-AllowedRange -Warning $cleanup.TempWarningGb -Unit 'GB')

        $downloads = Join-Path -Path $env:USERPROFILE -ChildPath 'Downloads'
        if (Test-Path -LiteralPath $downloads) {
            $size = Get-FolderSize -Path $downloads -TimeoutMs $cleanup.TimeoutMs
            New-CheckResult -Category $category -Check 'Downloads folder' -Status Info `
                -Value ('{0}{1} in {2} files' -f (Format-Gigabyte -Bytes $size.Bytes), $(if (-not $size.Complete) { ' or more' }), $size.FileCount)
        }

        $bin = Get-RecycleBinSize -TimeoutMs $cleanup.TimeoutMs
        $status = Get-ThresholdStatus -Value ($bin.Bytes / 1GB) -Warning $cleanup.RecycleBinWarningGb
        $recommendation = if ($status -ne 'OK') {
            'Deleted files still take up a lot of space. Right-click the Recycle Bin on the desktop and choose "Empty Recycle Bin".'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Recycle Bin' -Status $status `
            -Value ('{0}{1}' -f (Format-Gigabyte -Bytes $bin.Bytes), $(if (-not $bin.Complete) { ' or more' })) `
            -Recommendation $recommendation -Allowed (Format-AllowedRange -Warning $cleanup.RecycleBinWarningGb -Unit 'GB')

        # Hibernation file: Windows saves the memory into it for hibernation and for
        # Fast Startup. It is about as large as 40 % of the RAM or more.
        $hibernation = Get-ChildItem -LiteralPath ('{0}\' -f $env:SystemDrive) -Filter 'hiberfil.sys' -File -Force -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $hibernation) {
            New-CheckResult -Category $category -Check 'Hibernation file' -Status Info -Value 'Not present (hibernation is off)'
        }
        else {
            # The advice is only given where space is short.
            $recommendation = if ($lowDisks -contains $env:SystemDrive) {
                'The system disk is short of space and this file takes up a good part of it. On a computer that is never put into hibernation, an administrator can remove the file with "powercfg /hibernate off"; this also turns off Fast Startup, so starting Windows takes a little longer.'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Hibernation file' -Status Info -Value (Format-Gigabyte -Bytes $hibernation.Length) -Recommendation $recommendation
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Space that can be freed' -ErrorRecord $_
    }

    # Page file: the file Windows uses as extra memory when the RAM is full.
    try {
        $pageFiles = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
        $allocatedMb = if ($pageFiles.Count -gt 0) { ($pageFiles | Measure-Object -Property AllocatedBaseSize -Sum).Sum } else { 0 }
        if (-not $allocatedMb) {
            New-CheckResult -Category $category -Check 'Page file' -Status Info -Value 'No page file'
        }
        else {
            $usedMb = ($pageFiles | Measure-Object -Property CurrentUsage -Sum).Sum
            $usedPercent = [int][math]::Round($usedMb / $allocatedMb * 100)
            $status = Get-ThresholdStatus -Value $usedPercent -Warning $thresholds.PageFile.WarningPercent
            $recommendation = if ($status -ne 'OK') {
                'The page file is almost full, which means the computer regularly runs out of memory. Close programs that are not needed; if it keeps happening, the computer needs more RAM.'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'Page file' -Status $status `
                -Value ('{0} % ({1} MB of {2} MB used)' -f $usedPercent, $usedMb, $allocatedMb) -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.PageFile.WarningPercent -Unit '%') -Typical $thresholds.PageFile.Typical
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Page file' -ErrorRecord $_
    }

    # Checks that Windows only allows for administrators. Without elevation they are
    # not attempted at all, because some of these queries wait several seconds before
    # they fail, and one of them simply returns nothing instead of an error.
    if (-not (Test-IsAdministrator)) {
        New-AdminRequiredResult -Category $category -Check 'Drive details'
        New-AdminRequiredResult -Category $category -Check 'File system'
        New-AdminRequiredResult -Category $category -Check 'System temporary files'
    }
    else {
        # What every drive measures about itself (SMART)
        try {
            $limits = $thresholds.DriveDetail
            $degrees = '{0}C' -f [char]176
            foreach ($drive in Get-DriveReliability) {
                $parts = @()
                $statuses = @()
                $advice = @()

                if ($drive.Temperature) {
                    $parts += '{0} {1}' -f $drive.Temperature, $degrees
                    $state = Get-ThresholdStatus -Value $drive.Temperature -Warning $limits.TemperatureWarning -Critical $limits.TemperatureCritical
                    if ($state -ne 'OK') {
                        $statuses += $state
                        $advice += 'The drive is too hot. Clean the dust out of the computer and make sure the air can flow; heat shortens the life of a drive.'
                    }
                }
                if ($null -ne $drive.Wear) {
                    $parts += '{0} % of its lifetime used' -f $drive.Wear
                    $state = Get-ThresholdStatus -Value $drive.Wear -Warning $limits.WearWarningPercent -Critical $limits.WearCriticalPercent
                    if ($state -ne 'OK') {
                        $statuses += $state
                        $advice += 'The drive is close to the end of its rated lifetime. Back up the data and plan to replace it.'
                    }
                }
                if ($drive.PowerOnHours) {
                    $parts += '{0} hours powered on' -f $drive.PowerOnHours
                }
                if ($null -ne $drive.ReadErrors -or $null -ne $drive.WriteErrors) {
                    $errors = [long]$drive.ReadErrors + [long]$drive.WriteErrors
                    $parts += '{0} uncorrected errors' -f $errors
                    if ($errors -gt 0) {
                        $statuses += 'Warning'
                        $advice += 'The drive could not read or write some data. Back up the data now; a drive with uncorrected errors is likely to fail.'
                    }
                }

                $status = if ($statuses -contains 'Critical') { 'Critical' } elseif ($statuses -contains 'Warning') { 'Warning' } elseif ($parts.Count -gt 0) { 'OK' } else { 'Info' }
                $value = if ($parts.Count -gt 0) { $parts -join ', ' } else { 'The drive reports no details' }

                New-CheckResult -Category $category -Check ('Drive details: {0}' -f $drive.Name) -Status $status -Value $value `
                    -Recommendation ($advice -join ' ') `
                    -Allowed ('temperature up to {0} {1}, lifetime used up to {2} %, 0 uncorrected errors' -f $limits.TemperatureWarning, $degrees, $limits.WearWarningPercent) `
                    -Typical ('{0} {1}' -f $limits.TypicalTemperature, $degrees)
            }
        }
        catch {
            New-FailureResult -Category $category -Check 'Drive details' -ErrorRecord $_
        }

        # File system: Windows sets a "dirty" flag on a volume that may be damaged.
        try {
            $volumes = @(Get-CimInstance -ClassName Win32_Volume -Filter 'DriveType = 3' -ErrorAction Stop | Where-Object { $_.DriveLetter })
            $flagged = @($volumes | Where-Object { $_.DirtyBitSet } | ForEach-Object { $_.DriveLetter })

            if ($flagged.Count -gt 0) {
                New-CheckResult -Category $category -Check 'File system' -Status Warning `
                    -Value ('Possible errors on {0}' -f ($flagged -join ', ')) `
                    -Recommendation 'Windows has flagged the drive for a disk check. Restart the computer and let the check run, or run "chkdsk /scan" for that drive as administrator.'
            }
            else {
                New-CheckResult -Category $category -Check 'File system' -Status OK `
                    -Value ('No errors flagged ({0})' -f (($volumes | ForEach-Object { $_.DriveLetter } | Sort-Object) -join ', '))
            }
        }
        catch {
            New-FailureResult -Category $category -Check 'File system' -ErrorRecord $_
        }

        # Temporary files of Windows itself
        try {
            $systemTemp = Get-FolderSize -Path (Join-Path -Path $env:WINDIR -ChildPath 'Temp') -TimeoutMs $cleanup.TimeoutMs
            $status = Get-ThresholdStatus -Value ($systemTemp.Bytes / 1GB) -Warning $cleanup.SystemTempWarningGb
            $recommendation = if ($status -ne 'OK') {
                'Windows has collected a lot of temporary files. Run Disk Cleanup (cleanmgr) and choose "Clean up system files".'
            }
            else {
                ''
            }
            New-CheckResult -Category $category -Check 'System temporary files' -Status $status `
                -Value ('{0}{1}' -f (Format-Gigabyte -Bytes $systemTemp.Bytes), $(if (-not $systemTemp.Complete) { ' or more' })) `
                -Recommendation $recommendation -Allowed (Format-AllowedRange -Warning $cleanup.SystemTempWarningGb -Unit 'GB')
        }
        catch {
            New-FailureResult -Category $category -Check 'System temporary files' -ErrorRecord $_
        }
    }

    # Devices that Device Manager marks with a yellow warning sign. Error code 0 means
    # the device works; code 22 means it was disabled on purpose, which is not a fault.
    try {
        $devices = @(Get-CimInstance -ClassName Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 22' -ErrorAction Stop)
        if ($devices.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Devices with problems' -Status OK -Value 'None'
        }
        else {
            $names = @($devices | ForEach-Object {
                    $name = if ($_.Name) { $_.Name } else { 'Unknown device' }
                    '{0} (code {1})' -f $name, $_.ConfigManagerErrorCode
                })
            $shown = 5
            $remaining = @($names | Select-Object -Skip $shown)
            $value = '{0} devices: {1}' -f $devices.Count, (($names | Select-Object -First $shown) -join ', ')
            if ($remaining.Count -gt 0) {
                $value = '{0} and {1} more' -f $value, $remaining.Count
            }
            New-CheckResult -Category $category -Check 'Devices with problems' -Status Warning -Value $value -Details $remaining `
                -Recommendation 'These devices have no working driver. Open Device Manager (devmgmt.msc), find the devices with a yellow mark and install the driver from Windows Update or from the web site of the manufacturer.'
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Devices with problems' -ErrorRecord $_
    }

    # Drivers. A driver without a valid signature may have been altered; an old driver of
    # a graphics card, network adapter or sound card is a common cause of crashes.
    try {
        $drivers = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $_.DeviceName })

        $unsigned = @($drivers | Where-Object { $_.IsSigned -eq $false } | ForEach-Object { [string]$_.DeviceName } | Sort-Object -Unique)
        if ($unsigned.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Unsigned drivers' -Status OK -Value 'None'
        }
        else {
            $list = ConvertTo-ListValue -Item $unsigned -Label 'driver'
            New-CheckResult -Category $category -Check 'Unsigned drivers' -Status Warning -Value $list.Value -Details $list.Details `
                -Recommendation 'These drivers carry no valid digital signature, so nobody vouches that they are unchanged. Replace them with the current driver from Windows Update or from the web site of the device maker.'
        }

        # Chipset drivers of some makers carry a symbolic date decades in the past;
        # dates before 2006 are therefore not taken as real.
        $limits = $thresholds.Drivers
        $oldBefore = (Get-Date).AddYears(-$limits.OldYears)
        $old = @(
            $drivers |
                Where-Object {
                    $_.DriverProviderName -and $_.DriverProviderName -notlike 'Microsoft*' -and
                    $limits.Classes -contains $_.DeviceClass -and
                    $_.DriverDate -and $_.DriverDate.Year -ge 2006 -and $_.DriverDate -lt $oldBefore
                } |
                Sort-Object -Property DriverDate |
                ForEach-Object { [string]::Format([cultureinfo]::InvariantCulture, '{0} ({1:yyyy-MM-dd})', $_.DeviceName, $_.DriverDate) } |
                Select-Object -Unique
        )
        if ($old.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Old drivers' -Status Info -Value ('None older than {0} years' -f $limits.OldYears)
        }
        else {
            $list = ConvertTo-ListValue -Item $old -Label 'driver'
            New-CheckResult -Category $category -Check 'Old drivers' -Status Info -Value $list.Value -Details $list.Details `
                -Recommendation ('These drivers are older than {0} years. An old driver that works needs no attention; when the device misbehaves, installing the current driver from the maker is the first thing to try.' -f $limits.OldYears)
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Drivers' -ErrorRecord $_
    }

    # Result of the last memory test (Windows Memory Diagnostic), when one is on record
    try {
        $memoryTest = Get-MemoryDiagnosticResult
        if (-not $memoryTest) {
            New-CheckResult -Category $category -Check 'Memory test' -Status Info -Value 'No test on record'
        }
        elseif ($memoryTest.HasErrors) {
            New-CheckResult -Category $category -Check 'Memory test' -Status Critical `
                -Value ([string]::Format([cultureinfo]::InvariantCulture, 'Errors found (tested {0:yyyy-MM-dd})', @($memoryTest.TestedAt))) `
                -Recommendation 'Windows Memory Diagnostic found faulty memory. Test the modules one at a time to find the bad one and replace it; until then crashes and damaged files are to be expected.'
        }
        else {
            New-CheckResult -Category $category -Check 'Memory test' -Status OK -Value ([string]::Format([cultureinfo]::InvariantCulture, 'No errors (tested {0:yyyy-MM-dd})', @($memoryTest.TestedAt)))
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Memory test' -ErrorRecord $_
    }

    # Battery. Desktops simply have no Win32_Battery instance.
    try {
        $batteries = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
        if ($batteries.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Battery' -Status Info -Value 'No battery (desktop computer)'
        }

        foreach ($battery in $batteries) {
            # BatteryStatus 1, 4 and 5 mean the computer is running on battery power.
            $onBattery = $battery.BatteryStatus -in 1, 4, 5

            # Some batteries do not tell their charge (the firmware reports nothing, or
            # more than 100). No charge that was read must not look like an empty battery.
            $reported = $battery.EstimatedChargeRemaining
            if ($null -eq $reported -or [int]$reported -lt 0 -or [int]$reported -gt 100) {
                $power = if ($onBattery) { 'on battery' } else { 'plugged in' }
                New-CheckResult -Category $category -Check 'Battery' -Status Info -Value ('Charge not reported ({0})' -f $power)
                continue
            }
            $charge = [int]$reported

            if ($onBattery) {
                $status = Get-ThresholdStatus -Value $charge -LowerIsWorse `
                    -Warning $thresholds.Battery.WarningPercent -Critical $thresholds.Battery.CriticalPercent
                $power = 'on battery'
            }
            else {
                $status = 'OK'
                $power = 'plugged in'
            }

            $recommendation = if ($status -ne 'OK') { 'Battery charge is low. Connect the charger.' } else { '' }
            New-CheckResult -Category $category -Check 'Battery' -Status $status `
                -Value ('{0} % ({1})' -f $charge, $power) -Recommendation $recommendation `
                -Allowed (Format-AllowedRange -Warning $thresholds.Battery.WarningPercent -Critical $thresholds.Battery.CriticalPercent -Unit '%' -LowerIsWorse)
        }

        # Battery health: how much of its original capacity the battery still has.
        if ($batteries.Count -gt 0) {
            foreach ($capacity in @(Get-BatteryCapacity)) {
                $health = [int][math]::Min(100, [math]::Round([double]$capacity.FullChargedCapacity / [double]$capacity.DesignedCapacity * 100))
                $status = Get-ThresholdStatus -Value $health -LowerIsWorse `
                    -Warning $thresholds.Battery.HealthWarningPercent -Critical $thresholds.Battery.HealthCriticalPercent
                $value = '{0} % of the original capacity ({1} of {2} mWh)' -f $health, $capacity.FullChargedCapacity, $capacity.DesignedCapacity
                if ($capacity.CycleCount) {
                    $value = '{0}, {1} charge cycles' -f $value, $capacity.CycleCount
                }
                $recommendation = if ($status -ne 'OK') {
                    'The battery has lost much of its capacity, so the computer runs for a much shorter time than when it was new. Plan to replace the battery.'
                }
                else {
                    ''
                }
                New-CheckResult -Category $category -Check 'Battery health' -Status $status -Value $value -Recommendation $recommendation `
                    -Allowed (Format-AllowedRange -Warning $thresholds.Battery.HealthWarningPercent -Critical $thresholds.Battery.HealthCriticalPercent -Unit '%' -LowerIsWorse -Maximum 100) `
                    -Typical $thresholds.Battery.TypicalHealth
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Battery' -ErrorRecord $_
    }
}
