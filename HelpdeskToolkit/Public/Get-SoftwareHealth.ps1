function Get-SoftwareHealth {
    <#
    .SYNOPSIS
        Reports installed programs, recent installations, application crashes, browser extensions and the default browser.
    .DESCRIPTION
        - Installed programs: how many there are and their names with versions. The
          first few are part of the value, the rest is returned in the Details property.
        - Recently installed: programs installed in the last 30 days. "What changed
          recently?" is often the fastest way to the cause of a new problem.
        - Application crashes: how often programs crashed in the selected period and
          which ones. More crashes than the limit in Config\Thresholds.psd1 is a Warning.
        - Browser extensions of Chrome, Edge, Brave and Opera, with their versions.
        - Default browser.

        Everything is read from the registry and the Application event log, without
        administrator rights. Nothing is installed, removed or changed.
    .PARAMETER Days
        How many days of crash history to analyze. The default is 7.
    .EXAMPLE
        Get-SoftwareHealth

        Returns the software results for the local computer.
    .EXAMPLE
        Get-SoftwareHealth -Days 30 | Where-Object Check -eq 'Application crashes'

        Shows which programs crashed in the last 30 days and how often.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param(
        [ValidateRange(1, 365)]
        [int]$Days = 7
    )

    $category = 'Software'
    $thresholds = (Get-HealthThreshold).Software
    $shown = 8

    # Installed programs and recent installations
    try {
        $programs = @(Get-InstalledProgram | Sort-Object -Property Name)
        $list = @($programs | ForEach-Object { ('{0} {1}' -f $_.Name, $_.Version).Trim() })
        $remaining = @($list | Select-Object -Skip $shown)
        $value = '{0} programs' -f $programs.Count
        if ($list.Count -gt 0) {
            $value = '{0}: {1}' -f $value, (($list | Select-Object -First $shown) -join ', ')
        }
        if ($remaining.Count -gt 0) {
            $value = '{0} and {1} more' -f $value, $remaining.Count
        }
        New-CheckResult -Category $category -Check 'Installed programs' -Status Info -Value $value -Details $remaining

        $since = (Get-Date).Date.AddDays(-$thresholds.RecentDays)
        $recent = @($programs | Where-Object { $_.InstallDate -and $_.InstallDate -ge $since } |
                Sort-Object -Property InstallDate -Descending |
                ForEach-Object { '{0} ({1:yyyy-MM-dd})' -f $_.Name, $_.InstallDate })

        if ($recent.Count -eq 0) {
            $value = 'None in the last {0} days' -f $thresholds.RecentDays
        }
        else {
            $value = '{0} in the last {1} days: {2}' -f $recent.Count, $thresholds.RecentDays, (($recent | Select-Object -First $shown) -join ', ')
        }
        $remaining = @($recent | Select-Object -Skip $shown)
        if ($remaining.Count -gt 0) {
            $value = '{0} and {1} more' -f $value, $remaining.Count
        }
        New-CheckResult -Category $category -Check 'Recently installed' -Status Info -Value $value -Details $remaining
    }
    catch {
        New-FailureResult -Category $category -Check 'Installed programs' -ErrorRecord $_
    }

    # Application crashes. Event 1000 of the source "Application Error" is written every
    # time a program crashes; its first property is the name of the program.
    try {
        try {
            $filter = @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000; StartTime = (Get-Date).AddDays(-$Days) }
            $crashes = @(Get-WinEvent -FilterHashtable $filter -ErrorAction Stop)
        }
        catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                throw
            }
            $crashes = @()
        }

        $period = if ($Days -eq 1) { 'in the last day' } else { 'in the last {0} days' -f $Days }
        $byProgram = @(
            $crashes |
                Group-Object -Property { [string]$_.Properties[0].Value } |
                Sort-Object -Property Count -Descending |
                ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count }
        )

        $value = '{0} {1}' -f $crashes.Count, $period
        if ($byProgram.Count -gt 0) {
            $value = '{0}: {1}' -f $value, (($byProgram | Select-Object -First 5) -join ', ')
        }
        $remaining = @($byProgram | Select-Object -Skip 5)
        if ($remaining.Count -gt 0) {
            $value = '{0} and {1} more' -f $value, $remaining.Count
        }

        $status = Get-ThresholdStatus -Value $crashes.Count -Warning $thresholds.CrashWarningAbove
        $recommendation = if ($status -ne 'OK') {
            'Programs crash more often than usual. Update or reinstall the program at the top of the list; the details of each crash are in Event Viewer (eventvwr.msc) > Windows Logs > Application, source "Application Error".'
        }
        else {
            ''
        }
        New-CheckResult -Category $category -Check 'Application crashes' -Status $status -Value $value -Details $remaining `
            -Recommendation $recommendation `
            -Allowed (Format-AllowedRange -Warning $thresholds.CrashWarningAbove) -Typical $thresholds.TypicalCrashes
    }
    catch {
        New-FailureResult -Category $category -Check 'Application crashes' -ErrorRecord $_
    }

    # Browser extensions. They run inside the browser and see the pages the user
    # opens, which makes them a frequent cause of slow, odd or ad-filled browsing.
    try {
        $extensions = @(Get-BrowserExtension)
        if ($extensions.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Browser extensions' -Status Info -Value 'None found'
        }
        else {
            $perBrowser = @($extensions | Group-Object -Property Browser | Sort-Object -Property Name | ForEach-Object { '{0} ({1})' -f $_.Name, $_.Count })
            $names = @($extensions | Sort-Object -Property Browser, Name | ForEach-Object { ('{0}: {1} {2}' -f $_.Browser, $_.Name, $_.Version).Trim() })
            New-CheckResult -Category $category -Check 'Browser extensions' -Status Info `
                -Value ('{0} extensions: {1}' -f $extensions.Count, ($perBrowser -join ', ')) -Details $names
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Browser extensions' -ErrorRecord $_
    }

    # Default browser
    $browserPath = Get-DefaultBrowserPath
    if ($browserPath) {
        New-CheckResult -Category $category -Check 'Default browser' -Status Info -Value (Get-FileProductName -Path $browserPath)
    }
    else {
        New-CheckResult -Category $category -Check 'Default browser' -Status Info -Value 'Not set'
    }
}
