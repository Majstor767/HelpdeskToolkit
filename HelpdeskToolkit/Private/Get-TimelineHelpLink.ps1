function Get-TimelineHelpLink {
    <#
    .SYNOPSIS
        Returns the address of a web search for a problem of the time line, or nothing.
    .DESCRIPTION
        The problems on the time line (see Get-ChangeTimeline) are errors Windows has
        no place to fix: a program that crashed or stopped responding, an update that
        failed, a blue screen, a computer that went off without a shutdown. What a
        technician does with them is look them up, so each of them becomes a link to
        a web search for exactly that error:

        Program crashed              "<program> crash exception code <code>"
        Program stopped responding   "<program> not responding"
        Update failed                "Windows update KB<number> failed to install
                                     error <code>", or the name of the update when
                                     it has no number
        Windows crashed              "Windows stop code <code>"
        Unexpected shutdown          "Windows unexpected shutdown event 6008"

        The name of the program or the update goes into the search only as
        ConvertTo-SearchName lets it; without a usable name the search is for the
        kind of error and its code. The code is taken only in its fixed shape
        (0x and eight hexadecimal digits). A change (an installation, an update that
        worked) is no error and gets no link.

        Returns the address, or an empty text. Nothing is opened here.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        # An entry of the time line, as Get-ChangeTimeline or a report returns it.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Entry
    )

    if (-not $Entry -or -not $Entry.PSObject.Properties['Level'] -or [string]$Entry.Level -ne 'Problem') {
        return ''
    }

    $title = if ($Entry.PSObject.Properties['Title']) { [string]$Entry.Title } else { '' }
    $name = ConvertTo-SearchName -Name $title
    # A report saved by an earlier version has no code.
    $code = ''
    if ($Entry.PSObject.Properties['Code'] -and [string]$Entry.Code -match '^0x[0-9A-Fa-f]{8}$') {
        $code = '0x{0}' -f ([string]$Entry.Code).Substring(2).ToUpperInvariant()
    }

    $kind = if ($Entry.PSObject.Properties['Kind']) { [string]$Entry.Kind } else { '' }
    $words = switch ($kind) {
        'Program crashed' {
            $subject = if ($name) { '{0} crash' -f $name } else { 'Windows program crash Application Error 1000' }
            if ($code) { '{0} exception code {1}' -f $subject, $code } else { $subject }
        }
        'Program stopped responding' {
            if ($name) { '{0} not responding' -f $name } else { 'Windows program not responding Application Hang 1002' }
        }
        'Update failed' {
            $subject = if ($title -match '\bKB(\d{6,8})\b') {
                'Windows update KB{0} failed to install' -f $Matches[1]
            }
            elseif ($name) {
                '{0} update failed' -f $name
            }
            else {
                'Windows update failed to install'
            }
            if ($code) { '{0} error {1}' -f $subject, $code } else { $subject }
        }
        'Windows crashed (blue screen)' {
            if ($code) { 'Windows stop code {0}' -f $code } else { 'Windows blue screen stop code' }
        }
        'Unexpected shutdown' {
            'Windows unexpected shutdown event 6008'
        }
        default {
            ''
        }
    }
    if (-not $words) {
        return ''
    }
    Get-SearchAddress -Words $words
}
