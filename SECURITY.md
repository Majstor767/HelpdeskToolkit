# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use **Security > Report a
vulnerability** on the GitHub page of the project
(<https://github.com/Majstor767/HelpdeskToolkit/security/advisories/new>), which reaches
the maintainer privately. Say what you did, what happened and which version you used. Do
not include a report of a real computer: it contains personal data (see
[PRIVACY.md](PRIVACY.md)).

This is a project of one person, maintained in spare time. You can expect an answer
within about two weeks; there is no bounty.

## Supported versions

Fixes are made for the newest release only.

## What to know about the program

- **It is not signed.** Windows SmartScreen therefore warns before the installer runs.
  Download it only from the [Releases](https://github.com/Majstor767/HelpdeskToolkit/releases)
  page of this repository and compare it with `SHA256SUMS.txt` of the same release.
- **It is PowerShell, and readable.** Everything the program does is in the files of
  the installation folder. Its launchers start PowerShell with
  `-ExecutionPolicy Bypass` for that one process, so the module loads without a change
  to any setting of the computer.
- **It only reads.** The checks never change the system. The exceptions, all of them
  started by a click of the user, are listed under "Read-only" in the
  [README](README.md).
- **With administrator rights it sees more.** "Restart as administrator" starts the same
  program elevated, through the Windows prompt. A link to a web page is then opened
  through the desktop, so the browser does not run with administrator rights.
- **Addresses are restricted.** The program opens `https://` addresses only, and builds
  them from the name of a check, an event number, an update number or an error code,
  never from the free text of a result.
