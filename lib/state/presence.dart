// Ibasho — presencia propia: conectado, ausente, no molestar, invisible.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import '../backend/rtdb_socket.dart';
import '../backend/social.dart';
import 'session.dart';

@immutable
class PresenceStatus {
  const PresenceStatus({
    this.mode = PresenceMode.online,
    this.connected = false,
  });

  /// Lo que ha elegido la persona. Mientras no elija otra cosa, conectado.
  final PresenceMode mode;

  /// Hay conexion persistente con el servidor.
  final bool connected;

  /// Lo que ven sus amigos.
  PresenceState get published => publishedFor(mode);

  PresenceStatus copyWith({PresenceMode? mode, bool? connected}) => PresenceStatus(
        mode: mode ?? this.mode,
        connected: connected ?? this.connected,
      );
}

/// Estado publicado para una eleccion. No hay estados automaticos: sale lo que
/// la persona ha elegido, y nada mas. Invisible publica exactamente lo mismo
/// que una desconexion.
PresenceState publishedFor(PresenceMode mode) => switch (mode) {
      PresenceMode.online => PresenceState.online,
      PresenceMode.away => PresenceState.away,
      PresenceMode.busy => PresenceState.busy,
      PresenceMode.invisible => PresenceState.offline,
    };

/// Publica la presencia de la cuenta en `/users/{accountId}/presence`.
///
/// Va por una conexion persistente ([PresenceLink]) y no por REST por una
/// razon: al conectar se encarga al servidor que escriba `offline` cuando esa
/// conexion se pierda (`onDisconnect`). Cerrar la app, que se cuelgue o que se
/// vaya la red deja a la persona desconectada sin que el cliente haga nada.
///
/// Invisible es indistinguible de desconectado: se anula el encargo, se
/// publica `offline` con la misma forma que deja una desconexion de verdad (y
/// solo si no estaba ya asi, para no mover `lastSeen`), y no se vuelve a
/// escribir nada mientras dure.
///
/// Estar dentro de la app es lo que publica el estado elegido; estar fuera
/// publica `offline`. No hay ausente automatico: si alguien sale a ausente es
/// porque lo ha elegido.
class PresenceController extends StateNotifier<PresenceStatus> {
  PresenceController({
    required IbashoBackend backend,
    required SessionController session,
    required bool active,
  })  : _backend = backend,
        _session = session,
        super(const PresenceStatus()) {
    if (active && session.state.accountId.isNotEmpty) unawaited(_start());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  PresenceLink? _link;
  StreamSubscription<bool>? _connection;

  /// La app esta en segundo plano: no hay conexion abierta.
  bool _suspended = false;

  /// Lo ultimo que se sabe publicado en el servidor.
  PresenceState? _serverState;
  bool _applying = false;
  bool _dirty = false;

  String get _path => '/users/${_session.state.accountId}/presence';

  @override
  void dispose() {
    unawaited(_connection?.cancel());
    // Cerrar la conexion basta: el servidor ejecuta lo encargado.
    unawaited(_link?.close());
    super.dispose();
  }

  /// La app pasa a segundo plano (solo movil).
  ///
  /// Fuera de la app no se esta: se publica `offline`, que es justo lo que
  /// dejaria el `onDisconnect`, y se cierra el websocket limpiamente. Quien ya
  /// estaba invisible no toca nada, porque ya publica exactamente eso.
  Future<void> suspend() async {
    if (_suspended) return;
    _suspended = true;
    final link = _link;
    final subscription = _connection;
    _link = null;
    _connection = null;
    await subscription?.cancel();
    if (link == null) return;
    if (link.isConnected && _serverState != PresenceState.offline) {
      final value = {'state': PresenceState.offline.name, 'lastSeen': serverTimestamp};
      try {
        await link.setOnDisconnect(_path, value);
        await link.set(_path, value);
        _serverState = PresenceState.offline;
      } catch (e) {
        debugPrint('Ibasho: no se ha podido dejar la presencia en desconectado ($e)');
      }
    }
    await link.close();
    if (mounted) state = state.copyWith(connected: false);
  }

  /// Vuelve del segundo plano: conexion nueva, con su retroceso, y la
  /// presencia de siempre en cuanto conecte.
  Future<void> resume() async {
    if (!_suspended || !mounted) return;
    _suspended = false;
    _serverState = null;
    await _start();
  }

  Future<void> _start() async {
    final account = _session.state.accountId;
    try {
      final token = await _session.freshToken();
      final results = await Future.wait([
        _backend.read('/users/$account/presenceMode', idToken: token),
        _backend.read(_path, idToken: token),
      ]);
      if (!mounted) return;
      _serverState = Presence.fromJson(results[1]).state;
      state = state.copyWith(mode: PresenceMode.byName(results[0]));
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer la presencia ($e)');
    }
    if (!mounted || _suspended) return;

    final link = _link = _backend.openPresenceLink(token: _session.freshToken);
    _connection = link.connection.listen((up) {
      if (!mounted) return;
      state = state.copyWith(connected: up);
      if (up) {
        // Tras una caida el servidor ya ejecuto el encargo: se desconoce lo
        // publicado y se vuelve a encargar todo.
        _serverState = null;
        unawaited(_apply());
      }
    });
  }

  /// Fija el estado a mano. Se guarda en la cuenta.
  Future<void> setMode(PresenceMode mode) async {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
    unawaited(_apply());
    try {
      await _backend.write(
        '/users/${_session.state.accountId}/presenceMode',
        mode.name,
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar el estado elegido ($e)');
    }
  }

  /// Lleva el servidor a lo que toca. Las llamadas que llegan a mitad se
  /// juntan en una pasada mas.
  Future<void> _apply() async {
    if (_applying) {
      _dirty = true;
      return;
    }
    _applying = true;
    try {
      do {
        _dirty = false;
        await _applyOnce();
      } while (_dirty && mounted);
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyOnce() async {
    final link = _link;
    if (link == null || !link.isConnected || !mounted) return;
    final target = state.published;
    final offline = {'state': PresenceState.offline.name, 'lastSeen': serverTimestamp};
    try {
      if (state.mode == PresenceMode.invisible) {
        await link.cancelOnDisconnect(_path);
        // Si no se sabe que hay publicado, se mira antes: reescribir un
        // `offline` que ya estaba moveria `lastSeen`, y eso si se veria.
        _serverState ??= Presence.fromJson(
          await _backend.read(_path, idToken: await _session.freshToken()),
        ).state;
        if (_serverState != PresenceState.offline) {
          // Lo mismo que habria dejado una desconexion en este instante.
          await link.set(_path, offline);
          _serverState = PresenceState.offline;
        }
        return;
      }
      if (_serverState == target) return;
      await link.setOnDisconnect(_path, offline);
      await link.set(_path, {'state': target.name, 'lastSeen': serverTimestamp});
      _serverState = target;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido publicar la presencia ($e)');
    }
  }
}
