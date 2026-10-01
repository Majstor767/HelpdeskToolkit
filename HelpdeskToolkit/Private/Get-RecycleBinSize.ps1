function Get-RecycleBinSize {
    <#
    .SYNOPSIS
        Returns the size of the current user's Recycle Bin on all fixed drives.
    .DESCRIPTION
        Every drive keeps deleted files in a hidden folder $Recycle.Bin, with one
        subfolder per user named after the security identifier (SID) of that user. A
        user can read the own subfolder without administrator rights, so its size is
        measured with Get-FolderSize. Returns an object with Bytes and Complete.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [int]$TimeoutMs = 3000
    )

    $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $bytes = [long]0
    $complete = $true

    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady }
    foreach ($drive in $drives) {
        $folder = Join-Path -Path $drive.RootDirectory.FullName -ChildPath ('$Recycle.Bin\{0}' -f $sid)
        $size = Get-FolderSize -Path $folder -TimeoutMs $TimeoutMs
        $bytes += $size.Bytes
        if (-not $size.Complete) {
            $complete = $false
        }
    }

    [PSCustomObject]@{
        Bytes    = $bytes
        Complete = $complete
    }
}
