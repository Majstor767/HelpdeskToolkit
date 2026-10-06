# Contributing

Bug reports, ideas and pull requests are welcome.

## Before you post anything

A report of HelpdeskToolkit and many screenshots of its window contain personal data:
the name of the computer, user names, installed programs, network addresses, serial
numbers. **Do not attach a report of a real computer to an issue**, and blur or crop
screenshots. What helps most is:

- the version (Settings > About), the Windows version, and whether the window ran with
  administrator rights
- what you did and what you expected
- the lines of `app.log` from the time of the problem (Settings > About > Open the
  folder), after a look that they name nothing you want to keep to yourself

Security problems are reported privately: see [SECURITY.md](SECURITY.md).

## Pull requests

- The rules of the code are in the [README](README.md#development): approved verbs,
  comment-based help, one function per file, Windows PowerShell 5.1 and PowerShell 7,
  tests with mocks, no findings of PSScriptAnalyzer. `.\tools\Test-Project.ps1` runs all
  of it.
- The checks only read. A change that makes the tool alter the system will not be
  merged.
- Test data and screenshots use invented names (Contoso, FIN-LT-014), never real ones.

## License of contributions

The project is released under the [MIT License](LICENSE). By sending a pull request you
agree that your contribution is released under the same license, and you confirm that
you wrote it yourself or otherwise have the right to contribute it. Do not copy code or
texts from sources whose license does not allow that.
