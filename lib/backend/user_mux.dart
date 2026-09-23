// Ibasho — una sola conexion en tiempo real para toda la cuenta propia.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'live_tree.dart';
import 'models.dart';

/// Reparte un unico stream de `/users/<cuenta>` entre todos los que miran un
/// hijo suyo.
///
/// Cada `watch` de la Realtime Database es una conexion abierta, y el plan
/// gratis de Firebase solo aguanta cien a la vez en todo el proyecto. Ibasho
/// miraba una docena de nodos de la cuenta por separado (monedas, despensa,
/// tickets, gacha, amigos, buzon...), asi que cinco personas conectadas ya
/// rozaban el tope. Aqui se abre **una** conexion a la cuenta entera y de ahi
/// salen todas las demas: el dueño puede leerla completa, asi que las reglas
/// lo permiten sin tocar nada.
///
/// A quien mira un hijo se le entrega siempre un `put` de su subarbol entero,
/// que es lo mismo que recibia del stream propio la primera vez.
class UserNodeMux {
  UserNodeMux({required Stream<DatabaseEvent> Function() source}) : _source = source;

  final Stream<DatabaseEvent> Function() _source;

  /// El arbol de la cuenta, al dia con lo que va llegando.
  Object? _tree;

  StreamSubscription<DatabaseEvent>? _sub;
  final List<_MuxChild> _children = <_MuxChild>[];

  /// Cuantas conexiones se estan ahorrando ahora mismo (para depuracion).
  int get watchers => _children.length;

  /// El subarbol `path` (relativo a la cuenta, p. ej. `tickets` o
  /// `shop/week`), como stream de eventos igual que el de un `watch` propio.
  Stream<DatabaseEvent> child(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList(growable: false);
    late final _MuxChild entry;
    late final StreamController<DatabaseEvent> controller;
    controller = StreamController<DatabaseEvent>(
      onListen: () {
        _children.add(entry);
        _connect();
        // Si el arbol ya esta en memoria, quien llega tarde no espera al
        // siguiente cambio: se le entrega lo que hay.
        if (_tree != null) entry.emit(_tree);
      },
      onCancel: () {
        _children.remove(entry);
        if (_children.isEmpty) _disconnect();
      },
    );
    entry = _MuxChild(segments: segments, controller: controller);
    return controller.stream;
  }

  /// Corta la conexion y olvida el arbol: al cerrar sesion.
  void reset() {
    _disconnect();
    _tree = null;
  }

  void _connect() {
    if (_sub != null) return;
    _sub = _source().listen(
      (event) {
        _tree = applyDatabaseEvent(_tree, event);
        final touched = _segmentsOf(event.path);
        for (final child in List<_MuxChild>.of(_children)) {
          if (child.affectedBy(touched)) child.emit(_tree);
        }
      },
      onError: (Object error, StackTrace stack) {
        for (final child in List<_MuxChild>.of(_children)) {
          child.controller.addError(error, stack);
        }
      },
    );
  }

  void _disconnect() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  static List<String> _segmentsOf(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList(growable: false);
}

class _MuxChild {
  _MuxChild({required this.segments, required this.controller});

  final List<String> segments;
  final StreamController<DatabaseEvent> controller;

  /// Un evento toca a este hijo si cae dentro de su subarbol o por encima de
  /// el (un `put` en la raiz de la cuenta lo cambia todo).
  bool affectedBy(List<String> touched) {
    final shared = touched.length < segments.length ? touched.length : segments.length;
    for (var i = 0; i < shared; i++) {
      if (touched[i] != segments[i]) return false;
    }
    return true;
  }

  void emit(Object? tree) {
    if (controller.isClosed) return;
    var node = tree;
    for (final segment in segments) {
      node = node is Map ? node[segment] : null;
    }
    controller.add(DatabaseEvent(path: '/', data: node, isPatch: false));
  }
}
