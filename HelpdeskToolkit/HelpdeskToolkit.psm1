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
# The runspaces that read several WMI classes at the same time (see Get-CimInstanceBatch).
$script:CimPool = $null
$script:DriveHealthCache = $null
# Only set when the functions were sent to another computer, where there is no manifest
# to read the version from (see Get-ToolVersion).
$script:ToolVersion = $null
# Where the checks lead to in Windows (Config\Actions.psd1), read on first use.
$script:Actions = $null
# Why a problem matters (Config\Risks.psd1), read on first use.
$script:Risks = $null
# Where a problem is explained on the web (Config\Help.psd1), read on first use.
$script:Help = $null
# Programs that no longer get security updates (Config\EndOfLife.psd1), read on first use.
$script:EndOfLife = $null
# Language of the window ("en" or "hr") and the translations of that language.
$script:Language = 'en'
$script:Translations = $null
# Replaces the folder for the files of the application itself; used by the tests.
$script:AppDataRoot = $null
# The name under which Windows knows the window of the application: it makes the taskbar
# show the icon of the application instead of that of PowerShell (see
# Initialize-AppIdentity). The shortcuts of the installer carry the same name.
$script:AppUserModelId = 'Majstor767.HelpdeskToolkit'
$script:AppIdentityType = $null
# Replaces the Startup folder of the user, where the shortcut for starting with Windows
# goes (see Get-AutoStartPath); used by the tests.
$script:AutoStartFolder = $null
# Replaces the number of check categories that run at the same time (see
# Get-PCHealthReport); used by the tests, whose mocks only exist in their own session.
$script:CheckThrottleLimit = $null

# Name of the progress bar of a run. The window uses it to tell the progress of the
# health check apart from progress written by Windows cmdlets.
$script:ProgressActivity = 'PC Health Check'

# One function per file. Public functions are exported, private ones are internal helpers.
$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1')
$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1')

# Loading the files one at a time takes about a second: PowerShell checks and compiles
# every file by itself. Read into one text and loaded as one block, the same functions
# are there in a fifth of that time, which every start of the application and every
# background runspace feels.
#
# The price is that an error then names a line of that block instead of a file. With
# the environment variable HELPDESKTOOLKIT_LOAD_FILES set to 1 the files are loaded one
# by one again; the tests do that, and it is the thing to set while debugging.
if ($env:HELPDESKTOOLKIT_LOAD_FILES -eq '1') {
    foreach ($file in ($private + $public)) {
        . $file.FullName
    }
}
else {
    $source = New-Object -TypeName System.Text.StringBuilder
    foreach ($file in ($private + $public)) {
        [void]$source.AppendLine([System.IO.File]::ReadAllText($file.FullName))
    }
    . ([scriptblock]::Create($source.ToString()))
}

Export-ModuleMember -Function $public.BaseName

# The runspaces of Get-CimInstanceBatch are given back when the module is removed.
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($script:CimPool) {
        $script:CimPool.Dispose()
        $script:CimPool = $null
    }
}
