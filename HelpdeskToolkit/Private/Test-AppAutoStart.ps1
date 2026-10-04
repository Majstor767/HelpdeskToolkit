function Test-AppAutoStart {
    <#
    .SYNOPSIS
        Tells whether the application is set to start with Windows.
    .DESCRIPTION
        It is when its shortcut lies in the Startup folder of the user (see
        Get-AutoStartPath). The shortcut itself is the setting; nothing about it is
        kept in the settings file, so turning it off in Windows is seen here too.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    Test-Path -LiteralPath (Get-AutoStartPath) -PathType Leaf
}
