<#
.SYNOPSIS
    Starts the HelpdeskToolkit window.
.DESCRIPTION
    Used by Start-HelpdeskToolkit.cmd and by the Start menu shortcut that the
    installer creates. It loads the module from the folder next to this file and opens
    the window.

    Both start this script through "conhost.exe --headless", so there is no console
    window at all and an error would go unnoticed. Any failure is therefore shown in a
    message box.
.PARAMETER RunCheck
    Start the check as soon as the window is open, without asking about administrator
    rights. The window uses it when it starts itself again.
.PARAMETER NoQuestion
    Do not ask about administrator rights.
.PARAMETER Background
    Start without a window, as an icon next to the clock, and run the check with
    standard rights. Used by the shortcut that starts the application with Windows.
.EXAMPLE
    .\Start-HelpdeskToolkit.ps1

    Opens the window, which asks about administrator rights and runs the check.
#>
[CmdletBinding()]
param(
    [switch]$RunCheck,

    [switch]$NoQuestion,

    [switch]$Background
)

try {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1'
    Import-Module -Name $manifest -ErrorAction Stop
    Show-PCHealthCheck -RunCheck:$RunCheck -NoQuestion:$NoQuestion -Background:$Background
}
catch {
    Add-Type -AssemblyName PresentationFramework
    $message = "HelpdeskToolkit could not be started.`n`n{0}" -f $_.Exception.Message
    [void][System.Windows.MessageBox]::Show($message, 'HelpdeskToolkit', 'OK', 'Error')
    exit 1
}
