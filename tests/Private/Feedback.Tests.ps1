# Tests for "Send feedback": the button at the bottom of the side bar, the form it opens,
# what a message contains and how it is handed to the form service.
#
# No test sends anything. The form service of the tests is an address under ".test",
# which exists on no network; the request itself is replaced (Invoke-RestMethod), and
# where the window would start its background work, the tests give it work of their own.

BeforeDiscovery {
    # WPF objects can only be created on a single-threaded apartment (STA) thread.
    $isSta = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '..\TestHelpers.ps1')
    Import-TestModule
    Set-TestThreshold

    $moduleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\..\HelpdeskToolkit'
    $testEndpoint = 'https://forms.example.test/f/abc123'

    # Sets what Config\Feedback.psd1 would say; nothing switches feedback off again.
    function Set-TestFeedback {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only sets a variable of the module under test.')]
        param([string]$Endpoint = $testEndpoint, [hashtable]$Fields = @{}, $MaximumLength = 4000, $TimeoutSeconds = 20)

        InModuleScope HelpdeskToolkit -Parameters @{ Config = @{ Endpoint = $Endpoint; Fields = $Fields; MaximumLength = $MaximumLength; TimeoutSeconds = $TimeoutSeconds } } {
            $script:Feedback = $Config
        }
    }

    function Get-TestSetting {
        InModuleScope HelpdeskToolkit { Get-FeedbackSetting }
    }

    # A window with feedback switched on and the form open.
    function New-TestForm {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only builds a window object in memory.')]
        param([string]$Text = '', [string]$Address = '')

        Set-TestFeedback
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        # A module that does not exist: background work the window starts itself ends at once.
        $gui.ManifestPath = Join-Path -Path $TestDrive -ChildPath 'No such module.psd1'
        $gui.Controls.FeedbackText.Text = $Text
        $gui.Controls.FeedbackAddress.Text = $Address
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowFeedback -Gui $Gui } | Out-Null
        $gui
    }

    # Puts background work of the test in the place of a message that is on its way, and waits until it is done.
    function Set-TestWork {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
            Justification = 'Test helper that only changes a table in memory.')]
        param([hashtable]$Gui, [string]$Script, [switch]$NoWait)

        $worker = [powershell]::Create()
        [void]$worker.AddScript($Script)
        $Gui.FeedbackWorker = $worker
        $Gui.FeedbackHandle = $worker.BeginInvoke()
        $Gui.FeedbackDeadline = (Get-Date).AddSeconds(30)
        if (-not $NoWait) {
            [void]$Gui.FeedbackHandle.AsyncWaitHandle.WaitOne(15000)
        }
    }

    function Invoke-TestReceive {
        param([hashtable]$Gui)
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $Gui } { Receive-WindowFeedback -Gui $Gui }
    }
}

AfterAll {
    InModuleScope HelpdeskToolkit { $script:Feedback = $null }
}

Describe 'Config\Feedback.psd1' {
    BeforeAll {
        $config = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Config\Feedback.psd1')
    }

    It 'names no form service, or one that is reached over https' {
        [string]$config.Endpoint | Should -Match '^(https://[^\s"<>]+)?$'
    }

    It 'contains no e-mail address: the application must not know the one of the author' {
        $text = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Config\Feedback.psd1'))
        $text | Should -Not -Match '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}'
    }

    It 'has a table of fields, a longest text and a timeout' {
        $config.Fields | Should -BeOfType [hashtable]
        [int]$config.MaximumLength | Should -BeGreaterThan 500
        [int]$config.TimeoutSeconds | Should -BeGreaterThan 4
    }
}

