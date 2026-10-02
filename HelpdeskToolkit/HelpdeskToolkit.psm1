Set-StrictMode -Version Latest

# Windows PowerShell inherits the module search path of the program that started it.
# When that program is PowerShell 7, or was itself started from PowerShell 7 (an
# installer, a .cmd file, a terminal), the path lists the modules of PowerShell 7
# first. Windows PowerShell then loads built-in modules that are not its own, and
# commands such as Import-PowerShellDataFile and Get-FileHash are missing.
#
# Those entries are of no use to Windows PowerShell, so they are taken off the search
# path of this process (nothing outside the process changes), and a built-in module
# that was loaded from the wrong place already is loaded again from the right one.
if ($PSVersionTable.PSEdition -ne 'Core') {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, [Environment]::GetFolderPath('MyDocuments')) |
        Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) }
    # "<root>\PowerShell\Modules", "<root>\PowerShell\7\Modules" and the copy from the Microsoft Store
    $foreign = '^({0})\\PowerShell\\(\d[^\\]*\\)?Modules\\?$|\\WindowsApps\\Microsoft\.PowerShell_[^\\]+\\Modules\\?$' -f ($roots -join '|')

    $entries = @($env:PSModulePath -split ';' | Where-Object { $_ })
    $own = @($entries | Where-Object { $_ -notmatch $foreign })
    if ($own.Count -lt $entries.Count) {
        $env:PSModulePath = $own -join ';'

        foreach ($name in 'Microsoft.PowerShell.Utility', 'Microsoft.PowerShell.Management', 'CimCmdlets') {
            $wrong = Get-Module -Name $name | Where-Object { $_.Version.Major -ge 6 }
            $manifest = Join-Path -Path $PSHOME -ChildPath "Modules\$name\$name.psd1"
            if ($wrong -and (Test-Path -LiteralPath $manifest)) {
                Import-Module -Name $manifest -Force -Global
            }
        }
    }
}

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
# Why a problem matters (Config\Risks.psd1), read on first use.
$script:Risks = $null
# Programs that no longer get security updates (Config\EndOfLife.psd1), read on first use.
$script:EndOfLife = $null
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
