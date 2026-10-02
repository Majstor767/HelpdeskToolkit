function Get-MemoryDiagnosticResult {
    <#
    .SYNOPSIS
        Returns the result of the last memory test of Windows; nothing when none is on record.
    .DESCRIPTION
        Windows Memory Diagnostic (mdsched.exe) tests the memory during a restart and
        writes the outcome into the System log afterwards, as an event of the source
        "Microsoft-Windows-MemoryDiagnostics-Results":

        1101, 1201  the test found no errors
        1102, 1202  the test found hardware errors

        The log is readable without administrator rights. The test itself is never
        started from here: it needs a restart, which is for the user to decide.

        Returns an object with TestedAt and HasErrors.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $filter = @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' }
        $entry = Get-WinEvent -FilterHashtable $filter -MaxEvents 1 -ErrorAction Stop
    }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') {
            return
        }
        throw
    }

    [PSCustomObject]@{
        TestedAt  = $entry.TimeCreated
        # Level 1 and 2 are Critical and Error.
        HasErrors = ($entry.Id -in 1102, 1202) -or ($entry.Level -in 1, 2)
    }
}
