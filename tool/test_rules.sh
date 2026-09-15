#!/usr/bin/env bash
# Ibasho — lanza los tests de las reglas de la Realtime Database.
# Copyright (C) 2026 Adrià Bonnin Catalán
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Levanta el emulador de Firebase, ejecuta los tests y lo apaga.
#   ./tool/test_rules.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d test/rules/node_modules ]; then
  echo "Instalando dependencias de los tests..."
  npm --prefix test/rules install --no-audit --no-fund
fi

export GCLOUD_PROJECT=demo-ibasho
exec firebase emulators:exec \
  --project demo-ibasho \
  --only database \
  "npm --prefix test/rules test"
