function Get-PendingRebootReason {
    <#
    .SYNOPSIS
        Returns the reasons why Windows is waiting for a restart; nothing when it is not.
    .DESCRIPTION
        Windows marks a pending restart by creating registry keys. Only their existence
        is tested, which works without administrator rights.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $keys = [ordered]@{
        'Windows Update'      = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        'Component servicing' = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    }

    foreach ($reason in $keys.Keys) {
        if (Test-Path -Path $keys[$reason]) {
            $reason
        }
    }
}
