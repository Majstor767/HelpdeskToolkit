# Privacy

HelpdeskToolkit is a program that runs on your computer. It has no server, no account
and no telemetry: nothing about you or your computer is sent to the author or to anyone
else by the program itself. This page says what it reads, what it keeps, and which
network connections it makes.

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
| A log of unexpected errors of the program, and of every uninstaller it started for you | `%LOCALAPPDATA%\HelpdeskToolkit\app.log` |
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
| Opening a page in your browser | Only when you click a link: a page of Microsoft Support or Microsoft Learn, or a web search on Bing | Do not click the link |
| A remote computer | Only with `-ComputerName`: the report of that computer is read over Windows Remote Management | Do not use the parameter |

What a link sends to a web site is the address itself. An address contains the name of
a check ("Disk"), the source and the number of an event ("Kernel-Power 41"), the number
of an update ("KB5050009") or an error code ("0x80070005"). It never contains the name
of a computer, a user, a program, a file or a drive: the code only takes parts of a
fixed shape, digits and hexadecimal digits, from a result. The sites you open that way
(Microsoft, Bing) have their own privacy policies.

## Questions

Open an issue at <https://github.com/Majstor767/HelpdeskToolkit/issues>, without
personal data in it.
