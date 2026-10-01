function Format-AllowedRange {
    <#
    .SYNOPSIS
        Describes the range of values that is reported as OK, for example "0 - 85 %".
    .DESCRIPTION
        The text is built from the same limits Get-ThresholdStatus uses, so the range
        shown in the report can never disagree with the status of the check, and it
        follows automatically when a limit in Config\Thresholds.psd1 is changed.

        By default higher is worse, so the range starts at 0 and ends at -Warning.
        With -LowerIsWorse it starts at -Warning and ends at -Maximum.
    .EXAMPLE
        Format-AllowedRange -Warning 85 -Critical 95 -Unit '%'

        Returns "0 - 85 % (critical above 95 %)".
    .EXAMPLE
        Format-AllowedRange -Warning 15 -Critical 5 -Unit '% free' -LowerIsWorse

        Returns "15 - 100 % free (critical below 5 % free)".
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Warning,

        [Nullable[double]]$Critical,

        [string]$Unit = '',

        [switch]$LowerIsWorse,

        [double]$Maximum = 100
    )

    $suffix = if ($Unit) { ' {0}' -f $Unit } else { '' }

    if ($LowerIsWorse) {
        $text = '{0} - {1}{2}' -f [string]$Warning, [string]$Maximum, $suffix
        if ($null -ne $Critical) {
            $text = '{0} (critical below {1}{2})' -f $text, [string]$Critical, $suffix
        }
    }
    else {
        $text = if ($Warning -eq 0) { '0{0}' -f $suffix } else { '0 - {0}{1}' -f [string]$Warning, $suffix }
        if ($null -ne $Critical) {
            $text = '{0} (critical above {1}{2})' -f $text, [string]$Critical, $suffix
        }
    }

    $text
}
