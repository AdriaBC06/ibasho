// Ibasho — configuracion comun de los tests de Flutter.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:ibasho/state/login_bonus.dart';

/// El bono diario no se abre solo en los tests: taparia cada recorrido. El
/// suyo lo vuelve a encender.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  loginBonusAutoOpen = false;
  await testMain();
}
