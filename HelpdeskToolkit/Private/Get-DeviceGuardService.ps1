function Get-DeviceGuardService {
    <#
    .SYNOPSIS
        Returns the numbers of the virtualization-based protection features that are running.
    .DESCRIPTION
        Windows reports them in the class Win32_DeviceGuard, which is readable without
        administrator rights. The numbers that matter here:

        1 = Credential Guard
        2 = memory integrity (hypervisor-protected code integrity, "Core isolation")

        A registry value only says that a feature was switched on; this class says
        whether it really runs, which it does not after an incompatible driver blocked
        it or before the restart that the change needs.

        Returns nothing when the class cannot be read (older Windows versions).
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    try {
        $guard = Get-CimInstance -Namespace 'root/Microsoft/Windows/DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        Write-Verbose "Win32_DeviceGuard could not be read: $($_.Exception.Message)"
        return
    }

    if ($guard) {
        # 0 stands for "nothing is running"; it is returned too, so the caller can tell
        # "nothing runs" from "unknown".
        $guard.SecurityServicesRunning | ForEach-Object { [int]$_ }
    }
}
