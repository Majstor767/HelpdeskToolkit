function Get-AntivirusProduct {
    <#
    .SYNOPSIS
        Returns the names of the antivirus products registered in Windows Security Center.
    .DESCRIPTION
        Used to tell "Defender is off because another antivirus is installed" apart
        from "the computer has no active antivirus at all". The SecurityCenter2
        namespace only exists on client editions of Windows; on a server the function
        returns nothing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop |
            ForEach-Object { [string]$_.displayName }
    }
    catch {
        Write-Verbose "Could not query Windows Security Center: $($_.Exception.Message)"
    }
}
