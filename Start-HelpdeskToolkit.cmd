@echo off
rem Opens the HelpdeskToolkit window. Double-click this file; no PowerShell knowledge needed.
rem
rem -ExecutionPolicy Bypass applies only to this one PowerShell process, so the module
rem   can be loaded without changing any setting on the computer.
rem -WindowStyle Hidden hides the console window that would otherwise stay open
rem   behind the application window.
rem %~dp0 is the folder this file is in, so it works from any location.

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Import-Module '%~dp0HelpdeskToolkit\HelpdeskToolkit.psd1'; Show-PCHealthCheck"
