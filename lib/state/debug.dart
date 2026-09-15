// Ibasho — interruptores del canal de depuracion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class DebugFlags {
  const DebugFlags({this.slowMotion = false, this.performanceOverlay = false});

  final bool slowMotion;
  final bool performanceOverlay;
}

/// No se persiste a proposito: son herramientas de una sesion de pruebas y no
/// deben quedarse puestas por accidente al volver a abrir la app.
class DebugController extends StateNotifier<DebugFlags> {
  DebugController() : super(const DebugFlags());

  void setSlowMotion(bool value) {
    timeDilation = value ? 5.0 : 1.0;
    state = DebugFlags(slowMotion: value, performanceOverlay: state.performanceOverlay);
  }

  void setPerformanceOverlay(bool value) =>
      state = DebugFlags(slowMotion: state.slowMotion, performanceOverlay: value);

  @override
  void dispose() {
    timeDilation = 1.0;
    super.dispose();
  }
}

final debugProvider =
    StateNotifierProvider<DebugController, DebugFlags>((_) => DebugController());
