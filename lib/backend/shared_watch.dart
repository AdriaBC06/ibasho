// Ibasho — una sola conexión en tiempo real por ruta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'live_tree.dart';
import 'models.dart';

/// Reparte una única conexión por clave (ruta y consulta) entre todos los que
/// la miran.
///
/// Cada `watch` abierto cuenta contra las cien conexiones del plan gratis de
/// Firebase. Aquí cada ruta abre la suya la primera vez que alguien escucha y
/// la cierra cuando se va el último. A quien llega tarde se le entrega el árbol
/// que ya se conoce como un `put` de la raíz, igual que recibió el primero.
class SharedWatches {
  final Map<String, _Shared> _entries = <String, _Shared>{};

  /// Conexiones abiertas ahora mismo (para depuración y tests).
  int get open => _entries.length;

  Stream<DatabaseEvent> watch(
    String key,
    Stream<DatabaseEvent> Function() source,
  ) {
    late final StreamController<DatabaseEvent> controller;
    controller = StreamController<DatabaseEvent>(
      onListen: () {
        final entry = _entries.putIfAbsent(key, () => _Shared(source));
        entry.add(controller);
      },
      onCancel: () {
        final entry = _entries[key];
        if (entry == null) return;
        entry.remove(controller);
        if (entry.listeners.isEmpty) {
          _entries.remove(key);
          entry.close();
        }
      },
    );
    return controller.stream;
  }
}

class _Shared {
  _Shared(this._source);

  final Stream<DatabaseEvent> Function() _source;
  final List<StreamController<DatabaseEvent>> listeners =
      <StreamController<DatabaseEvent>>[];
  StreamSubscription<DatabaseEvent>? _sub;
  Object? _tree;
  bool _hasTree = false;

  void add(StreamController<DatabaseEvent> controller) {
    listeners.add(controller);
    if (_hasTree) {
      controller.add(DatabaseEvent(path: '/', data: _tree, isPatch: false));
    }
    _sub ??= _source().listen(
      (event) {
        _tree = applyDatabaseEvent(_tree, event);
        _hasTree = true;
        for (final l in List<StreamController<DatabaseEvent>>.of(listeners)) {
          if (!l.isClosed) l.add(event);
        }
      },
      onError: (Object error, StackTrace stack) {
        for (final l in List<StreamController<DatabaseEvent>>.of(listeners)) {
          if (!l.isClosed) l.addError(error, stack);
        }
      },
    );
  }

  void remove(StreamController<DatabaseEvent> controller) =>
      listeners.remove(controller);

  void close() {
    unawaited(_sub?.cancel());
    _sub = null;
  }
}
