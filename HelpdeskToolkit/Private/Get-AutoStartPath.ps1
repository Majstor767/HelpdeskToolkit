function Get-AutoStartPath {
    <#
    .SYNOPSIS
        Returns where the shortcut lies that starts the application with Windows.
    .DESCRIPTION
        Windows starts every shortcut in the Startup folder of the Start menu when the
        user signs in. That folder belongs to the user: no administrator rights are
        needed to put a shortcut there, the shortcut shows up under "Startup apps" in
        the settings of Windows and in Task Manager, and it can be turned off or
        deleted there like that of any other program.

        The tests replace the folder through $script:AutoStartFolder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $folder = if ($script:AutoStartFolder) { $script:AutoStartFolder } else { [Environment]::GetFolderPath('Startup') }
    Join-Path -Path $folder -ChildPath 'HelpdeskToolkit.lnk'
}
