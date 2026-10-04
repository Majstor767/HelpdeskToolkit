function Initialize-AppIdentity {
    <#
    .SYNOPSIS
        Tells Windows that this process is HelpdeskToolkit, so the taskbar shows the icon of the application.
    .DESCRIPTION
        The window runs inside Windows PowerShell. Without anything else the taskbar
        takes it for a PowerShell window: it shows the PowerShell icon and puts the
        window into one group with open PowerShell consoles.

        Windows tells applications apart by their "application user model ID". This
        function gives the process an ID of its own ($script:AppUserModelId) before
        the window is created. The taskbar then treats the window as an application
        of its own and shows the icon of the window, which is the icon of
        HelpdeskToolkit. The shortcuts the installer creates carry the same ID (see
        installer\HelpdeskToolkit.iss), so a window that is pinned to the taskbar is
        started through them again.

        The call goes to shell32.dll (SetCurrentProcessExplicitAppUserModelID). Its
        declaration is built in memory, which takes a few milliseconds; compiling it
        with Add-Type would cost every start of the application half a second.

        Only this process is affected, and only while it runs. Returns $true when
        Windows accepted the ID.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        if (-not $script:AppIdentityType) {
            $name = New-Object -TypeName System.Reflection.AssemblyName -ArgumentList 'HelpdeskToolkit.Native'
            $assembly = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($name, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
            $type = $assembly.DefineDynamicModule('Native').DefineType('HelpdeskToolkit.Native.Shell', [System.Reflection.TypeAttributes]'Public, Class')

            # int SetCurrentProcessExplicitAppUserModelID(string appId), with the text as Unicode
            $method = $type.DefinePInvokeMethod('SetCurrentProcessExplicitAppUserModelID', 'shell32.dll',
                [System.Reflection.MethodAttributes]'Public, Static, PinvokeImpl', [System.Reflection.CallingConventions]::Standard,
                [int], [type[]]@([string]), [System.Runtime.InteropServices.CallingConvention]::Winapi,
                [System.Runtime.InteropServices.CharSet]::Unicode)
            $method.SetImplementationFlags([System.Reflection.MethodImplAttributes]::PreserveSig)

            $script:AppIdentityType = $type.CreateType()
        }

        # 0 is S_OK
        $script:AppIdentityType::SetCurrentProcessExplicitAppUserModelID($script:AppUserModelId) -eq 0
    }
    catch {
        Write-Verbose "The application ID could not be set; the taskbar shows the PowerShell icon: $($_.Exception.Message)"
        $false
    }
}
