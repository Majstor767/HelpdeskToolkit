function Get-ComponentDetail {
    <#
    .SYNOPSIS
        Returns everything that can be read about one component: processor, memory or graphics card.
    .DESCRIPTION
        The Live monitor shows a detail page when one of its tiles is clicked. This
        function collects what that page lists below the live values:

        - Name:     "Cpu", "Memory" or "Gpu"
        - ReadAt:   when the values were read
        - Sections: titles with lines of a name and a value (see Get-ProcessorDetail,
                    Get-MemoryDetail and Get-GraphicsDetail)

        The first sections are chosen and named for people. The last ones, marked as
        raw, list every property Windows reports under the name Windows gives it, so
        nothing that is available is left out.

        Some of the sources measure for a moment before they answer, so the window
        runs this function in the background and repeats it every few seconds while
        the page is open.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Cpu', 'Memory', 'Gpu')]
        [string]$Name
    )

    $sections = switch ($Name) {
        'Cpu' { Get-ProcessorDetail }
        'Memory' { Get-MemoryDetail }
        'Gpu' { Get-GraphicsDetail }
    }

    [PSCustomObject]@{
        Name     = $Name
        ReadAt   = Get-Date
        Sections = @($sections | Where-Object { $_ })
    }
}
