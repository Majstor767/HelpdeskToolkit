function Get-RemoteModuleScript {
    <#
    .SYNOPSIS
        Builds the script that makes the functions of this module available on another computer.
    .DESCRIPTION
        The other computer does not have HelpdeskToolkit installed. To run the checks
        there anyway, the source of all functions is sent along and loaded into the
        memory of the remote PowerShell session; nothing is written to its disk.

        The script that is returned consists of:

        - the variables the module keeps (the "$script:" lines of HelpdeskToolkit.psm1)
        - the source of every function in the Private and Public folders
        - three lines that take the configuration and the version from the parameters
          of the script, because the configuration files are not there either
        - the list of programs without support (Config\EndOfLife.psd1), written into
          the script as text for the same reason

        It expects three arguments: the text of Thresholds.psd1, the text of
        Descriptions.psd1 and the version of the tool.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $parts = New-Object -TypeName 'System.Collections.Generic.List[string]'
    # The parameters of a module script live in the same scope as the $script: variables,
    # so their names must differ from those.
    $parts.Add('param($RemoteThresholdText, $RemoteDescriptionText, $RemoteToolVersion)')
    $parts.Add('Set-StrictMode -Version Latest')

    # The variables of the module, taken from the module file itself so that a
    # variable added there later cannot be forgotten here.
    $moduleFile = Join-Path -Path $script:ModuleRoot -ChildPath 'HelpdeskToolkit.psm1'
    foreach ($line in [System.IO.File]::ReadAllLines($moduleFile)) {
        if ($line -match '^\$script:\w+\s*=') {
            $parts.Add($line)
        }
    }

    foreach ($folder in 'Private', 'Public') {
        $files = Get-ChildItem -Path (Join-Path -Path $script:ModuleRoot -ChildPath $folder) -Filter '*.ps1' | Sort-Object -Property Name
        foreach ($file in $files) {
            $parts.Add([System.IO.File]::ReadAllText($file.FullName))
        }
    }

    $parts.Add('$script:Thresholds = ConvertFrom-DataFileText -Text $RemoteThresholdText')
    $parts.Add('$script:Descriptions = ConvertFrom-DataFileText -Text $RemoteDescriptionText')
    $parts.Add('$script:ToolVersion = $RemoteToolVersion')

    # A here-string keeps the text of the file as it is; no line of it starts with '@.
    $endOfLife = [System.IO.File]::ReadAllText((Join-Path -Path $script:ModuleRoot -ChildPath 'Config\EndOfLife.psd1'))
    $parts.Add("`$script:EndOfLife = @((ConvertFrom-DataFileText -Text @'`n$endOfLife`n'@).Products)")

    $parts -join "`n"
}
