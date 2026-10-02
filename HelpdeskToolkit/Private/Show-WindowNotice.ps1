function Show-WindowNotice {
    <#
    .SYNOPSIS
        Draws the notices about new problems at the top of the window.
    .DESCRIPTION
        The notices are the problems an automatic check has found since the user last
        looked (see Add-WindowNotice). They are shown on every page, newest first, as
        lines that can be clicked: a click opens the result (Show-WindowResult).

        A notice whose problem is gone in the report on the screen is dropped, so the
        bar never points at something that is fine again. Without notices the bar is
        hidden. With -Clear all notices are dropped: the user dismissed them, or
        started a check, which is a fresh look at everything.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [switch]$Clear
    )

    $controls = $Gui.Controls

    if ($Clear) {
        $Gui.Notices.Clear()
    }

    # Only problems that the current report still has
    if ($Gui.Report) {
        foreach ($key in @($Gui.Notices.Keys)) {
            $notice = $Gui.Notices[$key]
            $result = @($Gui.Report.Results) | Where-Object { $_.Category -eq $notice.Category -and $_.Check -eq $notice.Check } | Select-Object -First 1
            if (-not $result -or $result.Status -notin 'Warning', 'Critical') {
                $Gui.Notices.Remove($key)
            }
        }
    }

    $notices = @($Gui.Notices.Values)
    if ($notices.Count -eq 0) {
        $controls.NoticeItems.ItemsSource = @()
        $controls.NoticeBorder.Visibility = [System.Windows.Visibility]::Collapsed
        return
    }

    [array]::Reverse($notices)
    $latest = $notices[0].FoundAt
    $controls.NoticeTitle.Text = if ($notices.Count -eq 1) {
        (Get-LocalizedText 'The automatic check found a new problem at {0:HH:mm}. Click it to see the result.') -f $latest
    }
    else {
        (Get-LocalizedText 'The automatic check found {0} new problems, the last one at {1:HH:mm}. Click one to see the result.') -f $notices.Count, $latest
    }

    $controls.NoticeItems.ItemsSource = @(
        $notices | ForEach-Object {
            [PSCustomObject]@{
                Text     = '[{0}] {1} / {2}: {3}' -f (Get-LocalizedText $_.Status), (Get-LocalizedText $_.Category), (Get-LocalizedCheckName $_.Check), (Get-LocalizedText $_.Value)
                Link     = Get-LocalizedText 'Show'
                Category = $_.Category
                Check    = $_.Check
            }
        }
    )
    $controls.NoticeBorder.Visibility = [System.Windows.Visibility]::Visible
}
