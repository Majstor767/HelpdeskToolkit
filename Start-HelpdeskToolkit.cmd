@echo off
rem Opens the HelpdeskToolkit window. Double-click this file; no PowerShell knowledge needed.
rem
rem conhost.exe --headless starts PowerShell without a console window. PowerShell's own
rem   "-WindowStyle Hidden" is not enough on Windows 11: Windows Terminal ignores it and
rem   leaves an empty window open, and closing that window would close the application.
rem -ExecutionPolicy Bypass applies only to this one PowerShell process, so the module
rem   can be loaded without changing any setting on the computer.
rem %~dp0 is the folder this file is in, so it works from any location.

start "" "%SystemRoot%\System32\conhost.exe" --headless "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-HelpdeskToolkit.ps1"
