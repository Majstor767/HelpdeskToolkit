HelpdeskToolkit - test version
==============================

Thank you for trying it out! HelpdeskToolkit checks the state of a Windows computer
(disk, memory, updates, protection, network, printers ...) and shows what is wrong,
why that is a problem and how it is fixed.

The checks ONLY READ. They change nothing on the computer, delete nothing and send
nothing about you anywhere. Two things happen only when you click one program and
confirm the question: its uninstaller is started (Live monitor > a disk), or it is
switched off or on as a startup program (System > Startup programs). What goes to the internet are the network tests (ping, DNS
and HTTPS to 1.1.1.1 and microsoft.com) and a question to winget, the package manager
of Windows, whether newer versions of the installed programs exist; both are switched
off with the tick "Skip network tests". A link you click opens a page of Microsoft or
a web search in your browser.

You need Windows 10 (version 1809 or later) or Windows 11. Nothing else.


HOW TO START IT
---------------

A) With the installer (recommended)

   1. Double-click HelpdeskToolkit-Setup-<version>.exe
   2. Windows will probably show a blue window "Windows protected your PC", because
      the program is not digitally signed. Click "More info", then "Run anyway".
   3. It installs for your user account only and does not ask for an administrator.
   4. Start HelpdeskToolkit from the Start menu.

   To remove it: Settings > Apps > Installed apps > HelpdeskToolkit.

B) Without installing

   1. Open the folder "Portable".
   2. Double-click Start-HelpdeskToolkit.cmd
   3. If Windows asks whether the file may run, confirm it (Run).

   When you are done, simply delete the folder.


WHAT WILL HAPPEN
----------------

1. The application asks at once: start with administrator rights?
   - "Yes" -> Windows asks for its own confirmation, then the check runs with
              everything it can read.
   - "No"  -> the check runs at once, without the part only an administrator sees.
2. A check usually takes 10 to 20 seconds (a little longer on a slow computer or a
   full disk). If the application ran before, the results of the last check are
   shown at once until the new one has finished.
3. Language: the window follows the language of Windows where it has a translation
   (English and Croatian). To change it: the gear "Settings" at the bottom left >
   Language > "Restart now".
4. Dark theme: the switch with the sun and the moon at the top right (or Ctrl+T). It
   changes at once.
5. In the background: the button "Run in background" at the bottom left hides the
   window and leaves the application as an icon next to the clock (right-click the
   icon > Exit ends it). For good: Settings > "In the background". With the first
   option the window hides like that on X as well; with the second the application
   starts like that with Windows. Both are off at first.
6. A picture of the window: the key PrtSc copies a picture of the window, which you
   paste with Ctrl+V (into a chat or an e-mail). Handy for showing what is wrong.


WHAT IS WORTH TRYING
--------------------

- Overview: the list of problems. Each says why it is a problem and what to do, and
  a button opens the place in Windows where it is fixed.
- The sections on the left (System, Hardware, Security ...): the problems are at the
  top, each with its fix next to it; the rest are tiles, and a click on a tile opens
  its details. The counters at the top (Critical, Warning, OK, Info) filter the page.
- Every problem has a link "What this means and how to fix it" that opens a page with
  the explanation. A failed update also links the article about that update and a
  search for its error code. In the Event Log, "Show more" lists every error with
  its event number; a click searches the web for that event.
- Live monitor > a disk > "What takes up the space": a click on a program asks
  whether you want to uninstall it and starts its own uninstaller. Nothing is
  started without your confirmation.
- System > Startup programs > "Show all": a click on a program asks whether it should
  stop starting with Windows (the same switch as Task Manager > Startup apps); a click
  on one that is "turned off" switches it on again.
- Timeline: what happened on the computer in the last weeks (installations, updates,
  crashes), day by day. A red dot is a failure, a blue one a change.
- Software: programs for which a newer version exists and programs without support.
- Security: SmartScreen, Memory integrity, who used the camera and the microphone.
- Live monitor: what the computer is doing right now. A click on the tile Processor,
  Memory or Graphics opens a page with everything about that component. The tile
  Internet shows how quickly the internet answers.
- The search field at the top right and the filter by status.
- "Open HTML report" and "Save as..." (HTML, PDF, CSV, JSON).
- Leave the application open for a few minutes: it repeats the check by itself and
  tells you when a new problem appears.


WHAT I WOULD LIKE TO HEAR
-------------------------

- Did it start at the first try? If not: what did it say (a screenshot helps)?
- If something breaks while it runs: the application stays open, and the status line
  says that the error was written to app.log. That file helps me most; Settings >
  About > Open the folder leads to it.
- How much memory does it use after an hour or two (Task Manager > Details >
  powershell.exe)? Open, it should stay at about 200-250 MB.
- Is something shown wrongly for your computer, or is something missing?
- Is it clear what each result means and what has to be done?
- Is anything slow, confusing or ugly?
- Which Windows you have (10 or 11) and whether the computer is a laptop or a
  desktop. On a laptop I am especially interested in the battery and the Wi-Fi,
  which I could not try on my own computer.

Privacy: a saved report (Save as...) contains the name of the computer, user names,
network addresses and the list of installed programs. Send it only if you do not
mind; a screenshot is quite enough.

No warranty: HelpdeskToolkit is free software under the MIT License, provided as it
is. It is an independent project and is not affiliated with Microsoft.
