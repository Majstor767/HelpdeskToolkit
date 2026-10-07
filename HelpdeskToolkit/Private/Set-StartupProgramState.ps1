function Set-StartupProgramState {
    <#
    .SYNOPSIS
        Switches a startup program off or on, the way Task Manager does.
    .DESCRIPTION
        One of the few things in this tool that change the computer, and only after
        the user clicked the program and confirmed the question (see
        Switch-WindowStartupProgram).

        Nothing is deleted. The entry of the program stays where it is; what is
        written is its switch under "StartupApproved" in the registry, the same value
        Task Manager and the Settings page "Startup apps" write:

            on:   02 00 00 00  00 00 00 00 00 00 00 00
            off:  03 00 00 00  <the moment it was switched off, as a file time>

        Windows reads the switch at the next sign-in. Task Manager shows the program
        as "Disabled" afterwards and can switch it on again, as can this function.

        The switch of a program that starts for every user lies in the part of the
        registry only administrators can write to; without those rights the function
        throws, as it does when the value cannot be written for another reason.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # A program as returned by Get-StartupProgram.
        [Parameter(Mandatory)]
        [PSCustomObject]$Program,

        # $true switches the program on, $false off.
        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    $value = if ($Enabled) {
        [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    else {
        [byte[]](3, 0, 0, 0) + [System.BitConverter]::GetBytes([datetime]::UtcNow.ToFileTimeUtc())
    }

    $action = if ($Enabled) { 'Switch on at startup' } else { 'Switch off at startup' }
    if (-not $PSCmdlet.ShouldProcess([string]$Program.Name, $action)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Program.Approved)) {
        [void](New-Item -Path $Program.Approved -Force -ErrorAction Stop)
    }
    Set-ItemProperty -LiteralPath $Program.Approved -Name ([string]$Program.Entry) -Value $value -Type Binary -ErrorAction Stop
}
