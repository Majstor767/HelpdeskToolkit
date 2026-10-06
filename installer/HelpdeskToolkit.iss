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
; Must be the same text as $script:AppUserModelId in HelpdeskToolkit\HelpdeskToolkit.psm1.
#define AppUserModelId "Majstor767.HelpdeskToolkit"

[Setup]
; AppId identifies the application for updates and uninstall. Never change it.
AppId={{0E354CC9-7F28-44F2-96B4-5782F88829B9}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Antonio Majstorovic
AppCopyright=Copyright (c) 2026 Antonio Majstorovic. MIT License.
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

; An update only overwrites files; a file that the new version no longer has would stay
; behind, and the module loads every script in its folders. The module folder of the
; previous version is therefore removed before the new files are copied.
[InstallDelete]
Type: filesandordirs; Name: "{app}\HelpdeskToolkit"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

; The shortcut that starts the application with Windows is written by the application
; itself when the user ticks that option (see Private\Enable-AppAutoStart.ps1). It goes
; with the application.
[UninstallDelete]
Type: files; Name: "{userstartup}\HelpdeskToolkit.lnk"

; The shortcuts carry the application ID the window gives itself (see
; Private\Initialize-AppIdentity.ps1 and $script:AppUserModelId in the module). With it
; the taskbar knows that the running window belongs to these shortcuts: it shows their
; icon, and a window that is pinned to the taskbar is started through them.
;
; The shortcuts start the window through the launcher script. Windows PowerShell is
; part of every supported Windows version, so nothing else has to be installed. In this
; file a double quote inside a quoted value is written as two double quotes.
[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{#ConsoleHost}"; Parameters: "--headless ""{sys}\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-HelpdeskToolkit.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"; Comment: "Check the health of this PC"; AppUserModelID: "{#AppUserModelId}"
Name: "{autodesktop}\{#AppName}"; Filename: "{#ConsoleHost}"; Parameters: "--headless ""{sys}\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-HelpdeskToolkit.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\{#AppIcon}"; Comment: "Check the health of this PC"; AppUserModelID: "{#AppUserModelId}"; Tasks: desktopicon

; Setup must not replace the files of an application that is running: it could not
; replace the files that are in use, would stop halfway and leave a copy behind that no
; longer starts. The running application keeps its icon file open (see
; Private\Lock-AppFile.ps1), also when it runs with administrator rights and Setup does
; not. Setup therefore tries to open that file for itself alone before it changes
; anything, and stops with a message when it cannot.
[Code]
function IsApplicationRunning(): Boolean;
var
  IconFile: String;
  Stream: TFileStream;
begin
  Result := False;
  IconFile := ExpandConstant('{app}\{#AppIcon}');
  if FileExists(IconFile) then
  begin
    try
      Stream := TFileStream.Create(IconFile, fmOpenReadWrite or fmShareExclusive);
      Stream.Free;
    except
      Result := True;
    end;
  end;
end;

// Called after the questions of the wizard and before the first file is touched.
// A text as the result stops the installation and is shown to the user.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if IsApplicationRunning() then
    Result := '{#AppName} is running. Close it, then run Setup again. When it runs in the background: right-click its icon next to the clock and choose Exit.';
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if IsApplicationRunning() then
  begin
    MsgBox('{#AppName} is running. Close it, then uninstall it again. When it runs in the background: right-click its icon next to the clock and choose Exit.', mbError, MB_OK);
    Result := False;
  end;
end;

[Run]
Filename: "{#ConsoleHost}"; Parameters: "--headless ""{sys}\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -ExecutionPolicy Bypass -File ""{app}\Start-HelpdeskToolkit.ps1"""; WorkingDir: "{app}"; Description: "Start {#AppName}"; Flags: nowait postinstall skipifsilent
