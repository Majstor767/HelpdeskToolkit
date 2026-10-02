function Add-WindowNotice {
    <#
    .SYNOPSIS
        Announces problems that an automatic check has found.
    .DESCRIPTION
        Takes the changes "New problem" and "Worse" that Compare-PCHealthReport found
        between the report on the screen and the one of the automatic check, and adds
        them to the notices of the window ($Gui.Notices). A problem that is announced
        already is replaced by its newer state. Show-WindowNotice then draws them.

        Returns the notices that were added.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # Objects returned by Compare-PCHealthReport.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Change
    )

    $added = foreach ($entry in @($Change | Where-Object { $_ -and $_.Change -in 'New problem', 'Worse' })) {
        $key = '{0}|{1}' -f $entry.Category, $entry.Check
        # Removed first, so the newest notice is always the last one.
        if ($Gui.Notices.Contains($key)) {
            $Gui.Notices.Remove($key)
        }
        $notice = [PSCustomObject]@{
            Category = [string]$entry.Category
            Check    = [string]$entry.Check
            Status   = [string]$entry.After
            Value    = [string]$entry.Value
            FoundAt  = Get-Date
        }
        $Gui.Notices[$key] = $notice
        $notice
    }

    Show-WindowNotice -Gui $Gui
    $added
}
