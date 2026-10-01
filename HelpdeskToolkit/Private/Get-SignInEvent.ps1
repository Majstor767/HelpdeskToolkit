function Get-SignInEvent {
    <#
    .SYNOPSIS
        Returns the account names of failed sign-ins or account lockouts from the Security log.
    .DESCRIPTION
        The Security log can only be read by administrators. Two events are of interest
        to a helpdesk:

        - 4625: a sign-in failed (wrong password, unknown account)
        - 4740: an account was locked after too many wrong passwords

        Returns one account name per event, so the caller can count and group them.

        Without administrator rights Windows does not report "access denied" for this
        log but simply finds no events. The caller therefore has to check for elevation
        first; an empty result here is only meaningful when the session is elevated.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('FailedSignIn', 'Lockout')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [datetime]$Since
    )

    # Event id and the position of the account name among the values of the event.
    $definitions = @{
        FailedSignIn = @{ Id = 4625; NameIndex = 5 }
        Lockout      = @{ Id = 4740; NameIndex = 0 }
    }
    $definition = $definitions[$Kind]

    try {
        $entries = @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = $definition.Id; StartTime = $Since } -ErrorAction Stop)
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            return
        }
        throw
    }

    foreach ($entry in $entries) {
        $values = @($entry.Properties)
        if ($values.Count -gt $definition.NameIndex) {
            [string]$values[$definition.NameIndex].Value
        }
        else {
            'unknown'
        }
    }
}
