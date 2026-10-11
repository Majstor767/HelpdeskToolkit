# Notices

## Copyright and license

HelpdeskToolkit, copyright (c) 2026 Antonio Majstorovic, is released under the
[MIT License](LICENSE). The license comes with every copy; it says that the software is
provided "as is", without warranty of any kind, and that the author is not liable for
any damage that comes from using it.

## No affiliation, and trademarks

HelpdeskToolkit is an independent, private project. It is not made, endorsed, sponsored
or supported by Microsoft Corporation or by any other company named in it.

Microsoft, Windows, Windows PowerShell, Microsoft Defender, Microsoft Edge, Microsoft
Office, Outlook, OneDrive and BitLocker are trademarks of the Microsoft group of
companies. Google is a trademark of Google LLC. Other names of products and companies that appear in the program, in its
reports or in this repository (for example the names of installed programs, of
browsers, of hardware makers and of their products) are trademarks of their owners.
They are used only to name the things the tool reports about.

"Contoso" and the computer and user names in the sample report, the screenshots and the
tests are invented. Any likeness to a real organization, computer or person is
coincidence.

## What the tool is, and is not

The tool reports what Windows says about a computer and adds short explanations and
suggestions. These are general information for people who look after computers; they
are not professional advice for your situation, and a result can be wrong or out of
date (the end-of-support dates in `HelpdeskToolkit\Config\EndOfLife.psd1`, for example,
were read from the pages of the makers on the day named in that file). Decide for
yourself what to do with a computer, and keep a backup before you change it.

Use the tool only on computers you own or are allowed to examine. Reading another
computer with `-ComputerName`, or keeping and passing on a report of a computer that is
used by other people, can need permission under the law or the rules of your
organization. See [PRIVACY.md](PRIVACY.md).

## Links to other sites

The window and the HTML report link problems to pages of Microsoft Support and
Microsoft Learn and to web searches on Google. Those sites belong to their operators, who alone are responsible for
their content, and their terms and privacy policies apply when you open them. A link is
a pointer, not a recommendation of everything behind it.

Feedback you send from the window is delivered by the form service named in
`HelpdeskToolkit\Config\Feedback.psd1`: Formspree (`formspree.io`), an independent company
whose terms and privacy policy apply to the message it handles. HelpdeskToolkit is not
affiliated with it. See [PRIVACY.md](PRIVACY.md).

## Third-party software

Nothing of a third party is contained in the program: it is written in PowerShell and
uses what Windows provides (.NET Framework, Windows Presentation Foundation, the icon
font "Segoe MDL2 Assets" as installed on the computer, and winget when it is there).

- The installer is built with [Inno Setup](https://jrsoftware.org/isinfo.php) by Jordan
  Russell and Martijn Laan, and contains its setup engine. Inno Setup is used under its
  own [license](https://jrsoftware.org/files/is/license.txt), which permits this use.
- The tests use [Pester](https://pester.dev) and the code is checked with
  [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer). Neither is part of
  what a user receives.
- A PDF report is produced by the copy of Microsoft Edge or Google Chrome that is
  installed on the computer; no browser is included.
