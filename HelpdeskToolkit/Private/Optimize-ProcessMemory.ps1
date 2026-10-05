function Optimize-ProcessMemory {
    <#
    .SYNOPSIS
        Gives memory the application no longer needs back to Windows.
    .DESCRIPTION
        The application is meant to stay open for hours, also unseen next to the clock,
        so it must not keep memory it only needed for a moment.

        .NET frees what is no longer used when it sees a reason to, and an idle window
        gives it none: the data of a report that was replaced can stay around for a
        long time. This function asks for that clean-up at the moments where a lot
        became free, for example after a check. Large blocks are moved together once,
        so the freed space between them can be returned too.

        With -Trim the process also hands back the memory it holds but does not use
        right now (its "working set"). Windows keeps those pages and gives them back
        the moment they are touched, so nothing is lost; it is used while the window
        is hidden, where nobody waits for it to be quick.

        Only this process is affected. Nothing happens to other programs, and nothing
        on the computer is changed. Returns nothing; a failure only leaves the memory
        as it was.
    #>
    [CmdletBinding()]
    param(
        # Also hands back the memory the process holds but does not use right now.
        [switch]$Trim
    )

    try {
        [System.Runtime.GCSettings]::LargeObjectHeapCompactionMode = [System.Runtime.GCLargeObjectHeapCompactionMode]::CompactOnce
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()

        if (-not $Trim) {
            return
        }

        if (-not $script:MemoryNativeType) {
            # bool K32EmptyWorkingSet(IntPtr process), declared in memory like the call
            # in Initialize-AppIdentity: compiling it would cost half a second.
            $name = New-Object -TypeName System.Reflection.AssemblyName -ArgumentList 'HelpdeskToolkit.NativeMemory'
            $assembly = [System.Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly($name, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
            $type = $assembly.DefineDynamicModule('NativeMemory').DefineType('HelpdeskToolkit.Native.Memory', [System.Reflection.TypeAttributes]'Public, Class')
            $method = $type.DefinePInvokeMethod('K32EmptyWorkingSet', 'kernel32.dll',
                [System.Reflection.MethodAttributes]'Public, Static, PinvokeImpl', [System.Reflection.CallingConventions]::Standard,
                [bool], [type[]]@([IntPtr]), [System.Runtime.InteropServices.CallingConvention]::Winapi,
                [System.Runtime.InteropServices.CharSet]::Unicode)
            $method.SetImplementationFlags([System.Reflection.MethodImplAttributes]::PreserveSig)
            $script:MemoryNativeType = $type.CreateType()
        }

        $process = [System.Diagnostics.Process]::GetCurrentProcess()
        try {
            [void]$script:MemoryNativeType::K32EmptyWorkingSet($process.Handle)
        }
        finally {
            $process.Dispose()
        }
    }
    catch {
        Write-Verbose "The memory could not be handed back: $($_.Exception.Message)"
    }
}
