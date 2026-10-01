function Get-VideoMemory {
    <#
    .SYNOPSIS
        Returns the graphics adapters and the amount of dedicated memory each one has.
    .DESCRIPTION
        WMI reports the memory of a graphics adapter in a 32-bit field, so every card
        with more than 4 GB shows as 4 GB there. The driver stores the real amount as a
        64-bit value in its registry key, which standard users can read.

        Returns one object per adapter with Name and Bytes; adapters whose driver does
        not store the value are left out.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Registry class of display adapters; one numbered subkey per installed adapter.
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'

    foreach ($key in Get-ChildItem -Path $classKey -ErrorAction SilentlyContinue) {
        $name = $key.GetValue('DriverDesc')
        $bytes = $key.GetValue('HardwareInformation.qwMemorySize')
        if ($name -and $bytes) {
            [PSCustomObject]@{
                Name  = [string]$name
                Bytes = [long]$bytes
            }
        }
    }
}
