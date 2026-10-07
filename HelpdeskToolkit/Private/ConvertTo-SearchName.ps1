function ConvertTo-SearchName {
    <#
    .SYNOPSIS
        Returns the name of a program or an update as it may become part of a web search, or nothing.
    .DESCRIPTION
        A search for a program that crashes is useless without the name of the
        program, so that name is the one thing besides numbers and error codes that
        may go into the address of a search (see Get-SearchAddress). This function
        decides what counts as such a name:

        - Of a path only the file name is kept: the folders above it can name a user.
        - The name must be letters, digits, spaces and . _ + ( ) - , ' & only, and at
          most 100 characters long. An address, an e-mail address, a command line or
          a whole sentence is no name.
        - A name that contains the name of the signed-in user or of this computer is
          refused.

        Returns the name, or an empty text when it is refused; the caller then
        searches without it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Name
    )

    $text = ([string]$Name).Trim()
    if ($text -match '[\\/]') {
        $text = ([string]($text -split '[\\/]')[-1]).Trim()
    }
    if ($text -notmatch "^[\p{L}\p{N}][\p{L}\p{N} ._+(),'&-]{0,99}$") {
        return ''
    }

    # Very short names are left out of the comparison: they are part of too many words.
    foreach ($private in @([string]$env:USERNAME, [string]$env:COMPUTERNAME)) {
        if ($private.Length -ge 3 -and $text.IndexOf($private, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return ''
        }
    }
    $text
}
