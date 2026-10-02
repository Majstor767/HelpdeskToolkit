function Get-ProgramDiskUsage {
    <#
    .SYNOPSIS
        Returns the installed programs of one drive with the space each of them takes up.
    .DESCRIPTION
        The programs are the ones of "Installed apps" (see Get-InstalledProgram).

        Which drive: the drive of the folder the installer wrote down. A program
        without such a folder is counted to the drive Windows is on, which is where
        installers put programs unless they are told otherwise.

        How large: the size the installer wrote down. When it wrote none, the folder
        of the program is measured, limited by -TimeoutMs per program and -BudgetMs
        for all of them together; Complete is $false when the time ran out, and Bytes
        is then a lower bound. Folders that many programs share (such as
        "Program Files" itself) are never measured as the size of one program.

        Programs whose size cannot be found out are returned with Bytes $null, so the
        caller can say how many there are. Only the registry and file sizes are read.

        Returns objects with Name, Version, Bytes and Complete, largest first.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Drive letter with colon, for example "C:".
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]:$')]
        [string]$Drive,

        [int]$TimeoutMs = 1500,

        [int]$BudgetMs = 10000
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $systemDrive = [string]$env:SystemDrive

    # Folders that belong to more than one program
    $shared = @(
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:CommonProgramFiles, ${env:CommonProgramFiles(x86)},
        $env:ProgramData, $env:windir, (Join-Path -Path ([string]$env:windir) -ChildPath 'System32'),
        $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA
    ) | Where-Object { $_ } | ForEach-Object { ([string]$_).TrimEnd('\') }

    $programs = foreach ($program in Get-InstalledProgram) {
        $location = [string]$program.Location
        $programDrive = if ($location -match '^([A-Za-z]:)') { $Matches[1] } else { $systemDrive }
        if ($programDrive -ne $Drive) {
            continue
        }

        $bytes = $program.SizeBytes
        $complete = $true

        if (-not $bytes -and $location -match '^[A-Za-z]:\\.+' -and $shared -notcontains $location) {
            $remaining = $BudgetMs - $stopwatch.ElapsedMilliseconds
            if ($remaining -gt 0 -and (Test-Path -LiteralPath $location -PathType Container)) {
                $size = Get-FolderSize -Path $location -TimeoutMs ([math]::Min($TimeoutMs, $remaining))
                if ($size.Bytes -gt 0) {
                    $bytes = [long]$size.Bytes
                    $complete = $size.Complete
                }
            }
        }

        [PSCustomObject]@{
            Name     = $program.Name
            Version  = $program.Version
            Bytes    = $bytes
            Complete = $complete
        }
    }

    $programs | Sort-Object -Property @{ Expression = { [long]$_.Bytes }; Descending = $true }, Name
}
