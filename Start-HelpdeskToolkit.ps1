<#
.SYNOPSIS
    Starts the HelpdeskToolkit window.
.DESCRIPTION
    Used by Start-HelpdeskToolkit.cmd and by the Start menu shortcut that the
    installer creates. It loads the module from the folder next to this file and opens
    the window.

    The console window is hidden when the application is started this way, so an
    error would otherwise go unnoticed. Any failure is therefore shown in a message box.
.EXAMPLE
    .\Start-HelpdeskToolkit.ps1

    Opens the window.
#>
[CmdletBinding()]
param()

try {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath 'HelpdeskToolkit\HelpdeskToolkit.psd1'
    Import-Module -Name $manifest -ErrorAction Stop
    Show-PCHealthCheck
}
catch {
    Add-Type -AssemblyName PresentationFramework
    $message = "HelpdeskToolkit could not be started.`n`n{0}" -f $_.Exception.Message
    [void][System.Windows.MessageBox]::Show($message, 'HelpdeskToolkit', 'OK', 'Error')
    exit 1
}
