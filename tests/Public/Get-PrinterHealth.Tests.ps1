BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    # The test configuration treats a document waiting longer than 10 minutes as stuck.
    Set-TestThreshold
}

Describe 'Get-PrinterHealth' {
    BeforeAll {
        Mock -ModuleName HelpdeskToolkit Get-CimInstance { throw "Unexpected CIM query: $ClassName" }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Printer' } {
            [PSCustomObject]@{ Name = 'Office Laser'; Default = $true; WorkOffline = $false }
            [PSCustomObject]@{ Name = 'Microsoft Print to PDF'; Default = $false; WorkOffline = $false }
        }
        Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PrintJob' } { }
    }

    Context 'with working printers and an empty queue' {
        BeforeAll {
            $results = Get-PrinterHealth
        }

        It 'reports <Check> as <Status> with value "<Value>"' -ForEach @(
            @{ Check = 'Default printer'; Status = 'Info'; Value = 'Office Laser' }
            @{ Check = 'Installed printers'; Status = 'Info'; Value = '2 printers: Microsoft Print to PDF, Office Laser' }
            @{ Check = 'Print queue'; Status = 'OK'; Value = '0 documents waiting' }
        ) {
            $result = $results | Where-Object Check -eq $Check
            $result.Status | Should -Be $Status
            $result.Value | Should -Be $Value
        }
    }

    Context 'with a printer that is set to work offline' {
        It 'is a Warning that names the offline printer' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Printer' } {
                [PSCustomObject]@{ Name = 'Office Laser'; Default = $true; WorkOffline = $true }
                [PSCustomObject]@{ Name = 'Label Printer'; Default = $false; WorkOffline = $false }
            }
            $printers = Get-PrinterHealth | Where-Object Check -eq 'Installed printers'
            $printers.Status | Should -Be 'Warning'
            $printers.Value | Should -Be '2 printers, 1 offline: Label Printer, Office Laser (offline)'
            $printers.Recommendation | Should -Match 'Use Printer Offline'
        }
    }

    Context 'without printers' {
        It 'reports that no printer is installed and none is the default' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Printer' } { }
            $results = Get-PrinterHealth
            ($results | Where-Object Check -eq 'Default printer').Value | Should -Be 'None set'
            ($results | Where-Object Check -eq 'Installed printers').Value | Should -Be 'No printers installed'
        }
    }

    Context 'print queue' {
        It 'is OK while documents are printing normally' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PrintJob' } {
                [PSCustomObject]@{ Document = 'Report.docx'; StatusMask = 16; TimeSubmitted = (Get-Date).AddMinutes(-1) }
            }
            $queue = Get-PrinterHealth | Where-Object Check -eq 'Print queue'
            $queue.Status | Should -Be 'OK'
            $queue.Value | Should -Be '1 document waiting'
        }

        It 'is a Warning when a document is in an error state' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PrintJob' } {
                [PSCustomObject]@{ Document = 'Invoice.pdf'; StatusMask = 2; TimeSubmitted = (Get-Date).AddMinutes(-1) }
                [PSCustomObject]@{ Document = 'Report.docx'; StatusMask = 0; TimeSubmitted = (Get-Date).AddMinutes(-1) }
            }
            $queue = Get-PrinterHealth | Where-Object Check -eq 'Print queue'
            $queue.Status | Should -Be 'Warning'
            $queue.Value | Should -Be '2 documents waiting, 1 stuck: Invoice.pdf'
            $queue.Recommendation | Should -Match 'Print Spooler'
        }

        It 'is a Warning when a document has been waiting longer than the limit' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_PrintJob' } {
                [PSCustomObject]@{ Document = 'Old.pdf'; StatusMask = 0; TimeSubmitted = (Get-Date).AddMinutes(-45) }
            }
            (Get-PrinterHealth | Where-Object Check -eq 'Print queue').Status | Should -Be 'Warning'
        }
    }

    Context 'when the printers cannot be queried' {
        It 'reports them as unavailable and still checks the queue' {
            Mock -ModuleName HelpdeskToolkit Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Printer' } { throw 'The print service is not running' }
            $results = Get-PrinterHealth
            ($results | Where-Object Check -eq 'Installed printers').Value | Should -Be 'Unavailable'
            ($results | Where-Object Check -eq 'Print queue').Status | Should -Be 'OK'
        }
    }
}
