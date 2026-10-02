function Get-ReliabilityRecord {
    <#
    .SYNOPSIS
        Returns the entries behind Reliability Monitor: crashes, installations and updates, with their time.
    .DESCRIPTION
        Windows collects the events that tell the story of a computer (a program
        crashed, an update was installed, a driver was added, the computer went off
        without a shutdown) in the class Win32_ReliabilityRecords. Reliability Monitor
        ("perfmon /rel") draws its chart from it. The class is readable without
        administrator rights and reaches back about a month.

        A thin wrapper, so the tests have one command to replace. Returns the records
        as they are (SourceName, EventIdentifier, TimeGenerated, ProductName, Message),
        newest first.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        # Only records after this time are returned.
        [Parameter(Mandatory)]
        [datetime]$Since
    )

    Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction Stop |
        Where-Object { $_.TimeGenerated -ge $Since } |
        Sort-Object -Property TimeGenerated -Descending
}
