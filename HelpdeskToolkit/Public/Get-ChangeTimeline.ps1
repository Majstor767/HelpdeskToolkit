function Get-ChangeTimeline {
    <#
    .SYNOPSIS
        Lists what happened on the computer lately, in order of time: installations, updates, crashes and failures.
    .DESCRIPTION
        "It worked last week" is where most troubleshooting starts. This command puts
        the changes and the failures of the last weeks on one time line, so that the
        change that came just before the first failure can be found:

        Changes   a program was installed, updated or removed; Windows or a Store app
                  was updated; a driver was installed
        Problems  a program crashed or stopped responding; an update failed; Windows
                  crashed (blue screen); the computer went off without a shutdown

        The data is what Windows itself collects for Reliability Monitor. It is read
        without administrator rights, reaches back about a month, and nothing on the
        system is changed.

        Things that repeat are shown once per day with their number: the definition
        updates of the antivirus and the updates of the Store apps arrive by the dozen
        and would bury the rest.
    .PARAMETER Days
        How many days to look back. The default is 30, which is about as far as Windows
        keeps the data.
    .EXAMPLE
        Get-ChangeTimeline

        Returns the events of the last 30 days, newest first.
    .EXAMPLE
        Get-ChangeTimeline -Days 7 | Where-Object Level -eq 'Problem'

        Shows what went wrong in the last week.
    .EXAMPLE
        Get-ChangeTimeline | Format-Table Time, Kind, Title, Count -AutoSize

        Shows the time line as a table.
    .OUTPUTS
        HelpdeskToolkit.TimelineEvent
        Objects with the properties Time, Level ("Problem" or "Change"), Kind, Title and Count.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.TimelineEvent')]
    param(
        [ValidateRange(1, 365)]
        [int]$Days = 30
    )

    # Source and event number -> what it means. Entries that are not listed tell
    # nothing a technician acts on (for example "Windows Installer reconfigured the
    # product", which every repair check of a program writes).
    $meaning = @{
        'Application Error|1000'                          = @{ Level = 'Problem'; Kind = 'Program crashed' }
        'Application Hang|1002'                           = @{ Level = 'Problem'; Kind = 'Program stopped responding' }
        'Microsoft-Windows-WindowsUpdateClient|19'        = @{ Level = 'Change'; Kind = 'Update installed' }
        'Microsoft-Windows-WindowsUpdateClient|20'        = @{ Level = 'Problem'; Kind = 'Update failed' }
        'MsiInstaller|1033'                               = @{ Level = 'Change'; Kind = 'Program installed' }
        'MsiInstaller|1034'                               = @{ Level = 'Change'; Kind = 'Program removed' }
        'MsiInstaller|1036'                               = @{ Level = 'Change'; Kind = 'Program updated' }
        'MsiInstaller|1022'                               = @{ Level = 'Change'; Kind = 'Program updated' }
        'Microsoft-Windows-UserPnp|20001'                 = @{ Level = 'Change'; Kind = 'Driver installed' }
        'EventLog|6008'                                   = @{ Level = 'Problem'; Kind = 'Unexpected shutdown' }
        'Microsoft-Windows-WER-SystemErrorReporting|1001' = @{ Level = 'Problem'; Kind = 'Windows crashed (blue screen)' }
    }

    $records = @(Get-ReliabilityRecord -Since (Get-Date).AddDays(-$Days))

    $entries = foreach ($record in $records) {
        $known = $meaning['{0}|{1}' -f $record.SourceName, $record.EventIdentifier]
        if (-not $known) {
            continue
        }

        $title = ([string]$record.ProductName).Trim()
        # Store apps are named "9PMMSR1CGPWG-Microsoft.HEIFImageExtension". They update
        # themselves by the dozen, so their successful updates are gathered into one
        # entry per day; one that failed keeps its name.
        if ($title -match '^[0-9A-Z]{12}-') {
            $title = if ($known.Level -eq 'Change') { 'Microsoft Store apps' } else { $title -replace '^[0-9A-Z]{12}-', '' }
        }
        # The definitions of the antivirus carry their version in the name, which
        # would make every one of them a different thing.
        if ($title -match '^(Security Intelligence Update|Definition Update) ') {
            $title = 'Antivirus definitions'
        }

        [PSCustomObject]@{
            Time  = [datetime]$record.TimeGenerated
            Level = $known.Level
            Kind  = $known.Kind
            Title = $title
        }
    }

    # The same thing on the same day becomes one entry with its number and its newest time.
    @($entries | Where-Object { $_ }) | Group-Object -Property { $_.Time.ToString('yyyyMMdd', [cultureinfo]::InvariantCulture) }, Kind, Title | ForEach-Object {
        $newest = $_.Group | Sort-Object -Property Time -Descending | Select-Object -First 1
        [PSCustomObject]@{
            PSTypeName = 'HelpdeskToolkit.TimelineEvent'
            Time       = $newest.Time
            Level      = $newest.Level
            Kind       = $newest.Kind
            Title      = $newest.Title
            Count      = $_.Count
        }
    } | Sort-Object -Property Time -Descending
}
