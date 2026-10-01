Set-StrictMode -Version Latest

$script:ModuleRoot = $PSScriptRoot
$script:Thresholds = $null

# One function per file. Public functions are exported, private ones are internal helpers.
$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1')
$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1')

foreach ($file in ($private + $public)) {
    . $file.FullName
}

Export-ModuleMember -Function $public.BaseName
