; Ibasho — instalador de Windows.
; Copyright (C) 2026 Adrià Bonnin Catalán
; SPDX-License-Identifier: GPL-3.0-or-later
;
; No se compila a mano: lo llama tool\package_windows.ps1, que antes construye
; la release y le pasa la version leida de pubspec.yaml.
;
;   ISCC.exe /DAppVersion=0.3.3 windows\packaging\ibasho.iss
;
; El resultado es un unico .exe en dist\. La configuracion de Firebase de .env
; queda compilada dentro de la build, no la lleva el instalador.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "Ibasho"
#define AppPublisher "Adrià Bonnin Catalán"
#define AppExe "ibasho.exe"
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Este GUID identifica la app para actualizar y desinstalar: no cambia nunca.
; Sale de uuid5(DNS, "top.ibasho.ibasho"), el mismo id que usa el .desktop de Linux.
AppId={{F9413DB9-98AC-5CAD-89F6-2D47B16EC824}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppCopyright=Copyright (C) 2026 {#AppPublisher}. GPL-3.0-or-later.
VersionInfoVersion={#AppVersion}

; Como en Linux: se instala para el usuario, sin pedir administrador.
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE

; Ibasho pide Windows 10 o posterior, de 64 bits.
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

OutputDir=..\..\dist
OutputBaseFilename=Ibasho-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName} {#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Todo el bundle: el ejecutable, flutter_windows.dll, los DLL de los plugins
; y la carpeta data\ con los assets y el AOT.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Las preferencias y la sesion guardada no se borran: desinstalar no deberia
; perder la cuenta ni los Tamas. Viven en {userappdata}\<CompanyName>\<ProductName>,
; que path_provider saca del VERSIONINFO de Runner.rc; hoy eso es
; %APPDATA%\Adria Bonnin Catalan\Ibasho. Cambiar esos dos campos muda la carpeta
; y deja atras los datos de quien ya tuviera la app instalada.
Type: dirifempty; Name: "{app}"
