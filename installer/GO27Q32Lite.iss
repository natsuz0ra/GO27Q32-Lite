#ifndef AppVersion
  #error AppVersion must be supplied by build-installer.ps1
#endif
#ifndef PayloadDir
  #error PayloadDir must be supplied by build-installer.ps1
#endif
#ifndef OutputDir
  #error OutputDir must be supplied by build-installer.ps1
#endif

[Setup]
AppId={{F401EF7D-F8C4-46C1-852A-B0FF4F395D08}
AppName=GO27Q32 Lite
AppVersion={#AppVersion}
AppVerName=GO27Q32 Lite {#AppVersion}
AppPublisher=natsuzora
AppPublisherURL=https://github.com/natsuz0ra/GO27Q32-Lite
AppSupportURL=https://github.com/natsuz0ra/GO27Q32-Lite/issues
AppUpdatesURL=https://github.com/natsuz0ra/GO27Q32-Lite/releases
DefaultDirName={localappdata}\Programs\GO27Q32 Lite
DefaultGroupName=GO27Q32 Lite
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
ShowLanguageDialog=yes
LanguageDetectionMethod=uilanguage
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\go27q32_lite.exe
LicenseFile=..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename=GO27Q32Lite-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no
AppMutex=Local\GO27Q32LiteFlutter
UninstallDisplayName=GO27Q32 Lite
VersionInfoVersion={#AppVersion}.0

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "zhCN"; MessagesFile: "languages\ChineseSimplified.isl"

[CustomMessages]
en.DesktopShortcut=Create a desktop shortcut
zhCN.DesktopShortcut=创建桌面快捷方式
en.LaunchApp=Open GO27Q32 Lite
zhCN.LaunchApp=打开 GO27Q32 Lite

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "desktop-checks.txt,*.pdb"

[Icons]
Name: "{group}\GO27Q32 Lite"; Filename: "{app}\go27q32_lite.exe"; Parameters: "--show"
Name: "{autodesktop}\GO27Q32 Lite"; Filename: "{app}\go27q32_lite.exe"; Parameters: "--show"; Tasks: desktopicon

[Run]
Filename: "{app}\go27q32_lite.exe"; Parameters: "--show"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent

[Code]
// Change only our existing Run value. Never delete another portable copy's entry.
function IsOurStartupCommand(const Command: String): Boolean;
begin
  Result := (CompareText(Command, '"' + ExpandConstant('{app}\go27q32_lite.exe') + '" --tray') = 0);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  StartupCommand: String;
begin
  if CurUninstallStep = usPostUninstall then
    if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'GO27Q32LiteFlutter', StartupCommand) then
      if IsOurStartupCommand(StartupCommand) then
        RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', 'GO27Q32LiteFlutter');
  // Settings are deliberately outside {app} and are preserved.
end;
