function Get-CheckHelpLink {
    <#
    .SYNOPSIS
        Returns where the problem of a check, and every error it names, is explained on the web.
    .DESCRIPTION
        The recommendation of a result says what to do in one or two sentences. For
        whoever wants to understand the problem, the window and the HTML report offer
        links:

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
        - "Program": for every program the result "Application crashes" names, a web
          search for the crashes of that program. Windows has no place where a
          program of another maker is repaired; what helps is what others found out
          about the same crash.
        - "Search": without a page and without events, a web search for the name of
          the check.

        A check that could not be read (-ErrorText) is no finding, so it gets no page
        and no search for its name; it gets a search for every error code its error
        names, because that code is all there is to go by.

        What goes into an address is the name of a check, the source and the number of
        an event, the number of an update, an error code, or the name of a program
        that crashed. Numbers and codes are taken from the text by their fixed shape
        (digits and hexadecimal digits only), the name of a program only as
        ConvertTo-SearchName lets it, so a user, a computer, a folder or a drive can
        never become part of an address.

        Returns objects with Kind, Url and Text (the number of the update, the code or
        the name of the program). A link that belongs to a line of the details has
        that line as Line, and an event its Id, Source and Count. Nothing is opened
        here; that is done by Open-WindowHelpLink.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Check,

        [string]$Category = '',

        # The details of the result; lines that name an event or a program get a link of their own.
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Detail = @(),

        # The value of the result. Numbers of updates, error codes and the programs that crashed are read from it.
        [AllowEmptyString()]
        [string]$Value = '',

        # The error of a check that could not be read. Only error codes are read from it.
        [AllowEmptyString()]
        [string]$ErrorText = ''
    )

    if (-not $script:Help) {
        $script:Help = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Help.psd1')
    }

    $newLink = {
        param([string]$Kind, [string]$Url, [string]$Text = '', [string]$Line = '', [int]$Count = 0)
        [PSCustomObject]@{ Kind = $Kind; Url = $Url; Text = $Text; Line = $Line; Id = ''; Source = ''; Count = $Count }
    }
    # Error codes in their fixed shape, each once, in the order they are named.
    $findCodes = {
        param([string]$Text, [int]$Most)
        @([regex]::Matches($Text, '\b0x[0-9A-Fa-f]{8}\b') | ForEach-Object { '0x{0}' -f $_.Value.Substring(2).ToUpperInvariant() } |
                Select-Object -Unique | Select-Object -First $Most)
    }
    # A card with a dozen links helps nobody, so only the first few of each kind get one.
    $most = 3

    if ($ErrorText) {
        foreach ($code in & $findCodes $ErrorText $most) {
            & $newLink 'Code' (Get-SearchAddress -Words ('Windows error {0}' -f $code)) $code
        }
        return
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

    # The lines of "Application crashes" read "<program> (<how often>)"; a program
    # whose name ends in a number must not be taken for an event.
    $crashes = $Check -eq 'Application crashes'

    # "<source> <number> (<how often>)", as Get-EventLogHealth writes it
    $eventLine = '^(?<source>\S.*) (?<id>\d+) \((?<count>\d+)\)$'
    $events = @(
        if (-not $crashes) {
            foreach ($line in $Detail) {
                if ($line -match $eventLine) {
                    [PSCustomObject]@{
                        Kind   = 'Event'
                        Url    = Get-SearchAddress -Words ('Windows event ID {0} {1}' -f $Matches['id'], $Matches['source'])
                        Text   = ''
                        Line   = $line
                        Id     = $Matches['id']
                        Source = $Matches['source'] -replace '^Microsoft-Windows-', ''
                        Count  = [int]$Matches['count']
                    }
                }
            }
        }
    )
    foreach ($found in $events) {
        $found
    }

    # Numbers of updates and error codes, each once, in the order they are named.
    $text = (@($Value) + @($Detail | Where-Object { $crashes -or $_ -notmatch $eventLine })) -join "`n"

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
    foreach ($code in & $findCodes $text $most) {
        & $newLink 'Code' (Get-SearchAddress -Words ($words -f $code)) $code
    }

    if ($Check -eq 'Devices with problems') {
        $deviceCodes = @([regex]::Matches($text, '\(code (\d{1,2})\)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Select-Object -First $most)
        foreach ($code in $deviceCodes) {
            & $newLink 'Code' (Get-SearchAddress -Words ('Device Manager error code {0}' -f $code)) ('code {0}' -f $code)
        }
    }

    if ($crashes) {
        $programWords = '{0} crash Windows'
        # The value names the programs that crash most, after the colon:
        # "12 in the last 7 days: contoso.exe (10), fabrikam.exe (2) and 3 more"
        $named = @()
        if ($Value -match ':\s*(?<list>.+)$') {
            $named = @([regex]::Matches($Matches['list'], '(?<name>[^,]+?) \(\d+\)') | ForEach-Object { ConvertTo-SearchName -Name $_.Groups['name'].Value } |
                    Where-Object { $_ } | Select-Object -Unique | Select-Object -First $most)
        }
        foreach ($name in $named) {
            & $newLink 'Program' (Get-SearchAddress -Words ($programWords -f $name)) $name
        }
        # The rest of them, one per line of the details
        foreach ($line in $Detail) {
            if ($line -match '^(?<name>.+) \((?<count>\d+)\)$') {
                $count = [int]$Matches['count']
                $name = ConvertTo-SearchName -Name $Matches['name']
                if ($name) {
                    & $newLink 'Program' (Get-SearchAddress -Words ($programWords -f $name)) $name $line $count
                }
            }
        }
    }

    if (-not $page -and $events.Count -eq 0) {
        # The name of a service says little to a search engine without the word "service".
        $subject = if ($service) { 'Windows service {0} not running' -f $service } else { 'Windows {0}' -f ($Check -replace '\s*\(.*$', '') }
        & $newLink 'Search' (Get-SearchAddress -Words $subject)
    }
}