Describe 'Get-FeedbackSetting' {
    It 'switches feedback off when no form service is named' {
        Set-TestFeedback -Endpoint ''
        $setting = Get-TestSetting
        $setting.Enabled | Should -BeFalse
        $setting.Endpoint | Should -Be ''
        $setting.Service | Should -Be ''
    }

    It 'switches feedback off for <Why>' -ForEach @(
        @{ Endpoint = 'http://forms.example.test/f/abc'; Why = 'an address that is not encrypted' }
        @{ Endpoint = 'forms.example.test/f/abc'; Why = 'an address without https://' }
        @{ Endpoint = 'https://forms.example.test/f/a b'; Why = 'an address with a space' }
        @{ Endpoint = 'https://localhost/f/abc'; Why = 'a name that is no internet address' }
        @{ Endpoint = 'mailto:someone@example.test'; Why = 'an e-mail address' }
        @{ Endpoint = 'file:///C:/form'; Why = 'a file' }
    ) {
        Set-TestFeedback -Endpoint $Endpoint
        (Get-TestSetting).Enabled | Should -BeFalse
    }

    It 'switches feedback on for an https address and names the service in it' {
        Set-TestFeedback -Endpoint '  https://forms.example.test/f/abc123  '
        $setting = Get-TestSetting
        $setting.Enabled | Should -BeTrue
        $setting.Endpoint | Should -Be 'https://forms.example.test/f/abc123'
        $setting.Service | Should -Be 'forms.example.test'
    }

    It 'returns the fields of the service as texts' {
        Set-TestFeedback -Fields @{ access_key = 'abc-123'; number = 7 }
        $fields = (Get-TestSetting).Fields
        $fields['access_key'] | Should -Be 'abc-123'
        $fields['number'] | Should -Be '7'
    }

    It 'falls back to 4000 characters and 20 seconds when the file says something unusable' {
        Set-TestFeedback -MaximumLength 'many' -TimeoutSeconds 0
        $setting = Get-TestSetting
        $setting.MaximumLength | Should -Be 4000
        $setting.TimeoutSeconds | Should -Be 20
    }

    It 'takes the length and the timeout of the file' {
        Set-TestFeedback -MaximumLength 1500 -TimeoutSeconds 45
        $setting = Get-TestSetting
        $setting.MaximumLength | Should -Be 1500
        $setting.TimeoutSeconds | Should -Be 45
    }
}

Describe 'New-FeedbackMessage: what leaves the computer' {
    BeforeAll {
        function New-TestMessage {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
                Justification = 'Test helper that only builds a table in memory.')]
            param([string]$Text = 'It works well.', [string]$Address = '', [hashtable]$Field = @{})
            InModuleScope HelpdeskToolkit -Parameters @{ Text = $Text; Address = $Address; Field = $Field } { New-FeedbackMessage -Text $Text -Address $Address -Field $Field }
        }
    }

    It 'contains the text, the versions and the language, and nothing else' {
        $message = New-TestMessage -Text "  It works well.`n"
        @($message.Keys) | Should -Be @('message', 'version', 'windows', 'language')
        $message['message'] | Should -Be 'It works well.'
        $message['version'] | Should -Be (InModuleScope HelpdeskToolkit { [string](Get-ToolVersion) })
        $message['windows'] | Should -Match '^\d+\.\d+\.\d+$'
        $message['language'] | Should -BeIn @('en', 'hr')
    }

    It 'carries the address only when one was typed in' {
        (New-TestMessage).Contains('email') | Should -BeFalse
        (New-TestMessage -Address '   ').Contains('email') | Should -BeFalse
        (New-TestMessage -Address ' ana@contoso.example ')['email'] | Should -Be 'ana@contoso.example'
    }

    It 'never names this computer or its user' {
        $message = New-TestMessage -Address 'ana@contoso.example' -Field @{ access_key = 'abc' }
        foreach ($value in $message.Values) {
            if ($env:COMPUTERNAME.Length -ge 3) { $value | Should -Not -Match ([regex]::Escape($env:COMPUTERNAME)) }
            if ($env:USERNAME.Length -ge 3) { $value | Should -Not -Match ([regex]::Escape($env:USERNAME)) }
        }
    }

    It 'adds the fields of the form service' {
        $message = New-TestMessage -Field @{ access_key = 'abc-123'; _subject = 'Feedback' }
        $message['access_key'] | Should -Be 'abc-123'
        $message['_subject'] | Should -Be 'Feedback'
    }

    It 'does not let a field of the configuration replace what the user wrote' {
        $message = New-TestMessage -Text 'Mine' -Address 'ana@contoso.example' -Field @{ message = 'Other'; email = 'other@example.test'; version = '0' }
        $message['message'] | Should -Be 'Mine'
        $message['email'] | Should -Be 'ana@contoso.example'
        $message['version'] | Should -Not -Be '0'
    }
}

