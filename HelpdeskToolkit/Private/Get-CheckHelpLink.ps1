function Get-CheckHelpLink {
    <#
    .SYNOPSIS
        Returns where the problem of a check, and every error it names, is explained on the web.
    .DESCRIPTION
        The recommendation of a result says what to do in one or two sentences. For
        whoever wants to understand the problem, the window offers links:

        - "Page": the page of the maker that explains the problem and how it is
          fixed, when Config\Help.psd1 lists one. It is looked up like the texts of
          Get-CheckRisk: by the full name of the check, by the part before the first
          colon or parenthesis ("Disk (C:)" -> "Disk"), by the part before " - "
          ("Firewall - Public profile" -> "Firewall"), for a service by
          "Service:<name>" with the name in parentheses, and at last by the category.
        - "Event": for every line of the details that names an event of the event log
          ("Microsoft-Windows-DistributedCOM 10016 (45)", see Get-EventLogHealth), a
          web search for that event by its number and its source. That is what an
          administrator types into a search engine to find out what an event means
          and how it is fixed.
        - "Article": for every update named by its number ("KB5050009"), the article
          of Microsoft about that update.
        - "Code": for every error code in the value or the details, a web search for
          that code: a Windows error ("0x80070005"), the stop code of a blue screen,
          or the code Device Manager gives a device ("code 28").
        - "Search": without a page and without events, a web search for the name of
          the check.

        What goes into an address is the name of a check, the source and the number of
        an event, the number of an update, or an error code. Those are taken from the
        text by their fixed shape (digits and hexadecimal digits only), so a name of a
        program, a user or a drive can never become part of an address.

        Returns objects with Kind, Url and Text (the number of the update or the code),
        and for an event Line (the line of the details), Id, Source and Count. Nothing
        is opened here; that is done by Open-WindowHelpLink.
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
        [string[]]$Detail = @(),

        # The value of the result. Only numbers of updates and error codes are read from it.
        [AllowEmptyString()]
        [string]$Value = ''
    )

    if (-not $script:Help) {
        $script:Help = Import-PowerShellDataFile -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Help.psd1')
    }

    $search = {
        param([string]$Words)
        ([string]$script:Help.SearchUrl) -f [uri]::EscapeDataString($Words)
    }
    $newLink = {
        param([string]$Kind, [string]$Url, [string]$Text = '')
        [PSCustomObject]@{ Kind = $Kind; Url = $Url; Text = $Text; Line = ''; Id = ''; Source = ''; Count = 0 }
    }

    $short = $Check -replace '\s*[:(].*$', ''
    $keys = @($Check, $short, ($Check -replace '\s+-\s+.*$', ''))
    $service = ''
    if ($Category -eq 'Services' -and $Check -match '\(([^()]+)\)\s*$') {
        $service = $Matches[1]
        $keys += 'Service:{0}' -f $service
    }
    if ($Category) {
        $keys += 'Category:{0}' -f $Category
    }

    $page = ''
    foreach ($key in $keys) {
        if (-not $page -and $key -and $script:Help.Pages.ContainsKey($key)) {
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
        & $newLink 'Page' $page
    }

    # "<source> <number> (<how often>)", as Get-EventLogHealth writes it
    $events = @(
        foreach ($line in $Detail) {
            if ($line -match '^(?<source>\S.*) (?<id>\d+) \((?<count>\d+)\)$') {
                [PSCustomObject]@{
                    Kind   = 'Event'
                    Url    = & $search ('Windows event ID {0} {1}' -f $Matches['id'], $Matches['source'])
                    Text   = ''
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

    # Numbers of updates and error codes, each once, in the order they are named. A card
    # with a dozen links helps nobody, so only the first few of each kind get one.
    $text = (@($Value) + @($Detail | Where-Object { $_ -notmatch '^\S.* \d+ \(\d+\)$' })) -join "`n"
    $most = 3

    $articles = @([regex]::Matches($text, '\bKB(\d{6,8})\b') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Select-Object -First $most)
    foreach ($number in $articles) {
        & $newLink 'Article' ([string]$script:Help.ArticleUrl -f $number) ('KB{0}' -f $number)
    }

    $words = if ($Check -eq 'Blue screens') {
        'Windows stop code {0}'
    }
    elseif ($Category -eq 'Windows Update') {
        'Windows Update error {0}'
    }
    else {
        'Windows error {0}'
    }
    $codes = @([regex]::Matches($text, '\b0x[0-9A-Fa-f]{8}\b') | ForEach-Object { '0x{0}' -f $_.Value.Substring(2).ToUpperInvariant() } |
            Select-Object -Unique | Select-Object -First $most)
    foreach ($code in $codes) {
        & $newLink 'Code' (& $search ($words -f $code)) $code
    }

    if ($Check -eq 'Devices with problems') {
        $deviceCodes = @([regex]::Matches($text, '\(code (\d{1,2})\)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Select-Object -First $most)
        foreach ($code in $deviceCodes) {
            & $newLink 'Code' (& $search ('Device Manager error code {0}' -f $code)) ('code {0}' -f $code)
        }
    }

    if (-not $page -and $events.Count -eq 0) {
        # The name of a service says little to a search engine without the word "service".
        $subject = if ($service) { 'Windows service {0} not running' -f $service } else { 'Windows {0}' -f ($Check -replace '\s*\(.*$', '') }
        & $newLink 'Search' (& $search $subject)
    }
}
