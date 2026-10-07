function Limit-WindowToScreen {
    <#
    .SYNOPSIS
        Makes the window fit the screen it opens on.
    .DESCRIPTION
        The window is designed for 1180 by 860 units. A laptop often has less: a screen
        of 1366 by 768, or a larger one that Windows scales to 150 %, leaves about 680
        to 730 units of height after the taskbar. A window that is taller than that
        opens with its title bar above the screen or its lower edge below it, where
        neither can be reached with the mouse.

        A window that is larger than the area is made as large as the area. Where the
        area is even smaller than the smallest size the window allows, that smallest
        size gives way and the window is put into the top left corner of the area, so
        at least its title bar and its buttons are there.

        Sizes are in the units of WPF, which already take the scaling of Windows into
        account. Returns $true when the window was changed.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only sets the size of the own window before it is shown.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Windows.Window]$Window,

        # The part of the screen the window may use. The default is the main screen
        # without the taskbar.
        [System.Windows.Rect]$Area = [System.Windows.SystemParameters]::WorkArea
    )

    if ($Area.IsEmpty -or $Area.Width -le 0 -or $Area.Height -le 0) {
        return $false
    }

    $changed = $false

    if ($Window.MinWidth -gt $Area.Width -or $Window.MinHeight -gt $Area.Height) {
        $Window.MinWidth = [math]::Min($Window.MinWidth, $Area.Width)
        $Window.MinHeight = [math]::Min($Window.MinHeight, $Area.Height)
        $Window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
        $Window.Left = $Area.Left
        $Window.Top = $Area.Top
        $changed = $true
    }

    if ($Window.Width -gt $Area.Width) {
        $Window.Width = $Area.Width
        $changed = $true
    }
    if ($Window.Height -gt $Area.Height) {
        $Window.Height = $Area.Height
        $changed = $true
    }

    $changed
}