Describe 'Send-FeedbackMessage' {
    BeforeAll {
        function Send-TestMessage {
            param($Body = ([ordered]@{ message = 'It works well.' }), [string]$Endpoint = $testEndpoint, [int]$TimeoutSeconds = 20)
            InModuleScope HelpdeskToolkit -Parameters @{ Body = $Body; Endpoint = $Endpoint; TimeoutSeconds = $TimeoutSeconds } {
                Send-FeedbackMessage -Body $Body -Endpoint $Endpoint -TimeoutSeconds $TimeoutSeconds
            }
        }
    }

    It 'posts the message as JSON to the address of the form, over the timeout it was given' {
        Mock -ModuleName HelpdeskToolkit Invoke-RestMethod { [PSCustomObject]@{ ok = $true } }
        (Send-TestMessage -TimeoutSeconds 33).Sent | Should -BeTrue

        Should -Invoke -ModuleName HelpdeskToolkit Invoke-RestMethod -Times 1 -Exactly -Scope It -ParameterFilter {
            $Uri -eq 'https://forms.example.test/f/abc123' -and $Method -eq 'Post' -and $ContentType -eq 'application/json; charset=utf-8' -and
            $Headers['Accept'] -eq 'application/json' -and $TimeoutSec -eq 33 -and $UserAgent -like 'HelpdeskToolkit/*'
        }
    }

    It 'sends the text as UTF-8, so letters of every alphabet arrive as they were written' {
        $script:sentBytes = $null
        Mock -ModuleName HelpdeskToolkit Invoke-RestMethod { $script:sentBytes = $Body; [PSCustomObject]@{ ok = $true } }
        # Croatian letters, a quotation mark, a line break and a backslash
        $text = ('Radi dobro, ali {0}to je s {1}itanjem "diska" C:\?' -f [char]0x0161, [char]0x010D) + "`nDrugi red."
        (Send-TestMessage -Body ([ordered]@{ message = $text; email = 'ana@contoso.example'; version = '1.0.0' })).Sent | Should -BeTrue
        $bytes = $script:sentBytes

        , $bytes | Should -BeOfType [byte[]]
        $read = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
        $read.message | Should -Be $text
        $read.email | Should -Be 'ana@contoso.example'
        $read.version | Should -Be '1.0.0'
    }

    It 'counts the message as sent when the service answers <Case>' -ForEach @(
        @{ Case = 'success: true'; Answer = [PSCustomObject]@{ success = $true; message = 'Email sent' } }
        @{ Case = 'ok: true'; Answer = [PSCustomObject]@{ ok = $true; next = '/thanks' } }
        @{ Case = 'with something else'; Answer = [PSCustomObject]@{ id = 42 } }
        @{ Case = 'with a text'; Answer = 'OK' }
        @{ Case = 'with nothing'; Answer = $null }
    ) {
        Mock -ModuleName HelpdeskToolkit Invoke-RestMethod { $Answer }
        $result = Send-TestMessage
        $result.Sent | Should -BeTrue
        $result.Error | Should -Be ''
    }

    It 'says why when the service refuses the message: <Case>' -ForEach @(
        @{ Case = 'success: false'; Answer = [PSCustomObject]@{ success = $false; message = 'Invalid access key' }; Reason = 'Invalid access key' }
        @{ Case = 'ok: false'; Answer = [PSCustomObject]@{ ok = $false; error = 'Form not found' }; Reason = 'Form not found' }
        @{ Case = 'without a reason'; Answer = [PSCustomObject]@{ success = $false }; Reason = 'The service did not accept the message.' }
    ) {
        Mock -ModuleName HelpdeskToolkit Invoke-RestMethod { $Answer }
        $result = Send-TestMessage
        $result.Sent | Should -BeFalse
        $result.Error | Should -Be $Reason
    }

    It 'returns the failure instead of throwing it when there is no connection' {
        Mock -ModuleName HelpdeskToolkit Invoke-RestMethod { throw 'The remote name could not be resolved.' }
        $result = $null
        { $script:result = Send-TestMessage } | Should -Not -Throw
        $script:result.Sent | Should -BeFalse
        $script:result.Error | Should -Be 'The remote name could not be resolved.'
    }

    It 'sends nothing to an address that is not https' {
        Mock -ModuleName HelpdeskToolkit Invoke-RestMethod { [PSCustomObject]@{ ok = $true } }
        foreach ($endpoint in 'http://forms.example.test/f/abc', 'ftp://forms.example.test/x', 'forms.example.test') {
            (Send-TestMessage -Endpoint $endpoint).Sent | Should -BeFalse
        }
        Should -Invoke -ModuleName HelpdeskToolkit Invoke-RestMethod -Times 0 -Exactly -Scope It
    }
}

