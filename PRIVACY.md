# Privacy

HelpdeskToolkit is a program that runs on your computer. It has no server, no account
and no telemetry: nothing about you or your computer is sent to the author or to anyone
else by the program itself. The one thing that reaches the author is a message you
write and send yourself with **Send feedback** (see below). This page says what the
program reads, what it keeps, and which network connections it makes.

*Hrvatski: sažetak je u [README.hr.md](README.hr.md#privatnost-i-pravne-napomene).*

## What it reads

The checks read information about the computer they run on: the Windows version,
hardware and drivers, drives and their free space, installed programs and updates,
entries of the event logs, the state of services, of Microsoft Defender and of the
firewall, local user accounts, network adapters with their addresses, printers and
running programs. Nothing is changed while reading (see "Read-only" in the
[README](README.md)).

## What it keeps, and where

Everything stays on the computer, in places only your Windows user can read:

| What | Where |
|---|---|
| Settings of the window | `%LOCALAPPDATA%\HelpdeskToolkit\settings.json` |
| The last 30 reports, for "since the last check" and the score over time | `%LOCALAPPDATA%\HelpdeskToolkit\History` |
| Sizes of folders that take long to measure, for half an hour | `%LOCALAPPDATA%\HelpdeskToolkit\Cache` |
| A log of unexpected errors of the program, and of every uninstaller it started and every startup program it switched for you | `%LOCALAPPDATA%\HelpdeskToolkit\app.log` |
| Reports you save or open, and recordings of the Live monitor when you start one | the folder you choose (`Documents\HelpdeskToolkit` by default) |

Uninstalling removes the program. To remove what it kept, delete the folder
`%LOCALAPPDATA%\HelpdeskToolkit` and the reports you saved.

## A report contains personal data

A report names the computer, the signed-in user and the local accounts, the installed
programs, the network addresses, the name of the Wi-Fi network and the serial number of
the computer. Treat a saved report like any other document with personal data:

- Share it only with people who are meant to see it, and prefer a screenshot of the one
  result in question.
- Do not attach a report to a public issue or forum post.
- If you examine a computer that is not yours (at work, for a customer, for a friend),
  you are responsible for having the permission to do so and for what happens to the
  report afterwards. Where the GDPR or a similar law applies, that is your duty as the
  one who processes the data; the program does not process anything on behalf of the
  author.

## Network connections

The program connects to the network only for the following, and each of them can be
avoided:

| Connection | Purpose | How to avoid it |
|---|---|---|
| Ping to your router and to `1.1.1.1` (a public DNS server of Cloudflare), a DNS lookup of `microsoft.com`, one HTTPS request to `https://www.microsoft.com` | The connectivity tests of the Network category and the Internet tile of the Live monitor | Tick **Skip network tests**, or use `-SkipNetwork` |
| `winget upgrade` | Asks the package manager of Windows which installed programs have a newer version. winget contacts its catalog, which Microsoft operates | The same switch |
| Opening a page in your browser | Only when you click a link: a page of Microsoft Support or Microsoft Learn, or a web search on Google | Do not click the link |
| Sending feedback | Only when you write a message under **Send feedback** and click **Send**: the message goes over https to the form service named in `HelpdeskToolkit\Config\Feedback.psd1` (Formspree, `formspree.io`), which passes it on to the author by e-mail | Do not send feedback; without a form service in that file the button is not shown at all |
| A remote computer | Only with `-ComputerName`: the report of that computer is read over Windows Remote Management | Do not use the parameter |

What a link sends to a web site is the address itself, and only when you click it; the
tip of a link shows the address before you do. An address contains the name of a check
("Disk"), the source and the number of an event ("Kernel-Power 41"), the number of an
update ("KB5050009"), an error code ("0x80070005"), or, in a search for a program that
crashed or an update that failed, the name of the program or the update
("contoso.exe crash"), because such a search is useless without it. Of a path only the
file name is taken, a name must consist of letters, digits and a few punctuation marks,
and a name that contains the name of the signed-in user or of the computer is left
out. An address never contains the name of a computer or a user, a folder, a file path
or a drive. The sites you open that way (Microsoft, Google) have their own privacy
policies.

## Feedback you send

A feedback message contains what the form shows before you send it, and nothing else:

- the text you wrote,
- your e-mail address, only if you typed one in because you would like an answer,
- the version of the application, the version number of Windows and the language of
  the window.

It does not contain the name of the computer, your user name, or any result of a check.
The message is delivered by a form service: a web service that receives it and passes
it on to the mailbox of the author, so the application itself knows no e-mail address.
In this version that service is Formspree (`formspree.io`), an independent company.
It sees the message and, like every web server, the internet address it came from; it
also keeps the message for the author to read, and its own
[privacy policy](https://formspree.io/legal/privacy-policy) applies to what it keeps. Do not put anything into a
message that you would not put into an e-mail to a stranger. A message that could not
be sent stays in the form; only the reason is written to the log of the application,
never the text.

## Questions

Open an issue at <https://github.com/Majstor767/HelpdeskToolkit/issues>, without
personal data in it.
