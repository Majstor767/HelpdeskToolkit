function Save-AppSetting {
    <#
    .SYNOPSIS
        Writes the settings of the application window to settings.json.
    .DESCRIPTION
        The counterpart of Get-AppSetting. The file is written as UTF-8 without a byte
        order mark into the application folder, which is created when needed. A
        failure to write (a full disk, a read-only profile) is not worth stopping the
        window for: the function returns $false and the settings are simply not
        remembered.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # The table returned by Get-AppSetting, with the changed values.
        [Parameter(Mandatory)]
        [hashtable]$Setting
    )

    try {
        $folder = Get-AppDataPath
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
        }

        $json = [PSCustomObject]$Setting | ConvertTo-Json
        $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
        [System.IO.File]::WriteAllText((Get-AppDataPath -ChildPath 'settings.json'), $json, $encoding)
        $true
    }
    catch {
        Write-Verbose "The settings could not be saved: $($_.Exception.Message)"
        $false
    }
}
