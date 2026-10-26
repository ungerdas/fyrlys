; Fyrlys – installasjonsprogrammet (Inno Setup 6). Bygges i workflowen:
;   ISCC.exe /DAppVersion=2.1.13 /DSource=<Release-mappen> /DOutputDir=<ut> windows\installer\fyrlys.iss
; Installerer for brukeren (uten administrator) i %LOCALAPPDATA%\Programs\Fyrlys, der appen kan oppdatere seg selv.
; AppId må aldri endres: oppdateringen setter versjonen under Apper i Windows via den (oppdater.ps1).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Source
  #define Source "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\installer-out"
#endif

[Setup]
AppId={{6E2B8C41-3F7A-4D2E-9B15-7C0A2F9D4E63}
AppName=Fyrlys
AppVersion={#AppVersion}
AppVerName=Fyrlys {#AppVersion}
AppPublisher=Fyrlys
AppPublisherURL=https://github.com/ungerdas/fyrlys
AppSupportURL=https://github.com/ungerdas/fyrlys/issues
AppUpdatesURL=https://github.com/ungerdas/fyrlys/releases
PrivilegesRequired=lowest
DefaultDirName={autopf}\Fyrlys
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\fyrlys.exe
UninstallDisplayName=Fyrlys
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=Fyrlys-oppsett
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no
ShowLanguageDialog=no

[Languages]
; språket i Windows (norsk eller engelsk); andre språk får engelsk, det første
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "norsk"; MessagesFile: "compiler:Languages\Norwegian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Source}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Fyrlys"; Filename: "{app}\fyrlys.exe"
Name: "{autodesktop}\Fyrlys"; Filename: "{app}\fyrlys.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\fyrlys.exe"; Description: "{cm:LaunchProgram,Fyrlys}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; nedlastede oppdateringer (innloggingen og innstillingene blir liggende, i tilfelle du installerer igjen)
Type: filesandordirs; Name: "{localappdata}\Fyrlys\oppdatering"