Describe 'The button "Send feedback"' -Skip:(-not $isSta) {
    It 'is not shown while no form service is set, so nothing is offered that cannot work' {
        Set-TestFeedback -Endpoint ''
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Controls.FeedbackButton.Visibility | Should -Be 'Collapsed'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowFeedback -Gui $Gui } | Should -BeFalse
        $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MainLayout.IsEnabled | Should -BeTrue
    }

    It 'is shown at the bottom of the side bar when a form service is set' {
        Set-TestFeedback
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        $gui.Controls.FeedbackButton.Visibility | Should -Be 'Visible'
        $gui.Controls.FeedbackButton.Content | Should -Be 'Send feedback'
        # In the same panel as Settings, below it
        $panel = $gui.Controls.SettingsButton.Parent
        $gui.Controls.FeedbackButton.Parent | Should -Be $panel
        $panel.Children.IndexOf($gui.Controls.FeedbackButton) | Should -BeGreaterThan $panel.Children.IndexOf($gui.Controls.SettingsButton)
    }

    It 'reads "Send feedback" in Croatian in a Croatian window' {
        Set-TestFeedback
        $content = InModuleScope HelpdeskToolkit {
            $script:Language = 'hr'
            $script:Translations = $null
            try {
                (New-HealthCheckWindow).Controls.FeedbackButton.Content
            }
            finally {
                $script:Language = 'en'
                $script:Translations = $null
            }
        }
        $content | Should -Not -Be 'Send feedback'
        $content | Should -Match '^Po.alji mi.ljenje$'
        # It has to fit the side bar, like the longest entry that was there before.
        $content.Length | Should -BeLessThan 26
    }
}

