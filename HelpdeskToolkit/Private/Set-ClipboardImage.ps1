function Set-ClipboardImage {
    <#
    .SYNOPSIS
        Puts a picture on the clipboard.
    .DESCRIPTION
        A thin wrapper around the clipboard of Windows, so the tests can replace it and
        leave the clipboard of the person running them alone. The picture stays on the
        clipboard after the application is closed.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Copies to the clipboard at the request of the user, like Ctrl+C.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Media.Imaging.BitmapSource]$Image
    )

    $data = New-Object -TypeName System.Windows.DataObject
    $data.SetImage($Image)
    [System.Windows.Clipboard]::SetDataObject($data, $true)
}
