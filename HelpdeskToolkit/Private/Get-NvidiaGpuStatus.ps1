function Get-NvidiaGpuStatus {
    <#
    .SYNOPSIS
        Returns temperature, fan speed and power draw of the NVIDIA graphics cards.
    .DESCRIPTION
        Windows itself does not hand out these sensor values. For NVIDIA cards the
        driver brings its own status tool (see Invoke-NvidiaSmi); other makes have no
        comparable tool, so for them nothing is returned.

        Returns one object per card with Name, TemperatureC, FanPercent, PowerWatts
        and PowerLimitWatts. A value the card does not report (laptops often have no
        fan sensor of their own) is $null.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # A missing value is printed as "[N/A]" or "[Not Supported]".
    $toNumber = {
        param($Text)
        $number = 0.0
        if ([double]::TryParse(([string]$Text).Trim(), [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$number)) {
            [int][math]::Round($number)
        }
    }

    foreach ($line in @(Invoke-NvidiaSmi -Query 'name,temperature.gpu,fan.speed,power.draw,power.limit')) {
        $fields = @(([string]$line) -split ',')
        if ($fields.Count -lt 5) {
            continue
        }

        [PSCustomObject]@{
            Name            = $fields[0].Trim()
            TemperatureC    = & $toNumber $fields[1]
            FanPercent      = & $toNumber $fields[2]
            PowerWatts      = & $toNumber $fields[3]
            PowerLimitWatts = & $toNumber $fields[4]
        }
    }
}
