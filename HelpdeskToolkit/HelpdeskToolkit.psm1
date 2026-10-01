Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:Thresholds = $null
$script:Descriptions = $null
$script:HealthCheckWindow = $null

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
