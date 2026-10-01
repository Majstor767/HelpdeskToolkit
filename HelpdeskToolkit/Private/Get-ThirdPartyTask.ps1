function Get-ThirdPartyTask {
    <#
    .SYNOPSIS
        Returns the scheduled tasks that do not belong to Windows.
    .DESCRIPTION
        Windows keeps its own tasks in the folder \Microsoft\. Everything outside of it
        was created by an installed program or by a user: updaters, helpers, and
        sometimes unwanted software that wants to be started again and again.

        Returns one object per task with Name, Author and Enabled. A standard user only
        sees the tasks Windows lets that user see.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    foreach ($task in Get-ScheduledTask -ErrorAction Stop) {
        if ($task.TaskPath -like '\Microsoft\*') {
            continue
        }

        # Tasks of one user carry the security identifier of that user in their name.
        $name = [string]$task.TaskName -replace '[-_ ]?S-1-5-21(-\d+)+', ''
        [PSCustomObject]@{
            Name    = $name
            Author  = [string]$task.Author
            Enabled = [string]$task.State -ne 'Disabled'
        }
    }
}
