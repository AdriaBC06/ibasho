// Ibasho — donde guarda cada juego sus récords, en un JSON local.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Un archivo `<nombre>.json` en el directorio de la app. Sin directorio (en
/// los tests de widgets) guarda solo en memoria mientras dure el proceso.
class GameStore {
  GameStore._(this._file);

  final File? _file;
  Map<String, Object?> _memory = const <String, Object?>{};

  static Future<GameStore> open(String name) async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return GameStore._(File('${dir.path}/$name.json'));
    } catch (e) {
      debugPrint('Ibasho: sin directorio local para $name ($e)');
      return GameStore._(null);
    }
  }

  Future<Map<String, Object?>> load() async {
    final file = _file;
    if (file == null) return _memory;
    try {
      if (!await file.exists()) return const <String, Object?>{};
      final raw = jsonDecode(await file.readAsString());
      return raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    } catch (e) {
      debugPrint('Ibasho: récords ilegibles en ${file.path} ($e)');
      return const <String, Object?>{};
    }
  }

  Future<void> save(Map<String, Object?> json) async {
    final file = _file;
    if (file == null) {
      _memory = json;
      return;
    }
    try {
      await file.writeAsString(jsonEncode(json), flush: true);
    } catch (e) {
      debugPrint('Ibasho: no se han podido guardar los récords ($e)');
    }
  }
}

int readInt(Object? v) => v is num ? v.toInt() : 0;
