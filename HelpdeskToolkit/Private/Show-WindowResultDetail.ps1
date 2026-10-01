function Show-WindowResultDetail {
    <#
    .SYNOPSIS
        Shows the details of one result in the panel below the result list.
    .DESCRIPTION
        The list only has room for the status, the check and the value. Everything
        else a result carries is shown here when its row is selected: the description
        of the check, the allowed range, the typical value, the remaining items of a
        long list and the recommendation. Rows of the panel without a value are hidden.
    #>
    [CmdletBinding()]
    param(
        # The table returned by New-HealthCheckWindow.
        [Parameter(Mandatory)]
        [hashtable]$Gui,

        # The selected result; nothing when the selection was cleared.
        [AllowNull()]
        [PSCustomObject]$Result
    )

    $controls = $Gui.Controls

    if (-not $Result) {
        $controls.DetailTitle.Text = 'Select a row to see what the check means.'
        $controls.DetailDescription.Text = ''
        $values = @{ Result = ''; Allowed = ''; Typical = ''; More = ''; Recommendation = '' }
    }
    else {
        $controls.DetailTitle.Text = '{0} - {1}' -f $Result.Category, $Result.Check
        $controls.DetailDescription.Text = $Result.Description
        $values = @{
            Result         = $Result.Value
            Allowed        = $Result.Allowed
            Typical        = $Result.Typical
            More           = @($Result.Details) -join ', '
            Recommendation = $Result.Recommendation
        }
    }

    # Each detail is a label and a value next to it; both are hidden when there is no value.
    foreach ($name in $values.Keys) {
        $visibility = if ($values[$name]) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $controls["Detail$name"].Text = [string]$values[$name]
        $controls["Detail$name"].Visibility = $visibility
        $controls["Detail${name}Label"].Visibility = $visibility
    }
}
