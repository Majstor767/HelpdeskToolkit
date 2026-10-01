function Get-SecureBootState {
    <#
    .SYNOPSIS
        Returns the Secure Boot state: Enabled, Disabled or Unsupported.
    .DESCRIPTION
        Confirm-SecureBootUEFI needs administrator rights. The same state is stored in
        the registry, which standard users can read. The key does not exist on
        computers that start in legacy BIOS mode.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
    try {
        $state = Get-ItemProperty -Path $key -ErrorAction Stop
        if ($state.PSObject.Properties.Name -contains 'UEFISecureBootEnabled') {
            if ($state.UEFISecureBootEnabled -eq 1) { return 'Enabled' }
            return 'Disabled'
        }
    }
    catch {
        Write-Verbose "Could not read the Secure Boot state: $($_.Exception.Message)"
    }

    'Unsupported'
}
