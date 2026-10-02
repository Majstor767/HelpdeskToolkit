function Get-LauncherArgument {
    <#
    .SYNOPSIS
        Returns the arguments with which Windows PowerShell starts the application window.
    .DESCRIPTION
        Used when the window starts a second copy of itself: to restart with
        administrator rights, or to restart after the language or the theme changed.

        Installed and portable copies have the launcher script next to the module
        folder. A module that was loaded from somewhere else is started through its
        manifest instead.

        -RunCheck makes the new copy start the check at once, without asking about
        administrator rights; -NoQuestion only leaves the question out. Both are
        passed on to Show-PCHealthCheck.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [switch]$RunCheck,

        [switch]$NoQuestion
    )

    $switches = ''
    if ($RunCheck) {
        $switches += ' -RunCheck'
    }
    if ($NoQuestion) {
        $switches += ' -NoQuestion'
    }

    $launcher = Join-Path -Path (Split-Path -Path $script:ModuleRoot -Parent) -ChildPath 'Start-HelpdeskToolkit.ps1'
    if (Test-Path -LiteralPath $launcher) {
        return '-NoProfile -ExecutionPolicy Bypass -File "{0}"{1}' -f $launcher, $switches
    }

    $manifest = (Join-Path -Path $script:ModuleRoot -ChildPath 'HelpdeskToolkit.psd1').Replace("'", "''")
    '-NoProfile -ExecutionPolicy Bypass -Command "Import-Module ''{0}''; Show-PCHealthCheck{1}"' -f $manifest, $switches
}
