function Get-CheckHelpLink {
    <#
    .SYNOPSIS
        Returns where the problem of a check, and every event it lists, is explained on the web.
    .DESCRIPTION
        The recommendation of a result says what to do in one or two sentences. For
        whoever wants to understand the problem, the window offers links:

        - "Page": the page of the maker that explains the problem and how it is
          fixed, when Config\Help.psd1 lists one. It is looked up like the
          descriptions: by the full name of the check, then by the part before the
          first colon or parenthesis ("Disk (C:)" -> "Disk"), and at last by the
          category.
        - "Event": for every line of the details that names an event of the event log
          ("Microsoft-Windows-DistributedCOM 10016 (45)", see Get-EventLogHealth), a
          web search for that event by its number and its source. That is what an
          administrator types into a search engine to find out what an event means
          and how it is fixed.
        - "Search": without a page and without events, a web search for the name of
          the check.

        What goes into an address is the name of a check, or the source and the
        number of an event. The value of a result, which can name programs, users or
        drives, never does.

        Returns objects with Kind, Url and, for an event, Line (the line of the
        details), Id, Source and Count. Nothing is opened here; that is done by
        Open-WindowHelpLink.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Category = '',

        # The details of the result; lines that name an event get a link of their own.
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Detail = @()
    )

    if (-not $script:Help) {
        $script:Help = Import-PowerShellDataFile -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Help.psd1')
    }

    $search = {
        param([string]$Words)
        ([string]$script:Help.SearchUrl) -f [uri]::EscapeDataString($Words)
    }

    $keys = @($Check, ($Check -replace '\s*[:(].*$', ''))
    if ($Category) {
        $keys += 'Category:{0}' -f $Category
    }
    $page = ''
    foreach ($key in $keys) {
        if (-not $page -and $script:Help.Pages.ContainsKey($key)) {
            $entry = $script:Help.Pages[$key]
            $page = if ($entry -is [hashtable]) {
                # Windows 11 starts at build 22000.
                if ([Environment]::OSVersion.Version.Build -ge 22000) { [string]$entry.Windows11 } else { [string]$entry.Windows10 }
            }
            else {
                [string]$entry
            }
        }
    }
    if ($page) {
        [PSCustomObject]@{ Kind = 'Page'; Url = $page; Line = ''; Id = ''; Source = ''; Count = 0 }
    }

    # "<source> <number> (<how often>)", as Get-EventLogHealth writes it
    $events = @(
        foreach ($line in $Detail) {
            if ($line -match '^(?<source>\S.*) (?<id>\d+) \((?<count>\d+)\)$') {
                [PSCustomObject]@{
                    Kind   = 'Event'
                    Url    = & $search ('Windows event ID {0} {1}' -f $Matches['id'], $Matches['source'])
                    Line   = $line
                    Id     = $Matches['id']
                    Source = $Matches['source'] -replace '^Microsoft-Windows-', ''
                    Count  = [int]$Matches['count']
                }
            }
        }
    )
    foreach ($found in $events) {
        $found
    }

    if (-not $page -and $events.Count -eq 0) {
        [PSCustomObject]@{
            Kind = 'Search'; Url = & $search ('Windows {0}' -f ($Check -replace '\s*\(.*$', '')); Line = ''; Id = ''; Source = ''; Count = 0
        }
    }
}
