function Enable-AppAutoStart {
    <#
    .SYNOPSIS
        Makes the application start with Windows, in the background.
    .DESCRIPTION
        Puts a shortcut into the Startup folder of the current user (see
        Get-AutoStartPath). It starts the application the way the Start menu shortcut
        does, through the console host without a console window, and adds -Background:
        the application then opens as an icon next to the clock, without a window, and
        runs the check with standard rights. Nothing asks for administrator rights
        while Windows is starting.

        This is the only thing the application writes outside its own folders, and
        only when the user ticks the option. Disable-AppAutoStart removes it again, as
        does the uninstaller.

        A shortcut is used instead of an entry under the "Run" key of the registry
        because Windows ignores such an entry when its command is longer than 260
        characters, which the path of a portable copy easily makes it.

        Returns $true when the shortcut was written.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $path = Get-AutoStartPath
        $folder = Split-Path -Path $path -Parent
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }

        $powershell = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($path)
        $shortcut.TargetPath = Join-Path -Path $env:WINDIR -ChildPath 'System32\conhost.exe'
        $shortcut.Arguments = '--headless "{0}" {1}' -f $powershell, (Get-LauncherArgument -Background)
        $shortcut.WorkingDirectory = Split-Path -Path $script:ModuleRoot -Parent
        $shortcut.Description = 'HelpdeskToolkit, started with Windows in the background'
        $icon = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\HelpdeskToolkit.ico'
        if (Test-Path -LiteralPath $icon) {
            $shortcut.IconLocation = $icon
        }
        $shortcut.Save()
        $true
    }
    catch {
        Write-Verbose "The shortcut for starting with Windows could not be written: $($_.Exception.Message)"
        $false
    }
}
