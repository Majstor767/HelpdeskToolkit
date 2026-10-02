function Get-CimPropertyValue {
    <#
    .SYNOPSIS
        Returns the value of a property the way Windows reported it, not the way PowerShell shows it.
    .DESCRIPTION
        Some modules of Windows change how the objects of their WMI classes look. Once
        the Storage module is loaded (Get-PhysicalDisk does that), the property
        MediaType of a drive is no longer the number 4 but the text "SSD", and
        HealthStatus is "Healthy" instead of 0. Whether the module is loaded depends on
        what ran earlier in the same process, so the same line of code can work in one
        check and fail in the next one with "Cannot convert value "SSD" to type Int32".

        The value Windows itself reported is always there, below that layer. This
        function reads it from there.

        An object that is not a CIM instance (the tests use plain objects) simply
        returns its property. A property that does not exist returns nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return
    }

    $instance = if ($InputObject -is [psobject]) { $InputObject.PSObject.BaseObject } else { $InputObject }
    if ($instance -is [Microsoft.Management.Infrastructure.CimInstance]) {
        $property = $instance.CimInstanceProperties[$Name]
        if ($property) {
            return $property.Value
        }
        return
    }

    $member = $InputObject.PSObject.Properties[$Name]
    if ($member) {
        $member.Value
    }
}
