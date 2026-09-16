#!/usr/bin/env bash
# Ibasho — instala la app en este equipo Linux, para el usuario actual.
# Copyright (C) 2026 Adrià Bonnin Catalán
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   ./tool/install_linux.sh             compila en release con .env e instala
#   ./tool/install_linux.sh --uninstall quita todo lo instalado
#
# Todo va a ~/.local, sin sudo:
#   ~/.local/share/ibasho/                          la build (ejecutable, lib, data)
#   ~/.local/bin/ibasho                             enlace para lanzarla desde la terminal
#   ~/.local/share/applications/top.ibasho.ibasho.desktop
#   ~/.local/share/icons/hicolor/*/apps/top.ibasho.ibasho.png
# La configuracion de Firebase de .env queda compilada dentro de la build.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_ID="top.ibasho.ibasho"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
PREFIX="$DATA/ibasho"
BIN="$HOME/.local/bin"
DESKTOP="$DATA/applications/$APP_ID.desktop"
ICONS="$DATA/icons/hicolor"

refresh_caches() {
  command -v update-desktop-database >/dev/null && update-desktop-database "$DATA/applications" || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$ICONS" || true
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$PREFIX" "$DESKTOP" "$BIN/ibasho"
  find "$ICONS" -name "$APP_ID.png" -delete 2>/dev/null || true
  refresh_caches
  echo "Ibasho desinstalado. Tus preferencias y la sesion guardada siguen en ~/.local/share/$APP_ID."
  exit 0
fi

if [ ! -f .env ]; then
  echo "Falta .env (copia .env.example y rellenalo)." >&2
  exit 78
fi

VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)"
echo "Compilando Ibasho $VERSION en release..."
flutter build linux --release --dart-define-from-file=.env

BUNDLE="build/linux/x64/release/bundle"
echo "Instalando en $PREFIX"
rm -rf "$PREFIX"
mkdir -p "$PREFIX" "$BIN" "$DATA/applications"
cp -r "$BUNDLE"/. "$PREFIX"/
ln -sf "$PREFIX/ibasho" "$BIN/ibasho"

for size in 48 64 128 256 512; do
  mkdir -p "$ICONS/${size}x${size}/apps"
  if command -v magick >/dev/null; then
    magick linux/packaging/ibasho.png -resize "${size}x${size}" "$ICONS/${size}x${size}/apps/$APP_ID.png"
  elif [ "$size" = 512 ]; then
    cp linux/packaging/ibasho.png "$ICONS/512x512/apps/$APP_ID.png"
  fi
done

cat > "$DESKTOP" <<DESK
[Desktop Entry]
Type=Application
Name=Ibasho
GenericName=Espacio de juegos
Comment=居場所, tu lugar
Exec=$PREFIX/ibasho
Path=$PREFIX
Icon=$APP_ID
Terminal=false
Categories=Game;
StartupWMClass=$APP_ID
X-Ibasho-Version=$VERSION
DESK

refresh_caches
echo "Listo: Ibasho $VERSION esta en el menu de aplicaciones (y 'ibasho' en la terminal)."
