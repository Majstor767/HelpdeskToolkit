function Get-Windows11Readiness {
    <#
    .SYNOPSIS
        Works out whether a Windows 10 computer meets the hardware requirements of Windows 11.
    .DESCRIPTION
        Windows 11 needs: a 64-bit processor with at least 2 cores and 1 GHz that is
        on the list of supported models, 4 GB of memory, a system drive of 64 GB,
        UEFI with Secure Boot, and a TPM of version 2.0.

        Everything except the list of processor models is measured here. The list is
        covered by the judgement Windows keeps about itself (see Get-UpgradeIndicator);
        when Windows has none yet, the processor model stays unchecked and the result
        says so. The TPM can only be read with administrator rights.

        Returns an object with:
        Ready         $true, $false, or nothing when something could not be found out
        Requirements  one object per requirement with Name, Met ($true, $false or
                      nothing for "unknown") and Value (what was found)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $requirements = New-Object -TypeName System.Collections.Generic.List[object]
    $add = {
        param($Name, $Met, $Value)
        $requirements.Add([PSCustomObject]@{ Name = $Name; Met = $Met; Value = $Value })
    }

    # Processor: 64-bit, 2 cores, 1 GHz
    $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
    $cores = [int]($processors | Measure-Object -Property NumberOfCores -Sum).Sum
    $bits = [int]$processors[0].AddressWidth
    $megahertz = [int]$processors[0].MaxClockSpeed
    & $add 'Processor (64-bit, 2 cores, 1 GHz)' ($bits -eq 64 -and $cores -ge 2 -and $megahertz -ge 1000) `
        ('{0}-bit, {1} cores, {2} MHz' -f $bits, $cores, $megahertz)

    # Memory. Windows reports a little less than is installed, hence the margin.
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $memory = [double]$computer.TotalPhysicalMemory
    & $add 'Memory (4 GB)' ($memory -ge 3.5GB) (Format-Gigabyte -Bytes $memory)

    # System drive
    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter ("DeviceID = '{0}'" -f $env:SystemDrive) -ErrorAction Stop |
        Select-Object -First 1
    if ($drive -and $drive.Size) {
        & $add 'System drive (64 GB)' ([double]$drive.Size -ge 60GB) (Format-Gigabyte -Bytes $drive.Size)
    }
    else {
        & $add 'System drive (64 GB)' $null 'unknown'
    }

    # UEFI with Secure Boot. It has to be possible; switching it on is a setting.
    switch (Get-SecureBootState) {
        'Enabled' { & $add 'UEFI with Secure Boot' $true 'enabled' }
        'Disabled' { & $add 'UEFI with Secure Boot' $true 'supported, switched off' }
        default { & $add 'UEFI with Secure Boot' $false 'not supported (legacy BIOS mode)' }
    }

    # TPM 2.0 (administrators only)
    if (Test-IsAdministrator) {
        try {
            $tpm = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop |
                Select-Object -First 1
            if ($tpm) {
                # SpecVersion looks like "2.0, 0, 1.59"; the first part is the TPM version.
                $version = ([string]$tpm.SpecVersion -split ',')[0].Trim()
                & $add 'TPM 2.0' ($version -like '2.*') ('version {0}' -f $version)
            }
            else {
                & $add 'TPM 2.0' $false 'not present or switched off'
            }
        }
        catch {
            & $add 'TPM 2.0' $null 'unknown'
        }
    }
    else {
        & $add 'TPM 2.0' $null 'unknown (requires admin)'
    }

    # What Windows worked out itself, including the processor model.
    $reasonText = @{
        CpuFms          = 'processor model not supported'
        Tpm             = 'no TPM'
        TpmVersion      = 'TPM older than 2.0'
        UefiSecureBoot  = 'no UEFI with Secure Boot'
        Memory          = 'too little memory'
        SystemDriveSize = 'system drive too small'
    }
    $indicator = Get-UpgradeIndicator
    if ($indicator) {
        $reasons = @($indicator.Reasons | ForEach-Object { if ($reasonText.ContainsKey($_)) { $reasonText[$_] } else { $_ } })
        if ($indicator.Verdict -eq 'Green' -and $reasons.Count -eq 0) {
            & $add 'Assessment by Windows' $true 'nothing stands in the way'
        }
        elseif ($reasons.Count -gt 0) {
            & $add 'Assessment by Windows' $false ($reasons -join ', ')
        }
        else {
            & $add 'Assessment by Windows' $null ('undecided ({0})' -f $indicator.Verdict)
        }
    }
    else {
        & $add 'Assessment by Windows' $null 'none yet, so the processor model is not checked against the list of Microsoft'
    }

    $failed = @($requirements | Where-Object { $_.Met -eq $false })
    $unknown = @($requirements | Where-Object { $null -eq $_.Met })
    $windowsSaysYes = @($requirements | Where-Object { $_.Name -eq 'Assessment by Windows' -and $_.Met -eq $true }).Count -gt 0

    $ready = if ($failed.Count -gt 0) {
        $false
    }
    elseif ($unknown.Count -eq 0 -or $windowsSaysYes) {
        # Windows checks the TPM itself, so its "yes" covers what could not be read here.
        $true
    }
    else {
        $null
    }

    [PSCustomObject]@{
        Ready        = $ready
        Requirements = $requirements.ToArray()
    }
}