Describe 'The form "Send feedback"' -Skip:(-not $isSta) {
    It 'opens over the window, which cannot be used behind it' {
        $gui = New-TestForm
        $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Visible'
        $gui.Controls.MainLayout.IsEnabled | Should -BeFalse
    }

    It 'says what is sent and through which service before anything is sent' {
        $gui = New-TestForm
        $note = $gui.Controls.FeedbackNote.Text
        $note | Should -BeLike 'What is sent: your text, the address if you enter one, and the version of this application (*) and of Windows (*).*'
        $note | Should -BeLike '*not the name of this computer, not your user name and none of the results.*'
        $note | Should -BeLike '*delivered by forms.example.test,*'
    }

    It 'accepts no more text than the configuration allows and counts what is typed' {
        Set-TestFeedback -MaximumLength 1500
        $gui = InModuleScope HelpdeskToolkit { New-HealthCheckWindow }
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowFeedback -Gui $Gui } | Out-Null
        $gui.Controls.FeedbackText.MaxLength | Should -Be 1500
        $gui.Controls.FeedbackCount.Text | Should -Be '0 / 1500'

        $gui.Controls.FeedbackText.Text = 'Twelve chars'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Update-WindowFeedback -Gui $Gui }
        $gui.Controls.FeedbackCount.Text | Should -Be '12 / 1500'
    }

    It 'lets "Send" be clicked only when something is written' {
        $gui = New-TestForm
        $gui.Controls.FeedbackSendButton.IsEnabled | Should -BeFalse

        foreach ($case in @(@('   ', $false), @("`n", $false), @('It works.', $true))) {
            $gui.Controls.FeedbackText.Text = $case[0]
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Update-WindowFeedback -Gui $Gui }
            $gui.Controls.FeedbackSendButton.IsEnabled | Should -Be $case[1]
        }
    }

    It 'is closed by "Cancel" without sending, and keeps what was written for the next time' {
        $gui = New-TestForm -Text 'Half a thought' -Address 'ana@contoso.example'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Close-WindowFeedback -Gui $Gui } | Should -BeTrue

        $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MainLayout.IsEnabled | Should -BeTrue
        $gui.FeedbackWorker | Should -BeNullOrEmpty
        $gui.Controls.FeedbackText.Text | Should -Be 'Half a thought'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Show-WindowFeedback -Gui $Gui } | Should -BeTrue
        $gui.Controls.FeedbackText.Text | Should -Be 'Half a thought'
        $gui.Controls.FeedbackSendButton.IsEnabled | Should -BeTrue
    }

    It 'forgets an earlier complaint when it is opened again' {
        $gui = New-TestForm
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Send-WindowFeedback -Gui $Gui } | Should -BeFalse
        $gui.Controls.FeedbackStatus.Visibility | Should -Be 'Visible'

        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { [void](Close-WindowFeedback -Gui $Gui); Show-WindowFeedback -Gui $Gui } | Out-Null
        $gui.Controls.FeedbackStatus.Visibility | Should -Be 'Collapsed'
        $gui.Controls.FeedbackStatus.Text | Should -Be ''
    }
}

Describe 'Sending from the form' -Skip:(-not $isSta) {
    It 'sends nothing without a text, and says so' {
        $gui = New-TestForm -Text "  `n "
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Send-WindowFeedback -Gui $Gui } | Should -BeFalse
        $gui.FeedbackWorker | Should -BeNullOrEmpty
        $gui.Controls.FeedbackStatus.Text | Should -Be 'Write your message first.'
    }

    It 'sends nothing when the address is no address: <_>' -ForEach @('ana', 'ana@', '@contoso.example', 'ana@contoso', 'ana contoso@example.test', 'ana@contoso.example.') {
        $gui = New-TestForm -Text 'It works.' -Address $_
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Send-WindowFeedback -Gui $Gui } | Should -BeFalse
        $gui.FeedbackWorker | Should -BeNullOrEmpty
        $gui.Controls.FeedbackStatus.Text | Should -Be 'That does not look like an e-mail address. Correct it, or leave the field empty.'
    }

    It 'sends nothing that is longer than allowed' {
        $gui = New-TestForm
        $gui.Controls.FeedbackText.MaxLength = 0
        $gui.Controls.FeedbackText.Text = 'x' * 4001
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Send-WindowFeedback -Gui $Gui } | Should -BeFalse
        $gui.Controls.FeedbackStatus.Text | Should -Be 'The message is too long: at most 4000 characters.'
    }

    It 'starts the work in the background and locks the form until it is done: <Case>' -ForEach @(
        @{ Case = 'without an address'; Address = '' }
        @{ Case = 'with an address'; Address = 'ana@contoso.example' }
    ) {
        $gui = New-TestForm -Text 'It works.' -Address $Address
        try {
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Send-WindowFeedback -Gui $Gui } | Should -BeTrue

            $gui.FeedbackWorker | Should -Not -BeNullOrEmpty
            $gui.FeedbackDeadline | Should -BeGreaterThan (Get-Date)
            $gui.Controls.FeedbackStatus.Text | Should -Be 'Sending ...'
            $gui.Controls.FeedbackSendButton.IsEnabled | Should -BeFalse
            $gui.Controls.FeedbackCancelButton.IsEnabled | Should -BeFalse
            $gui.Controls.FeedbackText.IsReadOnly | Should -BeTrue
            $gui.Controls.FeedbackAddress.IsReadOnly | Should -BeTrue

            # Neither a second message nor closing while the first is on its way
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Send-WindowFeedback -Gui $Gui } | Should -BeFalse
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Close-WindowFeedback -Gui $Gui } | Should -BeFalse
            $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Visible'
        }
        finally {
            if ($gui.FeedbackTimer) { $gui.FeedbackTimer.Stop() }
            if ($gui.FeedbackHandle) { [void]$gui.FeedbackHandle.AsyncWaitHandle.WaitOne(20000) }
        }
    }

    It 'reports work that failed before it could send as a message that was not sent' {
        # The window of the tests names a module that does not exist.
        $gui = New-TestForm -Text 'It works.'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Send-WindowFeedback -Gui $Gui } | Should -BeTrue
        $gui.FeedbackTimer.Stop()
        [void]$gui.FeedbackHandle.AsyncWaitHandle.WaitOne(20000)

        Invoke-TestReceive $gui | Should -Be 'Failed'
        $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Visible'
        $gui.Controls.FeedbackText.Text | Should -Be 'It works.'
        $gui.Controls.FeedbackStatus.Text | Should -BeLike 'The message could not be sent: *'
    }
}

