function Export-HealthReportPdf {
    <#
    .SYNOPSIS
        Saves a health report as a PDF file and returns the file path.
    .DESCRIPTION
        The PDF is the HTML report, printed to a file by Microsoft Edge (or Google
        Chrome) in "headless" mode, that is without a window. The report has a print
        layout of its own, so the PDF looks like a printed page and not like a web page.

        The HTML is written to a temporary file first and removed afterwards. Throws
        when no suitable browser is installed or when the browser produced no file
        within the time limit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Report,

        # Full path of the file to create.
        [Parameter(Mandatory)]
        [string]$Path,

        [ValidateRange(5, 600)]
        [int]$TimeoutSeconds = 90
    )

    $browser = Get-PdfBrowserPath
    if (-not $browser) {
        throw 'A PDF needs Microsoft Edge or Google Chrome, and neither was found. Save the report as HTML and print it to PDF from any browser instead.'
    }

    $temporary = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('HelpdeskToolkit-{0}.html' -f [guid]::NewGuid())
    try {
        [void](Export-HealthReportHtml -Report $Report -Path $temporary)

        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }

        $arguments = @(
            '--headless=new'
            '--disable-gpu'
            # Without the header and footer a browser adds to printed pages (date, file path)
            '--no-pdf-header-footer'
            ('--print-to-pdf="{0}"' -f $Path)
            ('"{0}"' -f ([System.Uri]$temporary).AbsoluteUri)
        )
        $process = Start-Process -FilePath $browser -ArgumentList $arguments -PassThru -WindowStyle Hidden

        # The browser hands the work to a second process and may return at once, so the
        # file is waited for, not the process.
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not (Test-Path -LiteralPath $Path) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 250
        }
        if ($process -and -not $process.HasExited) {
            [void]$process.WaitForExit(5000)
        }

        if (-not (Test-Path -LiteralPath $Path)) {
            throw "The browser did not create the PDF within $TimeoutSeconds seconds."
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }

    $Path
}
