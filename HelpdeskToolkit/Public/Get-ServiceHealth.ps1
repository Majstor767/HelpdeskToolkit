function Get-ServiceHealth {
    <#
    .SYNOPSIS
        Reports the state of the Windows services a helpdesk technician checks first.
    .DESCRIPTION
        The list of services is defined in Config\Thresholds.psd1 (DHCP and DNS client,
        Windows Update, Print Spooler, firewall, Defender and others).

        The verdict depends on the start mode, because a stopped service is not
        always a problem:
        - Running                      -> OK
        - Stopped, start mode Manual   -> Info (Windows starts it on demand)
        - Stopped, start mode Auto     -> Warning (it should be running)
        - Disabled                     -> Warning

        Also listed: the services that start automatically and were installed by other
        programs (everything whose program file is outside the Windows folder and is not a Microsoft product).

        Services are only queried, never started or stopped. No administrator rights
        are needed.
    .EXAMPLE
        Get-ServiceHealth

        Returns one result per configured service.
    .OUTPUTS
        HelpdeskToolkit.CheckResult
        Objects with the properties Category, Check, Description, Status, Value, Details, Allowed, Typical and Recommendation.
    #>
    [CmdletBinding()]
    [OutputType('HelpdeskToolkit.CheckResult')]
    param()

    $category = 'Services'
    $names = @((Get-HealthThreshold).Services)

    try {
        # One WMI query for all services: Name = 'A' OR Name = 'B' ...
        $filter = ($names | ForEach-Object { "Name = '{0}'" -f $_ }) -join ' OR '
        $services = @(Get-CimInstance -ClassName Win32_Service -Filter $filter -ErrorAction Stop)
    }
    catch {
        New-FailureResult -Category $category -Check 'Services' -ErrorRecord $_
        return
    }

    foreach ($name in $names) {
        # The display name is translated on non-English Windows, so the explanation
        # is looked up by the service name, which is the same everywhere.
        $description = Get-CheckDescription -Key ('Service:{0}' -f $name)

        $service = $services | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $service) {
            New-CheckResult -Category $category -Check $name -Status Info -Value 'Not installed' -Description $description
            continue
        }

        $check = '{0} ({1})' -f $service.DisplayName, $service.Name
        $value = '{0} (start mode: {1})' -f $service.State, $service.StartMode

        if ($service.State -eq 'Running') {
            New-CheckResult -Category $category -Check $check -Status OK -Value $value -Description $description
        }
        elseif ($service.StartMode -eq 'Disabled') {
            New-CheckResult -Category $category -Check $check -Status Warning -Value $value -Description $description `
                -Recommendation 'The service is disabled. Unless that was done on purpose, set its startup type back to the default in services.msc.'
        }
        elseif ($service.StartMode -eq 'Auto') {
            New-CheckResult -Category $category -Check $check -Status Warning -Value $value -Description $description `
                -Recommendation 'The service should start automatically but is not running. Start it in services.msc and check the System event log for the reason it stopped.'
        }
        else {
            New-CheckResult -Category $category -Check $check -Status Info -Value $value -Description $description
        }
    }

    # Services that start with Windows and do not belong to it. They were installed by
    # other programs and run all the time, whether the program is used or not.
    try {
        $windowsFolder = [string]$env:SystemRoot
        $thirdParty = @(
            Get-CimInstance -ClassName Win32_Service -Filter "StartMode = 'Auto'" -ErrorAction Stop |
                Where-Object {
                    # Services of Windows live in the Windows folder; other services of
                    # Microsoft (Defender, Edge, Office, Store apps) are recognized by
                    # "Microsoft" or "Windows Defender" in the path of their program.
                    $_.PathName -and ([string]$_.PathName).Trim('"') -notlike "$windowsFolder\*" -and
                    [string]$_.PathName -notmatch '\\Microsoft([ .\\]|$)|\\Windows Defender'
                } |
                Sort-Object -Property DisplayName |
                ForEach-Object { if ($_.State -eq 'Running') { [string]$_.DisplayName } else { '{0} (not running)' -f $_.DisplayName } }
        )
        $list = ConvertTo-ListValue -Item $thirdParty -Label 'service' -Shown 6
        New-CheckResult -Category $category -Check 'Third-party services' -Status Info -Value $list.Value -Details $list.Details
    }
    catch {
        New-FailureResult -Category $category -Check 'Third-party services' -ErrorRecord $_
    }
}
