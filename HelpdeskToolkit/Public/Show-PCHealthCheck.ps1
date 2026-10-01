function Show-PCHealthCheck {
    <#
    .SYNOPSIS
        Opens the HelpdeskToolkit window for running the health check with the mouse.
    .DESCRIPTION
        Shows a window with a "Run check" button and a list of categories (System,
        Hardware, Network and so on). The Overview page lists every problem with its
        recommended fix; choosing a category shows all of its checks, each with an
        explanation, the allowed range and the typical value. The report can be opened
        in the browser as HTML or saved as HTML or JSON.

        The window runs exactly the same checks as Invoke-PCHealthCheck; it only
        presents them differently. The checks run in the background, so the window
        stays responsive. Nothing on the computer is changed.

        No administrator rights are needed. Checks that need them are marked "Requires
        admin"; the "Restart as administrator" button starts the window again
        elevated, after the user has confirmed the Windows prompt, and then includes them.

        The command returns when the window is closed.
    .PARAMETER OutputPath
        Folder used by the "Open HTML report" button. It is created when needed.
        Defaults to a HelpdeskToolkit folder inside the current user's Documents.
    .EXAMPLE
        Show-PCHealthCheck

        Opens the window.
    .EXAMPLE
        Show-PCHealthCheck -OutputPath C:\Temp\Reports

        Opens the window; reports opened from it are saved to C:\Temp\Reports.
    .OUTPUTS
        None.
    #>
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$OutputPath = (Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'HelpdeskToolkit')
    )

    # WPF windows can only be created on a single-threaded apartment (STA) thread.
    # powershell.exe and pwsh.exe start that way unless they were launched with -MTA.
    if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
        throw 'Show-PCHealthCheck needs a single-threaded (STA) PowerShell session. Start PowerShell without the -MTA switch.'
    }

    $gui = New-HealthCheckWindow
    $gui.ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'HelpdeskToolkit.psd1'
    $gui.OutputFolder = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutputPath)

    # The event handlers below run later, when a button is clicked. They reach the
    # window through this module-level variable.
    $script:HealthCheckWindow = $gui

    $controls = $gui.Controls
    $controls.ComputerText.Text = 'Computer: {0}' -f $env:COMPUTERNAME

    # Polls the background check a few times per second (see Receive-WindowCheck).
    $gui.Timer = New-Object -TypeName System.Windows.Threading.DispatcherTimer
    $gui.Timer.Interval = [timespan]::FromMilliseconds(200)
    $gui.Timer.Add_Tick({ Receive-WindowCheck -Gui $script:HealthCheckWindow })

    $controls.RunButton.Add_Click({ Invoke-WindowCheck -Gui $script:HealthCheckWindow })

    # With administrator rights there is nothing left to elevate.
    if (Test-IsAdministrator) {
        $controls.ElevationText.Text = 'Running as administrator: all checks are included.'
        $controls.ElevateButton.Visibility = [System.Windows.Visibility]::Collapsed
    }
    $controls.ElevateButton.Add_Click({ [void](Invoke-ElevatedRestart -Gui $script:HealthCheckWindow) })

    # Choosing an entry in the category list shows that page on the right.
    $controls.CategoryList.Add_SelectionChanged({ Show-WindowPage -Gui $script:HealthCheckWindow })

    # Saves the report as HTML in the output folder and opens it in the browser.
    $controls.OpenReportButton.Add_Click({
            $state = $script:HealthCheckWindow
            try {
                if (-not (Test-Path -LiteralPath $state.OutputFolder)) {
                    New-Item -Path $state.OutputFolder -ItemType Directory -Force | Out-Null
                }
                $fileName = '{0}.html' -f (Get-ReportFileName -Report $state.Report)
                $path = Export-HealthReportHtml -Report $state.Report -Path (Join-Path -Path $state.OutputFolder -ChildPath $fileName)
                Open-HealthReport -Path $path
                $state.Controls.StatusText.Text = 'Report saved: {0}' -f $path
            }
            catch {
                $state.Controls.StatusText.Text = 'The report could not be saved: {0}' -f $_.Exception.Message
            }
        })

    # Lets the user choose the place, the name and the format (HTML or JSON).
    $controls.SaveAsButton.Add_Click({
            $state = $script:HealthCheckWindow
            $dialog = New-Object -TypeName Microsoft.Win32.SaveFileDialog
            $dialog.Title = 'Save report'
            $dialog.Filter = 'HTML report (*.html)|*.html|JSON data (*.json)|*.json'
            $dialog.FileName = Get-ReportFileName -Report $state.Report

            if ($dialog.ShowDialog($state.Window)) {
                try {
                    if ([System.IO.Path]::GetExtension($dialog.FileName) -eq '.json') {
                        $path = Export-HealthReportJson -Report $state.Report -Path $dialog.FileName
                    }
                    else {
                        $path = Export-HealthReportHtml -Report $state.Report -Path $dialog.FileName
                    }
                    $state.Controls.StatusText.Text = 'Report saved: {0}' -f $path
                }
                catch {
                    $state.Controls.StatusText.Text = 'The report could not be saved: {0}' -f $_.Exception.Message
                }
            }
        })

    # Closing the window while a check is running stops the background work.
    $gui.Window.Add_Closed({
            $state = $script:HealthCheckWindow
            $state.Timer.Stop()
            if ($state.Worker) {
                [void]$state.Worker.BeginStop($null, $null)
            }
        })

    try {
        [void]$gui.Window.ShowDialog()
    }
    finally {
        $script:HealthCheckWindow = $null
    }
}
