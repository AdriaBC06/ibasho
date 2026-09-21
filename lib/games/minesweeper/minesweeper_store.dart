// Ibasho — mejor tiempo por dificultad, guardado en local.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Sigue el mismo patron que `lib/storage/settings_store.dart`: un archivo
// JSON en el directorio de datos de la aplicacion, sin depender de
// `shared_preferences`. No pasa por Riverpod porque solo lo usa este canal.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'minesweeper.dart';

/// Los mejores tiempos conocidos, uno por dificultad. Ausente si nunca se ha
/// ganado en ese nivel.
class MinesweeperStore {
  MinesweeperStore(this._file);

  final File _file;

  static Future<MinesweeperStore> open() async {
    try {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return MinesweeperStore(File('${dir.path}/minesweeper.json'));
    } catch (e) {
      // Sin `path_provider` de verdad (por ejemplo en los tests de widgets)
      // se guarda solo mientras dure el proceso.
      debugPrint('Ibasho: sin directorio local para el buscaminas ($e)');
      return MinesweeperStore(File(''));
    }
  }

  Future<Map<MinesweeperLevel, Duration>> loadBestTimes() async {
    try {
      if (!await _file.exists()) return const <MinesweeperLevel, Duration>{};
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, Object?>) return const <MinesweeperLevel, Duration>{};
      final best = <MinesweeperLevel, Duration>{};
      for (final level in MinesweeperLevel.values) {
        final ms = decoded[level.name];
        if (ms is num) best[level] = Duration(milliseconds: ms.toInt());
      }
      return best;
    } catch (e) {
      debugPrint('Ibasho: mejores tiempos de buscaminas ilegibles ($e)');
      return const <MinesweeperLevel, Duration>{};
    }
  }

  /// Guarda el tiempo si es mejor que el que hubiera. Devuelve el mapa
  /// resultante para que quien llama no tenga que releer el archivo.
  Future<Map<MinesweeperLevel, Duration>> recordTime(
    Map<MinesweeperLevel, Duration> current,
    MinesweeperLevel level,
    Duration time,
  ) async {
    final previous = current[level];
    if (previous != null && previous <= time) return current;
    final next = Map<MinesweeperLevel, Duration>.from(current)..[level] = time;
    try {
      final json = {for (final e in next.entries) e.key.name: e.value.inMilliseconds};
      await _file.writeAsString(jsonEncode(json), flush: true);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar el mejor tiempo ($e)');
    }
    return next;
  }
}
