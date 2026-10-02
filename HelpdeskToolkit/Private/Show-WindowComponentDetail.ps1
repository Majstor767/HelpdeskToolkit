function Show-WindowComponentDetail {
    <#
    .SYNOPSIS
        Draws the lower part of the detail page of a component: everything that was read about it.
    .DESCRIPTION
        Shows the sections Get-ComponentDetail returned for the component whose page
        is open, and says in the line next to the "Back" button when they were read.
        Until the first reading is there the line says that it is under way; a reading
        that failed is reported there as well.

        The sections come from a background runspace that works in English. They are
        translated here: the titles and the names of the lines, and values that are
        words ("Yes", "None"). Two kinds of text stay as they are:

        - the lines of a "raw" section, which list what Windows reports under the
          names Windows uses; only its title says so in the language of the window
        - names that are data and not labels, such as the name of a program or a
          display (the section says so with KeepNames)
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui
    )

    $name = $Gui.MonitorComponent
    if (-not $name) {
        return
    }

    $controls = $Gui.Controls
    $state = $Gui.ComponentDetail[$name]
    $seconds = [int](Get-HealthThreshold).Monitor.DetailRefreshSeconds

    if (-not $state -or -not $state.Detail) {
        $controls.ComponentSections.ItemsSource = @()
        $controls.ComponentState.Text = if ($state -and $state.State -eq 'Failed') {
            (Get-LocalizedText 'The details could not be read: {0}') -f $state.Error
        }
        else {
            Get-LocalizedText 'Reading the details ...'
        }
        return
    }

    $controls.ComponentState.Text = if ($state.State -eq 'Failed') {
        # The sections of the last reading that worked stay on the screen.
        (Get-LocalizedText 'The details could not be read: {0}') -f $state.Error
    }
    else {
        (Get-LocalizedText 'Details read at {0:HH:mm:ss}; they are read again every {1} seconds.') -f $state.Detail.ReadAt, $seconds
    }

    $controls.ComponentSections.ItemsSource = @(
        foreach ($section in @($state.Detail.Sections)) {
            if ($section.Raw) {
                [PSCustomObject]@{
                    Title = (Get-LocalizedText 'Everything Windows reports: {0}') -f $section.Title
                    Rows  = @($section.Rows | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Text = $_.Text; Percent = [double]0; Meter = '' } })
                }
            }
            else {
                $keepNames = [bool]$section.KeepNames
                [PSCustomObject]@{
                    # "Module: DIMM1" is translated by its first part, like the name of a check.
                    Title = Get-LocalizedCheckName $section.Title
                    Rows  = @(
                        $section.Rows | ForEach-Object {
                            [PSCustomObject]@{
                                Name    = if ($keepNames) { $_.Name } else { Get-LocalizedText $_.Name }
                                Text    = Get-LocalizedText $_.Text
                                Percent = [double]0
                                Meter   = ''
                            }
                        }
                    )
                }
            }
        }
    )
}