Describe 'Receive-WindowFeedback' -Skip:(-not $isSta) {
    It 'does nothing when no message is on its way' {
        $gui = New-TestForm -Text 'It works.'
        Invoke-TestReceive $gui | Should -BeNullOrEmpty
        $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Visible'
    }

    It 'waits while the message is on its way' {
        $gui = New-TestForm -Text 'It works.'
        Set-TestWork -Gui $gui -Script 'Start-Sleep -Seconds 3; [PSCustomObject]@{ Sent = $true; Error = "" }' -NoWait
        try {
            Invoke-TestReceive $gui | Should -Be 'Waiting'
            $gui.FeedbackWorker | Should -Not -BeNullOrEmpty
            $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Visible'
        }
        finally {
            [void]$gui.FeedbackHandle.AsyncWaitHandle.WaitOne(15000)
        }
    }

    It 'thanks the user, empties the form and closes it when the message was sent' {
        $gui = New-TestForm -Text 'It works.' -Address 'ana@contoso.example'
        Set-TestWork -Gui $gui -Script '[PSCustomObject]@{ Sent = $true; Error = "" }'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Update-WindowFeedback -Gui $Gui }

        Invoke-TestReceive $gui | Should -Be 'Sent'

        $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Collapsed'
        $gui.Controls.MainLayout.IsEnabled | Should -BeTrue
        $gui.Controls.FeedbackText.Text | Should -Be ''
        $gui.Controls.FeedbackAddress.Text | Should -Be ''
        $gui.Controls.StatusText.Text | Should -Be 'Thank you. Your feedback was sent to the author.'
        $gui.FeedbackWorker | Should -BeNullOrEmpty
        $gui.FeedbackHandle | Should -BeNullOrEmpty
    }

    It 'keeps the form and the text and says why when the message was not sent' {
        $log = InModuleScope HelpdeskToolkit { Get-AppDataPath -ChildPath 'app.log' }
        if (Test-Path -LiteralPath $log) {
            Remove-Item -LiteralPath $log -Force
        }
        $gui = New-TestForm -Text 'A secret thought nobody should log.' -Address 'ana@contoso.example'
        Set-TestWork -Gui $gui -Script '[PSCustomObject]@{ Sent = $false; Error = "The remote name could not be resolved." }'
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Update-WindowFeedback -Gui $Gui }

        Invoke-TestReceive $gui | Should -Be 'Failed'

        $gui.Controls.FeedbackOverlay.Visibility | Should -Be 'Visible'
        $gui.Controls.FeedbackText.Text | Should -Be 'A secret thought nobody should log.'
        $gui.Controls.FeedbackAddress.Text | Should -Be 'ana@contoso.example'
        $gui.Controls.FeedbackStatus.Visibility | Should -Be 'Visible'
        $gui.Controls.FeedbackStatus.Text | Should -Be 'The message could not be sent: The remote name could not be resolved. Your text is still here; check the internet connection and try again.'
        # It can be tried again, or given up.
        $gui.Controls.FeedbackSendButton.IsEnabled | Should -BeTrue
        $gui.Controls.FeedbackCancelButton.IsEnabled | Should -BeTrue
        $gui.Controls.FeedbackText.IsReadOnly | Should -BeFalse
        $gui.FeedbackWorker | Should -BeNullOrEmpty

        # The reason is in the log of the application; what the user wrote is not.
        $written = (Get-Content -LiteralPath $log) -join "`n"
        $written | Should -Match 'Feedback could not be sent: The remote name could not be resolved\.'
        $written | Should -Not -Match 'secret thought'
        $written | Should -Not -Match 'ana@contoso'
    }

    It 'reports a failure when the background work returns nothing' {
        $gui = New-TestForm -Text 'It works.'
        Set-TestWork -Gui $gui -Script '$null'
        Invoke-TestReceive $gui | Should -Be 'Failed'
        $gui.Controls.FeedbackStatus.Text | Should -BeLike 'The message could not be sent: The service did not accept the message.*'
    }

    It 'gives up on a service that does not answer in time, without hanging the window' {
        $gui = New-TestForm -Text 'It works.'
        Set-TestWork -Gui $gui -Script 'Start-Sleep -Seconds 4; [PSCustomObject]@{ Sent = $true; Error = "" }' -NoWait
        $handle = $gui.FeedbackHandle
        $gui.FeedbackDeadline = (Get-Date).AddSeconds(-1)

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-TestReceive $gui | Should -Be 'Failed'
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 3

        $gui.Controls.FeedbackStatus.Text | Should -BeLike 'The message could not be sent: The service did not answer in time.*'
        $gui.Controls.FeedbackText.Text | Should -Be 'It works.'
        $gui.FeedbackWorker | Should -BeNullOrEmpty
        [void]$handle.AsyncWaitHandle.WaitOne(15000)
    }
}

