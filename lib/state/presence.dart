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
    this.idle = false,
    this.connected = false,
  });

  /// Lo que ha elegido la persona.
  final PresenceMode mode;

  /// Lleva un rato sin tocar nada.
  final bool idle;

  /// Hay conexion persistente con el servidor.
  final bool connected;

  /// Lo que ven sus amigos.
  PresenceState get published => publishedFor(mode, idle: idle);

  PresenceStatus copyWith({PresenceMode? mode, bool? idle, bool? connected}) => PresenceStatus(
        mode: mode ?? this.mode,
        idle: idle ?? this.idle,
        connected: connected ?? this.connected,
      );
}

/// Estado publicado para una eleccion. Invisible publica exactamente lo mismo
/// que una desconexion.
PresenceState publishedFor(PresenceMode mode, {required bool idle}) => switch (mode) {
      PresenceMode.online => idle ? PresenceState.away : PresenceState.online,
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
class PresenceController extends StateNotifier<PresenceStatus> {
  PresenceController({
    required IbashoBackend backend,
    required SessionController session,
    required bool active,
    this.idleAfter = const Duration(minutes: 5),
  })  : _backend = backend,
        _session = session,
        super(const PresenceStatus()) {
    if (active && session.state.accountId.isNotEmpty) unawaited(_start());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  /// Sin interaccion durante este rato, conectado pasa a ausente.
  final Duration idleAfter;

  PresenceLink? _link;
  StreamSubscription<bool>? _connection;
  Timer? _idleCheck;
  DateTime _lastActivity = DateTime.now();

  /// Lo ultimo que se sabe publicado en el servidor.
  PresenceState? _serverState;
  bool _applying = false;
  bool _dirty = false;

  String get _path => '/users/${_session.state.accountId}/presence';

  @override
  void dispose() {
    _idleCheck?.cancel();
    unawaited(_connection?.cancel());
    // Cerrar la conexion basta: el servidor ejecuta lo encargado.
    unawaited(_link?.close());
    super.dispose();
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
    if (!mounted) return;

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

    _idleCheck = Timer.periodic(const Duration(seconds: 15), (_) => _checkIdle());
  }

  /// Hay movimiento: raton, teclado, un toque.
  void activity() {
    _lastActivity = DateTime.now();
    if (state.idle && mounted) {
      state = state.copyWith(idle: false);
      unawaited(_apply());
    }
  }

  void _checkIdle() {
    if (!mounted || state.idle) return;
    if (DateTime.now().difference(_lastActivity) >= idleAfter) {
      state = state.copyWith(idle: true);
      unawaited(_apply());
    }
  }

  /// Fija el estado a mano. Se guarda en la cuenta.
  Future<void> setMode(PresenceMode mode) async {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode, idle: false);
    _lastActivity = DateTime.now();
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
