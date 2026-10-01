# Publishing

The steps for making a version public. Nothing here runs by itself: every step that
sends something to the internet is started by hand.

## Before the first release

- [ ] `.\tools\Test-Project.ps1` passes on Windows PowerShell 5.1 and on PowerShell 7.
- [ ] The application was started with "Restart as administrator" once and the checks
      marked "Requires admin" show sensible values (drive details, BitLocker, TPM,
      restore points, failed sign-ins).
- [ ] `-ComputerName` was tried against a second computer, or the note that calls it
      experimental stays in the README files.
- [ ] `ModuleVersion` in `HelpdeskToolkit\HelpdeskToolkit.psd1` is the version to
      release, and `CHANGELOG.md` has a section with that version and the date in
      place of "Unreleased".
- [ ] The generated files were rebuilt, because the sample report shows the version:
      `.\tools\New-SampleReport.ps1`, then `.\tools\New-Screenshot.ps1`.
- [ ] `.\tools\Build-Release.ps1` builds the installer, and the installed application
      starts and runs a check.

## GitHub

1. Sign in once: `gh auth login` (GitHub.com, HTTPS, sign in with the browser).
2. Create the repository from the local folder and push it:

   ```powershell
   gh repo create Majstor767/HelpdeskToolkit --public --source . --remote origin --push
   ```

3. Open the **Actions** tab and wait for the CI run. It is the first time the tests
   run on a computer other than the one they were written on, so read the result
   before going on.
4. Create the release by pushing a tag that matches `ModuleVersion`:

   ```powershell
   git tag v1.0.0
   git push origin v1.0.0
   ```

   The release workflow runs the tests again, builds the installer and the ZIP and
   publishes them with `SHA256SUMS.txt` on the Releases page.
5. Download the installer from the Releases page on another computer, or with another
   account, and install it. This shows what a user sees: the SmartScreen notice
   ("More info" > "Run anyway"), because the installer is not digitally signed.

Good to set on the repository page: a short description, the topics `powershell`,
`windows`, `helpdesk`, `it-support`, `diagnostics`, and the picture
`docs/screenshot-window.png` as the social preview.

## PowerShell Gallery

The gallery makes `Install-Module HelpdeskToolkit -Scope CurrentUser` work. It holds
the module only: the window is part of it (`Show-PCHealthCheck`), the installer and
`Invoke-HealthCheck.ps1` are not.

1. Sign in on <https://www.powershellgallery.com> and create an API key that is limited
   to pushing the package `HelpdeskToolkit`. The key is a secret: it is not written to
   any file of the repository.
2. Check the manifest and what would be sent:

   ```powershell
   Test-ModuleManifest .\HelpdeskToolkit\HelpdeskToolkit.psd1
   Publish-Module -Path .\HelpdeskToolkit -NuGetApiKey $key -WhatIf
   ```

3. Publish: the same command without `-WhatIf`. A version that was published cannot be
   replaced, only hidden; a correction needs a new version number.

The name must be free in the gallery. Search for `HelpdeskToolkit` there first; if it
is taken, the module needs another name before it can be published there.

## winget

winget makes `winget install Majstor767.HelpdeskToolkit` work. The package is a small
description (a manifest) in the public repository `microsoft/winget-pkgs` that points
to the installer on the GitHub Releases page, so the GitHub release comes first.

1. Install the helper: `winget install Microsoft.WingetCreate`.
2. Create the manifest from the address of the installer in the release:

   ```powershell
   wingetcreate new https://github.com/Majstor767/HelpdeskToolkit/releases/download/v1.0.0/HelpdeskToolkit-Setup-1.0.0.exe
   ```

   The helper downloads the installer, works out its checksum and type (Inno Setup,
   installed for the current user) and asks for the rest: package identifier
   `Majstor767.HelpdeskToolkit`, publisher, license `MIT`, a short description.
3. Let the helper submit it. It opens a pull request in `microsoft/winget-pkgs` with
   your GitHub account. Automatic checks install the package in a test environment,
   then a moderator reviews it; this takes from a few hours to a few days.
4. For a later version: `wingetcreate update Majstor767.HelpdeskToolkit --version <new> --urls <address of the new installer> --submit`.

## After a release

- Start the next section "Unreleased" in `CHANGELOG.md`.
- Every later version repeats the same steps: version number, changelog, generated
  files, tag.