Describe 'The keys of the form' -Skip:(-not $isSta) {
    BeforeEach {
        $gui = New-TestForm -Text 'It works.'
        $clicked = @{ Send = 0; Cancel = 0; Run = 0 }
        $gui.Controls.FeedbackSendButton.Add_Click({ $clicked.Send++ }.GetNewClosure())
        $gui.Controls.FeedbackCancelButton.Add_Click({ $clicked.Cancel++ }.GetNewClosure())
        $gui.Controls.RunButton.Add_Click({ $clicked.Run++ }.GetNewClosure())

        function Send-TestKey {
            param([string]$Key, [switch]$Control)
            InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui; Key = $Key; Control = [bool]$Control } { Invoke-WindowShortcut -Gui $Gui -Key $Key -Control:$Control }
        }
    }

    It 'closes with Esc' {
        Send-TestKey -Key 'Escape' | Should -BeTrue
        $clicked.Cancel | Should -Be 1
    }

    It 'sends with Ctrl+Enter, and leaves Enter alone for a new line' {
        Send-TestKey -Key 'Return' | Should -BeFalse
        $clicked.Send | Should -Be 0
        Send-TestKey -Key 'Return' -Control | Should -BeTrue
        $clicked.Send | Should -Be 1
    }

    It 'lets no shortcut of the window behind it through: <Key>' -ForEach @(
        @{ Key = 'F5'; Control = $false }
        @{ Key = 'T'; Control = $true }
        @{ Key = 'S'; Control = $true }
        @{ Key = 'M'; Control = $true }
        @{ Key = 'F'; Control = $true }
    ) {
        $theme = $gui.Theme
        Send-TestKey -Key $Key -Control:$Control | Should -BeFalse
        $clicked.Run | Should -Be 0
        $gui.Theme | Should -Be $theme
    }

    It 'gives the keys back to the window when the form is closed' {
        InModuleScope HelpdeskToolkit -Parameters @{ Gui = $gui } { Close-WindowFeedback -Gui $Gui } | Out-Null
        Send-TestKey -Key 'F5' | Should -BeTrue
        $clicked.Run | Should -Be 1
    }
}

