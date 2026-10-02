function Get-UpgradeIndicator {
    <#
    .SYNOPSIS
        Returns what Windows itself has worked out about upgrading this computer to the newest release.
    .DESCRIPTION
        The compatibility check that Windows Update runs in the background writes its
        result into the registry, one key per target release (for example "GE24H2"):

        UpgEx      "Green" when nothing stands in the way, otherwise "Red" and others
        RedReason  the reasons that block the upgrade ("None" when there are none):
                   CpuFms = processor model, Tpm and TpmVersion, UefiSecureBoot,
                   Memory, SystemDriveSize

        This is the same judgement the PC Health Check app of Microsoft shows, and
        the only source that knows the list of supported processor models.

        Returns an object with Release, Verdict and Reasons for the newest release
        that has a verdict, or nothing when Windows has not judged the computer yet.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $root = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators'

    $judged = foreach ($key in Get-ChildItem -Path $root -ErrorAction SilentlyContinue) {
        $verdict = [string]$key.GetValue('UpgEx')
        # Release names end in year and half-year: "NI22H2", "GE24H2".
        if (-not $verdict -or $key.PSChildName -notmatch '(\d{2})H(\d)$') {
            continue
        }

        [PSCustomObject]@{
            Release = [string]$key.PSChildName
            Order   = [int]$Matches[1] * 10 + [int]$Matches[2]
            Verdict = $verdict
            Reasons = @($key.GetValue('RedReason') | Where-Object { $_ -and $_ -ne 'None' } | ForEach-Object { [string]$_ })
        }
    }

    $judged | Sort-Object -Property Order -Descending | Select-Object -First 1 -Property Release, Verdict, Reasons
}
