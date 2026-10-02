function Get-OutlookDataFile {
    <#
    .SYNOPSIS
        Returns the mailbox files of Outlook (.ost and .pst) of the signed-in user, with their sizes.
    .DESCRIPTION
        Outlook keeps a copy of an Exchange or Microsoft 365 mailbox in an .ost file
        and archives or POP accounts in .pst files. They are looked for in the two
        folders Outlook uses by default:

        %LOCALAPPDATA%\Microsoft\Outlook     (.ost, and .pst of older versions)
        Documents\Outlook Files              (.pst)

        A file that was moved somewhere else is not found. Only the names and sizes
        are read, never the content.

        Returns one object per file with Name and Bytes.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    $folders = @(
        Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Outlook'
        Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'Outlook Files'
    )

    foreach ($folder in $folders) {
        if (-not (Test-Path -LiteralPath $folder)) {
            continue
        }

        Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in '.ost', '.pst' } |
            ForEach-Object {
                [PSCustomObject]@{
                    Name  = [string]$_.Name
                    Bytes = [long]$_.Length
                }
            }
    }
}
