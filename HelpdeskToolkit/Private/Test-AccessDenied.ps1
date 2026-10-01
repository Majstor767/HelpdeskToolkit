function Test-AccessDenied {
    <#
    .SYNOPSIS
        Returns $true when an error was caused by missing permissions.
    .DESCRIPTION
        Different APIs report "access denied" in different ways: .NET throws
        UnauthorizedAccessException, CIM/WMI sets NativeErrorCode, and COM-based
        commands return the HRESULT 0x80070005.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception

    if ($exception -is [System.UnauthorizedAccessException]) {
        return $true
    }

    if ($exception -is [Microsoft.Management.Infrastructure.CimException] -and
        $exception.NativeErrorCode -eq 'AccessDenied') {
        return $true
    }

    # 0x80070005 (E_ACCESSDENIED) as a signed 32-bit integer.
    $exception.HResult -eq -2147024891
}
