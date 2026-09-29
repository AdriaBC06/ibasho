#!/usr/bin/env bash
# Ibasho — genera las versiones cantadas de Odori que falten: todas las voces
# (Teto, Kiritan, Zundamon, Merrow y Sinsy) en japonés y español, primero las
# japonesas. Se salta las que ya existen, así que se puede cortar y relanzar.
# Copyright (C) 2026 Adrià Bonnin Catalán
# SPDX-License-Identifier: GPL-3.0-or-later
#
#   nohup ./tool/odori_voces_todas.sh > voces.log 2>&1 &
#   tail -f voces.log
#
# JOBS=3 para más trabajos a la vez (por defecto 2). Tarda unas 3 h de CPU.
set -uo pipefail
cd "$(dirname "$0")/.."

PY="${ODORI_VOICES:-$HOME/.cache/ibasho-voices}/venv/bin/python"
JOBS="${JOBS:-2}"
SONGS=(tamagoyaki hanabi nekobasu kasa tsukimi kaerimichi ibasho yako)
VOICES=(teto kiritan zundamon merrow sinsy)

todo=()
for lang in ja es; do
  for song in "${SONGS[@]}"; do
    for voice in "${VOICES[@]}"; do
      id="${song}_${lang}_${voice}"
      [ -f "assets/odori/$song/$id.ogg" ] || todo+=("$id")
    done
  done
done

echo "$(date +%T) faltan ${#todo[@]} versiones, $JOBS a la vez"
printf '%s\n' "${todo[@]}" | xargs -P "$JOBS" -I{} sh -c \
  'echo "$(date +%T) empieza {}"; "$0" tool/gen_odori_music.py {} > /dev/null 2>&1 && echo "$(date +%T) hecha {}" || echo "$(date +%T) FALLA {}"' "$PY"

# Ningún temporal dentro de las carpetas que empaqueta la app.
find assets/odori -name '*.wav' -delete
echo "$(date +%T) fin. $(ls assets/odori/*/*.ogg | wc -l) canciones .ogg en total"
