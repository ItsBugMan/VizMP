#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\builds\windows"
#endif
#ifndef BuildDir
  #define BuildDir "..\..\builds"
#endif

[Setup]
AppId={{B75E8847-DC70-4D52-B661-0A50DBE4A8E9}
AppName=VizMP
AppVersion={#AppVersion}
AppPublisher=ItsBugMan
AppPublisherURL=https://github.com/ItsBugMan/VizMP
AppUpdatesURL=https://github.com/ItsBugMan/VizMP/releases
DefaultDirName={autopf}\VizMP
DefaultGroupName=VizMP
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#BuildDir}
OutputBaseFilename=VizMP_Setup_v{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\VizMP.exe
CloseApplications=yes
RestartApplications=no
SetupMutex=VizMPSetup

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
Name: "screensaver"; Description: "Use VizMP as my Windows screensaver"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VizMP"; Filename: "{app}\VizMP.exe"; WorkingDir: "{app}"
Name: "{group}\Screensaver settings"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\RunScreensaver.ps1"" -Mode Configure"; WorkingDir: "{app}"
Name: "{autodesktop}\VizMP"; Filename: "{app}\VizMP.exe"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\VizMP.exe"; Description: "Launch VizMP"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
var PreviousSaver: String;
    HadPreviousSaver: Boolean;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('screensaver') then begin
    { Configure this user's saver in-place: no duplicate executable in System32. }
    if not RegValueExists(HKCU, 'Software\ItsBugMan\VizMP', 'SaverRecorded') then begin
      HadPreviousSaver := RegQueryStringValue(HKCU, 'Control Panel\Desktop', 'SCRNSAVE.EXE', PreviousSaver);
      RegWriteStringValue(HKCU, 'Software\ItsBugMan\VizMP', 'PreviousSaver', PreviousSaver);
      if HadPreviousSaver then
        RegWriteDWordValue(HKCU, 'Software\ItsBugMan\VizMP', 'SaverRecorded', 1)
      else
        RegWriteDWordValue(HKCU, 'Software\ItsBugMan\VizMP', 'SaverRecorded', 0);
    end;
    RegWriteStringValue(HKCU, 'Control Panel\Desktop', 'SCRNSAVE.EXE', ExpandConstant('{app}\VizMP.scr'));
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var CurrentSaver: String;
    Recorded: Cardinal;
begin
  if CurUninstallStep = usUninstall then begin
    if RegQueryStringValue(HKCU, 'Control Panel\Desktop', 'SCRNSAVE.EXE', CurrentSaver) and
       (CompareText(CurrentSaver, ExpandConstant('{app}\VizMP.scr')) = 0) then begin
      if RegQueryDWordValue(HKCU, 'Software\ItsBugMan\VizMP', 'SaverRecorded', Recorded) then begin
        if Recorded = 1 then begin
          RegQueryStringValue(HKCU, 'Software\ItsBugMan\VizMP', 'PreviousSaver', PreviousSaver);
          RegWriteStringValue(HKCU, 'Control Panel\Desktop', 'SCRNSAVE.EXE', PreviousSaver);
        end else RegDeleteValue(HKCU, 'Control Panel\Desktop', 'SCRNSAVE.EXE');
      end;
    end;
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\ItsBugMan\VizMP');
  end;
end;
