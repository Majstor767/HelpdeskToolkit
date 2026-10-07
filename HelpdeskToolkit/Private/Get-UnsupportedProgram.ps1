function Get-UnsupportedProgram {
    <#
    .SYNOPSIS
        Picks the programs whose maker no longer releases security updates for them.
    .DESCRIPTION
        Compares the names of the installed programs with the list in
        Config\EndOfLife.psd1. An entry of that list counts from the day after its end
        date, so a version whose support ends next month is not reported yet and
        appears by itself when the day has passed.

        Returns one object per program with Name (as "Installed apps" shows it, with
        the version when the name does not contain it), EndDate and Level ("Warning"
        or "Info", see the configuration file).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # The objects returned by Get-InstalledProgram.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Program
    )

    if (-not $script:EndOfLife) {
        $path = Join-Path -Path $script:ModuleRoot -ChildPath 'Config\EndOfLife.psd1'
        $script:EndOfLife = @((Import-PowerShellDataFile -LiteralPath $path).Products)
    }

    $today = (Get-Date).Date

    foreach ($item in $Program) {
        foreach ($product in $script:EndOfLife) {
            if ([string]$item.Name -notmatch $product.Match) {
                continue
            }

            $end = [datetime]::ParseExact($product.End, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
            if ($end -lt $today) {
                $name = [string]$item.Name
                # Many names carry their version already ("Python 3.8.10 (64-bit)").
                if ($item.Version -and $name -notmatch '\d+\.\d+') {
                    $name = '{0} {1}' -f $name, $item.Version
                }

                [PSCustomObject]@{
                    Name    = $name
                    EndDate = $end
                    Level   = [string]$product.Level
                }
            }
            # The first entry that fits the name decides.
            break
        }
    }
}
