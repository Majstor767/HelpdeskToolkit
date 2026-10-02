function Get-BootDegradation {
    <#
    .SYNOPSIS
        Returns what Windows itself blamed for slowing down its startup.
    .DESCRIPTION
        When Windows measures a startup (see Get-LastBootDuration) and finds that
        something took noticeably longer than usual, it writes an event of its own
        for it into the log "Microsoft-Windows-Diagnostics-Performance/Operational":

        101 a program    102 a driver    103 a service    106 background optimization
        107 policies of the computer    108 policies of the user    109 a device
        110 the start of the session

        Each event names the culprit and the delay in milliseconds (DegradationTime).
        Only administrators can read that log.

        Returns one object per event with Kind, Name, Milliseconds and MeasuredAt.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Only startups after this time are looked at.
        [Parameter(Mandatory)]
        [datetime]$Since
    )

    $kinds = @{
        101 = 'program'
        102 = 'driver'
        103 = 'service'
        106 = 'background optimization'
        107 = 'computer policy'
        108 = 'user policy'
        109 = 'device'
        110 = 'session start'
    }

    try {
        $filter = @{
            LogName   = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            Id        = [int[]]@($kinds.Keys)
            StartTime = $Since
        }
        $entries = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            return
        }
        throw
    }

    foreach ($entry in $entries) {
        # The values of an event are named in its XML form: <Data Name="FriendlyName">...</Data>
        $data = @{}
        foreach ($node in ([xml]$entry.ToXml()).Event.EventData.Data) {
            # InnerText also works for a value that is empty, which has no text node.
            $data[[string]$node.Name] = [string]$node.InnerText
        }

        $kind = $kinds[[int]$entry.Id]
        $name = @($data['FriendlyName'], $data['Name'], $data['FileName']) | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
        if (-not $name) {
            # Policies and the session start have no name of their own.
            $name = $kind
        }

        [PSCustomObject]@{
            Kind         = $kind
            Name         = ([string]$name).Trim()
            Milliseconds = [long]($data['DegradationTime'] -as [long])
            MeasuredAt   = $entry.TimeCreated
        }
    }
}
