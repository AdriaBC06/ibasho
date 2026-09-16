// Ibasho — reloj, bateria y calidad de la conexion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import '../core/device.dart';

/// Reloj del entorno. Late al segundo, alineado con el reloj del sistema.
class Clock extends StateNotifier<DateTime> {
  Clock() : super(DateTime.now()) {
    _align();
  }

  Timer? _timer;

  /// En segundo plano el reloj no late: nadie lo ve.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_timer != null) return;
    state = DateTime.now();
    _align();
  }

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
  SystemStatusController(this._backend, {BatteryWatch? battery})
      : _battery = battery ?? PluginBatteryWatch(),
        super(const SystemStatus()) {
    _start();
  }

  final IbashoBackend _backend;
  final BatteryWatch _battery;

  Timer? _batteryTimer;
  Timer? _linkTimer;
  StreamSubscription<void>? _batteryChanges;

  void _start() {
    unawaited(_refreshBattery());
    unawaited(_refreshLink());
    _batteryChanges = _battery.changes.listen(
      (_) => unawaited(_refreshBattery()),
      onError: (Object e) => debugPrint('Ibasho: avisos de bateria ($e)'),
    );
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

  /// En segundo plano no se mide nada.
  void pause() {
    _batteryTimer?.cancel();
    _linkTimer?.cancel();
    unawaited(_batteryChanges?.cancel());
    _batteryTimer = null;
    _linkTimer = null;
    _batteryChanges = null;
  }

  /// Al volver se mide al momento: la red puede haber cambiado entretanto.
  void resume() {
    if (_linkTimer != null) return;
    _start();
  }

  @override
  void dispose() {
    pause();
    super.dispose();
  }

  Future<void> _refreshLink() async {
    final quality = await _backend.probe();
    if (mounted) state = SystemStatus(battery: state.battery, link: quality);
  }

  Future<void> _refreshBattery() async {
    final info = await _battery.read();
    if (mounted) state = SystemStatus(battery: info, link: state.link);
  }
}

/// De donde sale la bateria. Se sustituye en los tests.
abstract interface class BatteryWatch {
  /// Nivel y carga, o `null` si el equipo no tiene bateria.
  Future<BatteryInfo?> read();

  /// Avisa cuando cambia el estado de carga.
  Stream<void> get changes;
}

/// Bateria por `battery_plus`: el mismo camino en Android y en Linux (UPower).
///
/// Devuelve `null` en cuanto algo no cuadra: un sobremesa no tiene bateria
/// (UPower da estado desconocido) y la barra de estado no debe inventarse una.
class PluginBatteryWatch implements BatteryWatch {
  final Battery _plugin = Battery();

  /// Ultimo estado de carga conocido. En Linux, preguntar el estado abre una
  /// conexion de D-Bus que el plugin no cierra; el flujo de cambios usa una
  /// sola, asi que el estado sale de ahi y solo el nivel se pregunta.
  BatteryState? _state;

  /// En Android el flujo del plugin necesita un permiso privado de androidx
  /// para registrar su receptor, y ese permiso se quita del manifiesto (ver
  /// AndroidManifest.xml): la bateria se lee sondeando, que es lo que hacia
  /// la version de Linux desde el principio.
  @override
  Stream<void> get changes => Device.isAndroid
      ? const Stream<void>.empty()
      : _plugin.onBatteryStateChanged.map((state) => _state = state);

  @override
  Future<BatteryInfo?> read() async {
    try {
      final state = _state ?? await _plugin.batteryState;
      _state = state;
      if (state == BatteryState.unknown) return null;
      final level = await _plugin.batteryLevel;
      return BatteryInfo(
        level: level.clamp(0, 100),
        charging: state == BatteryState.charging || state == BatteryState.full,
      );
    } catch (e) {
      return null;
    }
  }
}
