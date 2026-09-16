# Ibasho — compila la app para Windows y la empaqueta en un instalador.
# Copyright (C) 2026 Adrià Bonnin Catalán
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   .\tool\package_windows.ps1              compila en release con .env y empaqueta
#   .\tool\package_windows.ps1 -SkipBuild   solo empaqueta lo ya compilado
#
# Deja dos cosas en dist\:
#   Ibasho-<version>-windows-x64-setup.exe  instalador de un solo fichero
#   Ibasho-<version>-windows-x64.zip        la misma build, portable
# La configuracion de Firebase de .env queda compilada dentro de la build.

[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path '.env')) {
    Write-Error 'Falta .env (copia .env.example y rellenalo).'
    exit 78
}

# La version manda desde pubspec.yaml, igual que en Linux.
$pubspec = Get-Content 'pubspec.yaml' -Raw
$m = [regex]::Match($pubspec, '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)')
if (-not $m.Success) { Write-Error 'No se ha podido leer version: de pubspec.yaml'; exit 1 }
$version = $m.Groups[1].Value

$release = 'build\windows\x64\runner\Release'

if (-not $SkipBuild) {
    Write-Host "Compilando Ibasho $version en release..."
    & flutter build windows --release --dart-define-from-file=.env
    if ($LASTEXITCODE -ne 0) { Write-Error 'La compilacion ha fallado.'; exit $LASTEXITCODE }
}

if (-not (Test-Path (Join-Path $release 'ibasho.exe'))) {
    Write-Error "No hay build en $release. Ejecuta sin -SkipBuild."
    exit 1
}

# Un Windows 10 recien instalado trae el CRT universal (api-ms-win-crt-*) pero no
# el runtime de Visual C++. Sin estos tres la app no arranca y el error que sale
# no dice cual falta, asi que viajan dentro del paquete en vez de exigir el
# redistribuible. Solo dependen entre ellos y del CRT del sistema.
$runtime = 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'
$faltan = $runtime | Where-Object { -not (Test-Path (Join-Path $release $_)) }
if ($faltan) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { Write-Error 'No se encuentra vswhere.exe; falta Visual Studio.'; exit 1 }
    $vs = & $vswhere -latest -products * -property installationPath
    $crt = Get-ChildItem (Join-Path $vs 'VC\Redist\MSVC') -Directory -Recurse -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' -and $_.FullName -notmatch 'onecore' } |
        Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $crt) { Write-Error 'No se encuentra el redistribuible de Visual C++ en la instalacion de Visual Studio.'; exit 1 }
    Write-Host "Copiando el runtime de Visual C++ desde $($crt.FullName)"
    foreach ($dll in $faltan) { Copy-Item (Join-Path $crt.FullName $dll) $release -Force }
}

New-Item -ItemType Directory -Force 'dist' | Out-Null

# ISCC no se instala en el PATH, asi que se busca donde lo dejan winget y el
# instalador oficial.
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Write-Error 'No se encuentra ISCC.exe. Instala Inno Setup 6: winget install JRSoftware.InnoSetup'
    exit 1
}

Write-Host "Empaquetando el instalador con $iscc"
& $iscc "/DAppVersion=$version" 'windows\packaging\ibasho.iss'
if ($LASTEXITCODE -ne 0) { Write-Error 'Inno Setup ha fallado.'; exit $LASTEXITCODE }

$zip = "dist\Ibasho-$version-windows-x64.zip"
Write-Host "Comprimiendo la version portable en $zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $release '*') -DestinationPath $zip

Write-Host ''
Write-Host "Listo. En dist\:"
Get-ChildItem 'dist' -File | ForEach-Object {
    '{0,-46} {1,8:N1} MB' -f $_.Name, ($_.Length / 1MB)
}