Describe 'The layout and the wiring of the form' {
    BeforeAll {
        $xaml = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Assets\MainWindow.xaml'))
        $window = [System.IO.File]::ReadAllText((Join-Path -Path $moduleRoot -ChildPath 'Public\Show-PCHealthCheck.ps1'))
    }

    It 'hides the button until the code has seen a form service' {
        $xaml | Should -Match '<Button x:Name="FeedbackButton" Content="Send feedback"[^>]*Visibility="Collapsed"'
    }

    It 'lays the form over the whole window, after everything else' {
        $xaml.IndexOf('x:Name="FeedbackOverlay"') | Should -BeGreaterThan $xaml.IndexOf('x:Name="StartupOverlay"')
        $xaml | Should -Match '<Border x:Name="FeedbackOverlay" Background="\{DynamicResource OverlayBrush\}" Visibility="Collapsed">'
    }

    It 'connects the button, "Send", "Cancel" and the text to their functions' {
        $window | Should -Match 'FeedbackButton\.Add_Click\(\{ \[void\]\(Show-WindowFeedback -Gui'
        $window | Should -Match 'FeedbackSendButton\.Add_Click\(\{ \[void\]\(Send-WindowFeedback -Gui'
        $window | Should -Match 'FeedbackCancelButton\.Add_Click\(\{ \[void\]\(Close-WindowFeedback -Gui'
        $window | Should -Match 'FeedbackText\.Add_TextChanged\(\{ Update-WindowFeedback -Gui'
    }

    It 'sends from one place only, and that place is started by "Send" alone' {
        $callers = @(Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private'), (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' |
                Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match '(?m)^[^#\r\n]*\bSend-FeedbackMessage -Body' } | ForEach-Object Name | Sort-Object)
        $callers | Should -Be @('Send-WindowFeedback.ps1')

        $starters = @(Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private'), (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' |
                Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match '(?m)^[^#\r\n]*\bSend-WindowFeedback -Gui' } | ForEach-Object Name | Sort-Object)
        $starters | Should -Be @('Show-PCHealthCheck.ps1')
    }
}

Describe 'The texts of the form' {
    It 'are translated into Croatian' {
        $croatian = Import-PowerShellDataFile -Path (Join-Path -Path $moduleRoot -ChildPath 'Lang\hr.psd1')
        $texts = @{}
        foreach ($table in $croatian.Values | Where-Object { $_ -is [hashtable] }) {
            foreach ($key in $table.Keys) { $texts[$key] = $table[$key] }
        }
        foreach ($text in 'Send feedback', 'Send', 'Cancel', 'Keys: Ctrl+Enter', 'Key: Esc', 'Sending ...', 'Write your message first.',
            'Write to the author of the application: what works, what does not, what is missing',
            'Tell the author what works well, what does not, or what is missing. Your message reaches the author by e-mail.',
            'Your e-mail address (optional: only if you would like an answer)',
            'The message is too long: at most {0} characters.',
            'That does not look like an e-mail address. Correct it, or leave the field empty.',
            'Thank you. Your feedback was sent to the author.',
            'The message could not be sent: {0} Your text is still here; check the internet connection and try again.',
            'The service did not answer in time.', 'The service did not accept the message.') {
            $texts[$text] | Should -Not -BeNullOrEmpty -Because "'$text' is shown to the user"
        }
        ($texts.Keys | Where-Object { $_ -like 'What is sent: your text,*' }) | Should -Not -BeNullOrEmpty
    }
}
