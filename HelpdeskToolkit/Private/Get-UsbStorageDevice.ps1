function Get-UsbStorageDevice {
    <#
    .SYNOPSIS
        Returns the names of the USB sticks and USB disks that have been connected to this computer.
    .DESCRIPTION
        Windows keeps an entry for every USB storage device it has ever installed a
        driver for, under Enum\USBSTOR in the registry: one key per model and below it
        one key per device (its serial number). The names are readable without
        administrator rights; the time of the last connection is not, so it is left out.

        Returns one name per device, for example "SanDisk Ultra". A device that has no
        name of its own is named after its model key ("Disk&Ven_SanDisk&Prod_Ultra").
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $root = 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR'

    foreach ($model in Get-ChildItem -Path $root -ErrorAction SilentlyContinue) {
        foreach ($device in Get-ChildItem -Path $model.PSPath -ErrorAction SilentlyContinue) {
            $name = [string]$device.GetValue('FriendlyName')
            if (-not $name -and $model.PSChildName -match 'Ven_(?<maker>[^&]*)&Prod_(?<product>[^&]*)') {
                $name = ('{0} {1}' -f $Matches.maker, $Matches.product) -replace '_', ' '
            }

            $name = ($name -replace '\s+USB Device$', '').Trim()
            if ($name) {
                $name
            }
        }
    }
}
