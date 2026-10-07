function Invoke-DesktopShell {
    <#
    .SYNOPSIS
        Has the desktop of the signed-in user open a file, a program or an address.
    .DESCRIPTION
        A program that runs with administrator rights starts everything it starts
        with those rights too. A web browser should never have them: whatever a web
        page manages to do in it would be done as an administrator.

        The desktop itself (Explorer: the taskbar, the icons) always runs with the
        ordinary rights of the user. Windows lets a program reach it and ask it to
        open something, exactly as a double-click on the desktop would. What is
        opened that way runs as the user, in the browser the user chose.

        This is the way Microsoft describes for starting something without
        administrator rights from a program that has them. The uninstaller of a
        program is started the same way (see Open-WindowUninstall), because that is
        how Windows itself starts it.

        Throws when the desktop cannot be reached (Explorer is not running). Whether
        the thing really opened is not reported back.
    #>
    [CmdletBinding()]
    param(
        # The file, program or address to open.
        [Parameter(Mandatory)]
        [string]$FilePath,

        # Arguments for a program.
        [string]$Arguments = '',

        # The folder the program is started in; without it, the one Windows chooses.
        [string]$WorkingDirectory = ''
    )

    # 8 = the window of the desktop, 1 = return an object that can be scripted;
    # the first argument (0) is the folder "Desktop".
    $handle = 0
    $desktop = (New-Object -ComObject Shell.Application).Windows().FindWindowSW(0, $null, 8, [ref]$handle, 1)
    if (-not $desktop) {
        throw 'The desktop of the signed-in user was not found.'
    }

    $application = $desktop.Document.Application
    if ($WorkingDirectory) {
        $application.ShellExecute($FilePath, $Arguments, $WorkingDirectory)
    }
    elseif ($Arguments) {
        $application.ShellExecute($FilePath, $Arguments)
    }
    else {
        $application.ShellExecute($FilePath)
    }
}
