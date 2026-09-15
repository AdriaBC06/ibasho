#!/usr/bin/env bash
# Ibasho — flujo de cuentas de extremo a extremo contra el emulador de Firebase.
# Copyright (C) 2026 Adrià Bonnin Catalán
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Levanta los emuladores de Auth y Realtime Database (procesos locales, nada de
# emuladores de dispositivo), ejecuta test/e2e/ con la app apuntando a ellos y
# los apaga. No toca el proyecto real.
#   ./tool/test_e2e.sh
set -euo pipefail
cd "$(dirname "$0")/.."

exec firebase emulators:exec \
  --project demo-ibasho \
  --only auth,database \
  "flutter test test/e2e \
     --dart-define=IBASHO_USE_EMULATOR=true \
     --dart-define=IBASHO_PROJECT_ID=demo-ibasho \
     --dart-define=IBASHO_API_KEY=demo-key \
     --dart-define=IBASHO_EMULATOR_HOST=127.0.0.1 \
     --dart-define=IBASHO_EMULATOR_DB_PORT=9000 \
     --dart-define=IBASHO_EMULATOR_AUTH_PORT=9099"
