function Test-OnBattery {
    <#
    .SYNOPSIS
        Tells whether the computer is running on its battery right now.
    .DESCRIPTION
        Asks Windows for the power status, which costs nothing (no WMI query). A
        desktop computer and a laptop on its charger return $false, and so does a
        computer whose status cannot be read: the application then behaves as usual.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Offline
    }
    catch {
        Write-Verbose "The power status could not be read: $($_.Exception.Message)"
        $false
    }
}
