; Inno Setup script that builds HelpdeskToolkit-Setup-<version>.exe.
;
; Do not compile this file directly: tools\Build-Release.ps1 passes the version
; (read from the module manifest) and the folder with the files to package.
;
;   ISCC.exe /DAppVersion=1.0.0 /DSourceDir=C:\path\to\staging HelpdeskToolkit.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir ".."
#endif

#define AppName "HelpdeskToolkit"
#define AppIcon "HelpdeskToolkit\Assets\HelpdeskToolkit.ico"

; PowerShell is a console program, so Windows always gives it a console window. On
; Windows 11 that window is a Windows Terminal window, which ignores PowerShell's own
; "-WindowStyle Hidden" option: an empty terminal stays open, and closing it closes
; the application. The shortcuts therefore start PowerShell through the Windows
; console host in headless mode, which provides the console without any window.
#define ConsoleHost "{sys}\conhost.exe"

[Setup]
; AppId identifies the application for updates and uninstall. Never change it.
AppId={{0E354CC9-7F28-44F2-96B4-5782F88829B9}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Antonio Majstorovic
AppPublisherURL=https://github.com/Majstor767/HelpdeskToolkit
AppSupportURL=https://github.com/Majstor767/HelpdeskToolkit/issues
AppUpdatesURL=https://github.com/Majstor767/HelpdeskToolkit/releases
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppIcon}

; Installs for the current user only, so no administrator rights are needed.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes

; On 64-bit Windows the 64-bit PowerShell must be used; the 32-bit one would see a
; different view of the registry and of some system information.
ArchitecturesInstallIn64BitMode=x64compatible

; The headless mode of the console host exists since Windows 10 version 1809 (build 17763).
MinVersion=10.0.17763

LicenseFile={#SourceDir}\LICENSE
SetupIconFile={#SourceDir}\{#AppIcon}
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputBaseFilename={#AppName}-Setup-{#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

; The shortcuts start the window through the launcher script. Windows PowerShell is
; part of every supported Windows version, so nothing else has to be installed. In this
; file a double quote inside a quoted value is written as two double quotes.
[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{#ConsoleHost}"; Parameters: "--headless ""{sys}\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-HelpdeskToolkit.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"; Comment: "Check the health of this PC"
Name: "{autodesktop}\{#AppName}"; Filename: "{#ConsoleHost}"; Parameters: "--headless ""{sys}\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-HelpdeskToolkit.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"; Comment: "Check the health of this PC"; Tasks: desktopicon

[Run]
Filename: "{#ConsoleHost}"; Parameters: "--headless ""{sys}\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-HelpdeskToolkit.ps1"""; WorkingDir: "{app}"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent
