function Get-DriveReliability {
    <#
    .SYNOPSIS
        Returns the values every physical drive measures about itself (SMART).
    .DESCRIPTION
        A thin wrapper around Get-PhysicalDisk and Get-StorageReliabilityCounter. Windows
        only hands these counters to administrators. Drives leave out what they do
        not measure: a hard disk has no wear value, some drives report no temperature.

        Returns one object per drive with Name, Temperature (degrees Celsius), Wear
        (percent of the rated lifetime used), PowerOnHours, ReadErrors and WriteErrors
        (errors the drive could not correct).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    foreach ($disk in Get-PhysicalDisk -ErrorAction Stop) {
        $counter = $disk | Get-StorageReliabilityCounter -ErrorAction Stop

        [PSCustomObject]@{
            Name         = [string]$disk.FriendlyName
            Temperature  = $counter.Temperature
            Wear         = $counter.Wear
            PowerOnHours = $counter.PowerOnHours
            ReadErrors   = $counter.ReadErrorsUncorrected
            WriteErrors  = $counter.WriteErrorsUncorrected
        }
    }
}
