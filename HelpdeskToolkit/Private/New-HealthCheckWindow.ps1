function New-HealthCheckWindow {
    <#
    .SYNOPSIS
        Creates the application window from Assets\MainWindow.xaml without showing it.
    .DESCRIPTION
        The window is built with WPF, which is part of Windows, so nothing has to be
        installed. The XAML file describes the layout; this function loads it and
        returns one table that the other window functions pass around:

        - Window:   the window object
        - Controls: every element that has an x:Name in the XAML, by that name
        - Report, Worker, Handle, Timer: state of the current run, filled in later
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds a window object in memory; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $path = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\MainWindow.xaml'
    [xml]$xaml = Get-Content -LiteralPath $path -Raw
    $reader = New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # Without an icon of its own the window would show the PowerShell icon.
    $iconPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Assets\HelpdeskToolkit.ico'
    if (Test-Path -LiteralPath $iconPath) {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object -TypeName System.Uri -ArgumentList $iconPath))
    }

    # Collect the named elements, so the code can write $controls.RunButton
    # instead of calling FindName everywhere.
    $xamlNamespace = 'http://schemas.microsoft.com/winfx/2006/xaml'
    $namespaces = New-Object -TypeName System.Xml.XmlNamespaceManager -ArgumentList $xaml.NameTable
    $namespaces.AddNamespace('x', $xamlNamespace)

    $controls = @{}
    foreach ($node in $xaml.SelectNodes('//*[@x:Name]', $namespaces)) {
        $name = $node.GetAttribute('Name', $xamlNamespace)
        $element = $window.FindName($name)
        # Names inside a template belong to that template and cannot be found on the window.
        if ($element) {
            $controls[$name] = $element
        }
    }

    @{
        Window   = $window
        Controls = $controls
        Report   = $null
        Worker   = $null
        Handle   = $null
        Timer    = $null
    }
}
