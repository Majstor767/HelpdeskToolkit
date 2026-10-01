function Get-PrinterHealth {
    <#
    .SYNOPSIS
        Reports the default printer, the installed printers and the print queue.
    .DESCRIPTION
        "I cannot print" is one of the most common helpdesk calls. This check shows the
        three things looked at first:

        - which printer is the default one
        - which printers are installed, and whether one is set to "Use printer offline"
        - whether documents are stuck in the print queue: in an error state, or waiting
          longer than the limit in Config\Thresholds.psd1 (10 minutes by default)

        Printers and print jobs are only queried, never changed. No administrator
        rights are needed.
    .EXAMPLE
        Get-PrinterHealth

        Returns the printer results for the local computer.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'Printers'
    $thresholds = (Get-HealthThreshold).Printers

    # Printers
    try {
        $printers = @(Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop)

        $default = $printers | Where-Object { $_.Default } | Select-Object -First 1
        $defaultName = if ($default) { $default.Name } else { 'None set' }
        New-CheckResult -Category $category -Check 'Default printer' -Status Info -Value $defaultName

        if ($printers.Count -eq 0) {
            New-CheckResult -Category $category -Check 'Installed printers' -Status Info -Value 'No printers installed'
        }
        else {
            $offline = @($printers | Where-Object { $_.WorkOffline })
            $names = @($printers | Sort-Object -Property Name | ForEach-Object {
                    if ($_.WorkOffline) { '{0} (offline)' -f $_.Name } else { $_.Name }
                })

            if ($offline.Count -gt 0) {
                New-CheckResult -Category $category -Check 'Installed printers' -Status Warning `
                    -Value ('{0} printers, {1} offline: {2}' -f $printers.Count, $offline.Count, ($names -join ', ')) `
                    -Recommendation 'A printer is set to work offline, so documents stay in the queue. Check that it is switched on and connected, then open Settings > Bluetooth & devices > Printers & scanners, open its print queue and turn off "Use Printer Offline".'
            }
            else {
                New-CheckResult -Category $category -Check 'Installed printers' -Status Info `
                    -Value ('{0} printers: {1}' -f $printers.Count, ($names -join ', '))
            }
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Installed printers' -ErrorRecord $_
    }

    # Print queue
    try {
        $jobs = @(Get-CimInstance -ClassName Win32_PrintJob -ErrorAction Stop)
        $limit = (Get-Date).AddMinutes(-$thresholds.StuckJobMinutes)

        # Bit 2 of StatusMask means the job is in an error state.
        $stuck = @($jobs | Where-Object { ([int]$_.StatusMask -band 2) -or ($_.TimeSubmitted -and $_.TimeSubmitted -lt $limit) })

        $waiting = '{0} document{1} waiting' -f $jobs.Count, $(if ($jobs.Count -ne 1) { 's' })

        if ($stuck.Count -gt 0) {
            New-CheckResult -Category $category -Check 'Print queue' -Status Warning `
                -Value ('{0}, {1} stuck: {2}' -f $waiting, $stuck.Count, (($stuck | ForEach-Object { $_.Document }) -join ', ')) `
                -Recommendation 'Documents are stuck in the print queue and block everything behind them. Open the print queue of the printer and cancel them; if they do not disappear, restart the Print Spooler service (services.msc).'
        }
        else {
            New-CheckResult -Category $category -Check 'Print queue' -Status OK -Value $waiting
        }
    }
    catch {
        New-FailureResult -Category $category -Check 'Print queue' -ErrorRecord $_
    }
}
