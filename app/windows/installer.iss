#ifndef SourceDir
  #define SourceDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif
#ifndef AppVersion
  #define AppVersion "0.2.6"
#endif

[Setup]
AppId={{7F3C1A92-6E4B-4C8D-9A15-2D8E0B6F4C31}}
AppName=Vitalog
AppVersion={#AppVersion}
AppPublisher=BSOC
DefaultDirName={autopf}\Vitalog
DefaultGroupName=Vitalog
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=Vitalog-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\Vitalog.exe
WizardStyle=modern

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Vitalog"; Filename: "{app}\Vitalog.exe"
