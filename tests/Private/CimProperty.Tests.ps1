# Tests for reading a WMI property the way Windows reported it. The Storage module of
# Windows, once it is loaded in a process, shows the type of a drive as the text "SSD"
# instead of the number 4; the checks have to keep working then.

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    # A drive as WMI returns it, and then what the Storage module turns it into.
    function Get-TestDrive {
        $drive = New-CimInstance -Namespace 'root/Microsoft/Windows/Storage' -ClassName MSFT_PhysicalDisk -ClientOnly -Property @{
            DeviceId = '0'; FriendlyName = 'Contoso SSD 512'; MediaType = [uint16]4; BusType = [uint16]17
            Size = [uint64]512GB; FirmwareVersion = 'FW2.1'; HealthStatus = [uint16]0
        }
        Add-TestStorageText -Drive $drive -Name MediaType -Text 'SSD'
        Add-TestStorageText -Drive $drive -Name BusType -Text 'NVMe'
        Add-TestStorageText -Drive $drive -Name HealthStatus -Text 'Healthy'
        $drive
    }
}

Describe 'Get-CimPropertyValue' {
    It 'returns the number Windows reported, not the text shown in its place' {
        $drive = Get-TestDrive
        # What a check sees when it asks the object directly
        $drive.MediaType | Should -Be 'SSD'

        InModuleScope HelpdeskToolkit -Parameters @{ Drive = $drive } {
            Get-CimPropertyValue -InputObject $Drive -Name MediaType | Should -Be 4
            Get-CimPropertyValue -InputObject $Drive -Name BusType | Should -Be 17
            Get-CimPropertyValue -InputObject $Drive -Name HealthStatus | Should -Be 0
            Get-CimPropertyValue -InputObject $Drive -Name FriendlyName | Should -Be 'Contoso SSD 512'
        }
    }

    It 'returns the property of an object that is not a CIM instance' {
        InModuleScope HelpdeskToolkit {
            Get-CimPropertyValue -InputObject ([PSCustomObject]@{ MediaType = 3 }) -Name MediaType | Should -Be 3
        }
    }

    It 'returns nothing for a property that does not exist, and for no object' {
        $drive = Get-TestDrive
        InModuleScope HelpdeskToolkit -Parameters @{ Drive = $drive } {
            Get-CimPropertyValue -InputObject $Drive -Name NoSuchProperty | Should -BeNullOrEmpty
            Get-CimPropertyValue -InputObject ([PSCustomObject]@{ A = 1 }) -Name NoSuchProperty | Should -BeNullOrEmpty
            Get-CimPropertyValue -InputObject $null -Name MediaType | Should -BeNullOrEmpty
        }
    }
}
