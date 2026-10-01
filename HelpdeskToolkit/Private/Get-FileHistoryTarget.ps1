function Get-FileHistoryTarget {
    <#
    .SYNOPSIS
        Returns where File History saves its backups, when the current user has set it up.
    .DESCRIPTION
        File History, the backup of personal files built into Windows, writes its
        settings to a file in the profile of the user. When that file exists, the
        backup was set up at some point; it names the drive or network folder that
        receives the copies.

        Returns the name of the target, the text "unknown target" when the file exists
        but names none, or nothing when File History was never set up.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $path = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Windows\FileHistory\Configuration\Config1.xml'
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    try {
        [xml]$config = [System.IO.File]::ReadAllText($path)
        $target = $config.SelectSingleNode('//Target/TargetName')
        if (-not $target -or -not $target.InnerText) {
            $target = $config.SelectSingleNode('//Target/TargetUrl')
        }
        if ($target -and $target.InnerText) {
            return [string]$target.InnerText
        }
    }
    catch {
        Write-Verbose "Unreadable File History configuration: $($_.Exception.Message)"
    }

    'unknown target'
}
