function Invoke-NvidiaSmi {
    <#
    .SYNOPSIS
        Asks nvidia-smi, the status tool of the NVIDIA graphics driver, for values of the graphics cards.
    .DESCRIPTION
        The NVIDIA driver installs nvidia-smi.exe into the System32 folder. It only
        reads the sensors of the card and needs no administrator rights.

        The tool is started from System32 by its full path and never searched for in
        the PATH: a program with the same name placed somewhere else must not be run.

        Returns the output lines (one per graphics card, values separated by commas),
        or nothing when the tool is not installed or fails.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # Comma-separated list of the fields to read, for example "name,temperature.gpu".
        [Parameter(Mandatory)]
        [string]$Query
    )

    $path = Join-Path -Path $env:SystemRoot -ChildPath 'System32\nvidia-smi.exe'
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $lines = & $path "--query-gpu=$Query" '--format=csv,noheader,nounits' 2>$null
    if ($LASTEXITCODE -eq 0) {
        $lines
    }
}
