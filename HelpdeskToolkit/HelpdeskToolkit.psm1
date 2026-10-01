Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:Thresholds = $null
$script:Descriptions = $null
$script:HealthCheckWindow = $null
$script:VideoMemoryCache = $null
$script:DriveHealthCache = $null
# Only set when the functions were sent to another computer, where there is no manifest
# to read the version from (see Get-ToolVersion).
$script:ToolVersion = $null
# Where the checks lead to in Windows (Config\Actions.psd1), read on first use.
$script:Actions = $null
# Language of the window ("en" or "hr") and the translations of that language.
$script:Language = 'en'
$script:Translations = $null
# Replaces the folder for the files of the application itself; used by the tests.
$script:AppDataRoot = $null

# Name of the progress bar of a run. The window uses it to tell the progress of the
# health check apart from progress written by Windows cmdlets.
$script:ProgressActivity = 'PC Health Check'

# One function per file. Public functions are exported, private ones are internal helpers.
$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1')
$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1')

foreach ($file in ($private + $public)) {
    . $file.FullName
}

Export-ModuleMember -Function $public.BaseName
