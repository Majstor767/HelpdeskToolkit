function Get-RestorePoint {
    <#
    .SYNOPSIS
        Returns the creation time of every restore point of System Restore.
    .DESCRIPTION
        Windows only lists the restore points for administrators. The times are read
        through CIM, which works in Windows PowerShell and in PowerShell 7 alike (the
        cmdlet Get-ComputerRestorePoint only exists in Windows PowerShell).

        Returns one [datetime] per restore point, or nothing when there are none.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param()

    foreach ($point in Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -ErrorAction Stop) {
        # The time is stored as text in the WMI date format: 20260928101500.000000-000
        $text = [string]$point.CreationTime
        if ($text.Length -ge 14) {
            [datetime]::ParseExact($text.Substring(0, 14), 'yyyyMMddHHmmss', [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal)
        }
    }
}
