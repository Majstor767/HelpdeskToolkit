function ConvertTo-HtmlEncodedText {
    <#
    .SYNOPSIS
        Escapes text so it can be placed safely inside an HTML document.
    .DESCRIPTION
        Values in the report come from the computer being checked (service names,
        event sources, adapter descriptions). Characters such as < > & " are replaced
        with HTML entities so a value can never break the page or inject markup.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Text
    )

    [System.Net.WebUtility]::HtmlEncode($Text)
}
