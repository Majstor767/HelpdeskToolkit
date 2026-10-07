function Get-StartupSource {
    <#
    .SYNOPSIS
        Returns the places where Windows looks for programs to start at sign-in, each with the place of its on/off switches.
    .DESCRIPTION
        A program starts with Windows because it has a value under one of the "Run"
        keys of the registry or a shortcut in one of the two Startup folders. Whether
        such an entry is switched on is kept elsewhere: under "StartupApproved" in
        the same part of the registry. That is the switch Task Manager and the
        Settings page "Startup apps" turn.

        Returns one table per place:
        - Scope:    "User" (this user) or "Machine" (every user; changing it needs
                    administrator rights)
        - Source:   "Run", "Run32" (32-bit programs on 64-bit Windows) or
                    "StartupFolder"
        - Path:     the registry key, or nothing for a folder
        - Folder:   the Startup folder, or nothing for a registry key
        - Approved: the registry key with the switches of this place

        A function of its own so the tests can point it at a registry and a folder of
        their own.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $run = 'Software\Microsoft\Windows\CurrentVersion\Run'
    $approved = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

    @{ Scope = 'User'; Source = 'Run'; Path = "HKCU:\$run"; Folder = ''; Approved = "HKCU:\$approved\Run" }
    @{ Scope = 'Machine'; Source = 'Run'; Path = "HKLM:\$run"; Folder = ''; Approved = "HKLM:\$approved\Run" }
    @{ Scope = 'Machine'; Source = 'Run32'; Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Folder = ''; Approved = "HKLM:\$approved\Run32" }
    @{ Scope = 'User'; Source = 'StartupFolder'; Path = ''; Folder = [Environment]::GetFolderPath('Startup'); Approved = "HKCU:\$approved\StartupFolder" }
    @{ Scope = 'Machine'; Source = 'StartupFolder'; Path = ''; Folder = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$approved\StartupFolder" }
}
