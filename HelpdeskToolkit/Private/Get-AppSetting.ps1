function Get-AppSetting {
    <#
    .SYNOPSIS
        Returns the settings of the application window.
    .DESCRIPTION
        Reads settings.json from the application folder (see Get-AppDataPath) and fills
        in the default for everything that is missing, so the caller always gets a
        complete table. A missing or damaged file simply yields the defaults.

        The settings:
        - Language:               "en" or "hr". The default is Croatian on a Windows
                                  that is set to Croatian and English everywhere else.
        - Theme:                  "System" (same as Windows), "Light" or "Dark"
        - MonitorIntervalSeconds: how often the Live monitor measures
        - AutoCheckMinutes:       how often the check is repeated in the background
                                  after the first one; 0 turns that off
        - WindowWidth, WindowHeight, WindowLeft, WindowTop, WindowMaximized:
                                  where the window was when it was closed
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $settings = @{
        Language               = if ((Get-UICulture).Name -like 'hr*') { 'hr' } else { 'en' }
        Theme                  = 'System'
        MonitorIntervalSeconds = 2
        AutoCheckMinutes       = 5
        WindowWidth            = $null
        WindowHeight           = $null
        WindowLeft             = $null
        WindowTop              = $null
        WindowMaximized        = $false
    }

    $path = Get-AppDataPath -ChildPath 'settings.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $stored = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($name in @($settings.Keys)) {
                $property = $stored.PSObject.Properties[$name]
                if ($property -and $null -ne $property.Value) {
                    $settings[$name] = $property.Value
                }
            }
        }
        catch {
            Write-Verbose "The settings file cannot be read; the defaults are used: $($_.Exception.Message)"
        }
    }

    # Values that came from a file somebody edited by hand must not break the window.
    if ($settings.Language -notin 'en', 'hr') {
        $settings.Language = 'en'
    }
    if ($settings.Theme -notin 'System', 'Light', 'Dark') {
        $settings.Theme = 'System'
    }
    if ($settings.MonitorIntervalSeconds -notin 2, 5, 10, 30) {
        $settings.MonitorIntervalSeconds = 2
    }
    if ($settings.AutoCheckMinutes -notin 0, 5, 15, 30, 60) {
        $settings.AutoCheckMinutes = 5
    }

    $settings
}
