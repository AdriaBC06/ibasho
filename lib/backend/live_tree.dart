// Ibasho — un arbol JSON que se mantiene al dia con los eventos del stream.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'models.dart';

/// Aplica un evento `put` o `patch` de la Realtime Database a una copia local
/// del nodo suscrito y devuelve el arbol resultante.
///
/// `put` sustituye lo que haya en la ruta (con `null` lo borra); `patch`
/// fusiona los hijos que trae. Asi un controlador puede suscribirse a un nodo
/// con muchos hijos y seguir teniendo el nodo entero en memoria.
Object? applyDatabaseEvent(Object? tree, DatabaseEvent event) {
  final segments = _segments(event.path);
  if (!event.isPatch) return _setAt(tree, segments, _clone(event.data));
  final data = event.data;
  if (data is! Map) return tree;
  var next = tree;
  data.forEach((key, value) {
    next = _setAt(next, [...segments, ..._segments('$key')], _clone(value));
  });
  return next;
}

List<String> _segments(String path) =>
    path.split('/').where((s) => s.isNotEmpty).toList(growable: false);

Object? _clone(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': _clone(entry.value),
    };
  }
  if (value is List) return value.map(_clone).toList();
  return value;
}

Object? _setAt(Object? tree, List<String> path, Object? value) {
  if (path.isEmpty) return value;
  final map = tree is Map
      ? <String, Object?>{for (final e in tree.entries) '${e.key}': e.value}
      : <String, Object?>{};
  final head = path.first;
  final child = _setAt(map[head], path.sublist(1), value);
  if (child == null || (child is Map && child.isEmpty)) {
    map.remove(head);
  } else {
    map[head] = child;
  }
  return map.isEmpty ? null : map;
}
