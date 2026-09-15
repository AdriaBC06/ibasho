// Ibasho — reloj, bateria y calidad de la conexion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';

/// Reloj del entorno. Late al segundo, alineado con el reloj del sistema.
class Clock extends StateNotifier<DateTime> {
  Clock() : super(DateTime.now()) {
    _align();
  }

  Timer? _timer;

  void _align() {
    final now = DateTime.now();
    final toNextSecond = 1000 - now.millisecond;
    _timer = Timer(Duration(milliseconds: toNextSecond), () {
      state = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        state = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

@immutable
class BatteryInfo {
  const BatteryInfo({required this.level, required this.charging});

  /// 0 a 100.
  final int level;
  final bool charging;
}

@immutable
class SystemStatus {
  const SystemStatus({this.battery, this.link = LinkQuality.offline});

  /// `null` cuando el equipo no tiene bateria: entonces no se dibuja nada ni
  /// se deja hueco en la barra de estado.
  final BatteryInfo? battery;

  final LinkQuality link;
}

/// Estado del sistema que se ve en la esquina superior derecha.
class SystemStatusController extends StateNotifier<SystemStatus> {
  SystemStatusController(this._backend) : super(const SystemStatus()) {
    unawaited(_refreshBattery());
    unawaited(_refreshLink());
    _batteryTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshBattery()),
    );
    // El checkpoint pide comprobar conectividad real contra el endpoint de la
    // base cada 30 segundos, no fiarse de que exista una interfaz de red.
    _linkTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshLink()),
    );
  }

  final IbashoBackend _backend;

  Timer? _batteryTimer;
  Timer? _linkTimer;

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _linkTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLink() async {
    final quality = await _backend.probe();
    if (mounted) state = SystemStatus(battery: state.battery, link: quality);
  }

  Future<void> _refreshBattery() async {
    final info = await readBattery();
    if (mounted) state = SystemStatus(battery: info, link: state.link);
  }
}

/// Lee la bateria de sysfs. Sin dependencias y sin plugins.
///
/// Devuelve `null` en cuanto algo no cuadra: un sobremesa no tiene bateria y
/// la barra de estado no debe inventarse una.
Future<BatteryInfo?> readBattery() async {
  if (!Platform.isLinux) return null;
  try {
    final root = Directory('/sys/class/power_supply');
    if (!await root.exists()) return null;
    await for (final entry in root.list(followLinks: true)) {
      final name = entry.path.split('/').last;
      if (!name.startsWith('BAT')) continue;
      final capacity = File('${entry.path}/capacity');
      if (!await capacity.exists()) continue;
      final level = int.tryParse((await capacity.readAsString()).trim());
      if (level == null) continue;
      var charging = false;
      final status = File('${entry.path}/status');
      if (await status.exists()) {
        final value = (await status.readAsString()).trim().toLowerCase();
        charging = value == 'charging' || value == 'full';
      }
      return BatteryInfo(level: level.clamp(0, 100), charging: charging);
    }
  } catch (e) {
    debugPrint('Ibasho: no se ha podido leer la bateria ($e)');
  }
  return null;
}
