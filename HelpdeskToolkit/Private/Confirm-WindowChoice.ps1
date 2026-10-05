function Confirm-WindowChoice {
    <#
    .SYNOPSIS
        Asks the user a yes-or-no question in a message box of the window.
    .DESCRIPTION
        Used before the one thing the window starts that changes the computer: the
        uninstaller of a program (see Open-WindowUninstall). "No" is the answer that
        Enter and Esc give, so nothing is started by a key pressed by accident.

        A function of its own, so the tests can answer the question instead of a
        person. Returns $true for "Yes".
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Text
    )

    $answer = [System.Windows.MessageBox]::Show($Gui.Window, $Text, $Title,
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question, [System.Windows.MessageBoxResult]::No)
    $answer -eq [System.Windows.MessageBoxResult]::Yes
}
