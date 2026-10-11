function Get-FeedbackSetting {
    <#
    .SYNOPSIS
        Returns where feedback is sent to, and whether it can be sent at all.
    .DESCRIPTION
        Reads Config\Feedback.psd1 once per session. Feedback is switched on only when
        the file names an address that begins with https:// and has nothing in it
        that does not belong into an address; anything else, an empty value included,
        switches it off, and the window then shows no button for it.

        Returns an object with
        - Enabled:        whether feedback can be sent
        - Endpoint:       the address of the form at the form service
        - Service:        the name of the computer in that address ("formspree.io"),
                          which the form shows to the user
        - Fields:         what every message carries besides the text (see the file)
        - MaximumLength:  the longest text, in characters
        - TimeoutSeconds: how long to wait for the service
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    if (-not $script:Feedback) {
        $script:Feedback = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $script:ModuleRoot -ChildPath 'Config\Feedback.psd1')
    }
    $config = $script:Feedback

    $endpoint = ([string]$config['Endpoint']).Trim()
    $service = ''
    if ($endpoint -match '^https://[^\s"<>]+$') {
        $uri = $null
        if ([uri]::TryCreate($endpoint, [System.UriKind]::Absolute, [ref]$uri) -and $uri.Host -match '\.') {
            $service = $uri.Host
        }
    }

    $fields = @{}
    if ($config['Fields'] -is [hashtable]) {
        foreach ($key in $config['Fields'].Keys) {
            $fields[[string]$key] = [string]$config['Fields'][$key]
        }
    }

    $length = 0
    if (-not [int]::TryParse([string]$config['MaximumLength'], [ref]$length) -or $length -lt 100) {
        $length = 4000
    }
    $timeout = 0
    if (-not [int]::TryParse([string]$config['TimeoutSeconds'], [ref]$timeout) -or $timeout -lt 5) {
        $timeout = 20
    }

    [PSCustomObject]@{
        Enabled        = [bool]$service
        Endpoint       = if ($service) { $endpoint } else { '' }
        Service        = $service
        Fields         = $fields
        MaximumLength  = $length
        TimeoutSeconds = $timeout
    }
}
