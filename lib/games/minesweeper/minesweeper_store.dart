// Ibasho — récords del buscaminas, guardados en local.
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

/// Las medallas, de peor a mejor. Se gana una segun el tiempo de la
/// victoria; por encima del tiempo del bronce no hay medalla.
enum Medal { bronze, silver, gold }

/// Tiempos de cada medalla por nivel: oro, plata y bronce.
const Map<MinesweeperLevel, (int gold, int silver, int bronze)> medalSeconds = {
  MinesweeperLevel.easy: (30, 60, 120),
  MinesweeperLevel.medium: (90, 180, 300),
  MinesweeperLevel.hard: (180, 360, 600),
};

/// La medalla que da un tiempo en un nivel, o `null` si es demasiado lento.
Medal? medalFor(MinesweeperLevel level, Duration time) {
  final (gold, silver, bronze) = medalSeconds[level]!;
  final s = time.inMilliseconds / 1000;
  if (s <= gold) return Medal.gold;
  if (s <= silver) return Medal.silver;
  if (s <= bronze) return Medal.bronze;
  return null;
}

/// La clave de un dia en el registro del tablero del dia: aaaa-mm-dd.
String dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Todo lo que se recuerda del buscaminas.
@immutable
class MinesweeperRecords {
  const MinesweeperRecords({
    this.best = const <MinesweeperLevel, Duration>{},
    this.medals = const <MinesweeperLevel, Medal>{},
    this.noFlags = const <MinesweeperLevel>{},
    this.wins = const <MinesweeperLevel, int>{},
    this.daily = const <String, Duration>{},
  });

  /// Mejor tiempo por nivel.
  final Map<MinesweeperLevel, Duration> best;

  /// Mejor medalla por nivel.
  final Map<MinesweeperLevel, Medal> medals;

  /// Niveles ganados alguna vez sin poner ni una bandera: el sello.
  final Set<MinesweeperLevel> noFlags;

  /// Victorias por nivel.
  final Map<MinesweeperLevel, int> wins;

  /// Mejor tiempo del tablero del dia, por dia. Solo se guardan los ultimos.
  final Map<String, Duration> daily;

  static const int _dailyKept = 31;

  Map<String, Object?> toJson() => {
        'v': 2,
        'best': {for (final e in best.entries) e.key.name: e.value.inMilliseconds},
        'medals': {for (final e in medals.entries) e.key.name: e.value.name},
        'noFlags': [for (final l in noFlags) l.name],
        'wins': {for (final e in wins.entries) e.key.name: e.value},
        'daily': {for (final e in daily.entries) e.key: e.value.inMilliseconds},
      };

  static MinesweeperRecords fromJson(Object? raw) {
    if (raw is! Map) return const MinesweeperRecords();
    MinesweeperLevel? level(Object? name) =>
        MinesweeperLevel.values.where((l) => l.name == name).firstOrNull;

    // La 0.5.0 de antes guardaba solo `{nivel: ms}` en la raiz.
    final bestRaw = raw['v'] == null ? raw : raw['best'];
    final best = <MinesweeperLevel, Duration>{};
    if (bestRaw is Map) {
      for (final e in bestRaw.entries) {
        final l = level(e.key);
        if (l != null && e.value is num) best[l] = Duration(milliseconds: (e.value as num).toInt());
      }
    }
    final medals = <MinesweeperLevel, Medal>{};
    final medalsRaw = raw['medals'];
    if (medalsRaw is Map) {
      for (final e in medalsRaw.entries) {
        final l = level(e.key);
        final m = Medal.values.where((m) => m.name == e.value).firstOrNull;
        if (l != null && m != null) medals[l] = m;
      }
    }
    // Quien ya tenia tiempos antes de las medallas se las lleva igual.
    for (final e in best.entries) {
      final m = medalFor(e.key, e.value);
      if (m != null && (medals[e.key]?.index ?? -1) < m.index) medals[e.key] = m;
    }
    final noFlags = <MinesweeperLevel>{};
    final noFlagsRaw = raw['noFlags'];
    if (noFlagsRaw is List) {
      for (final n in noFlagsRaw) {
        final l = level(n);
        if (l != null) noFlags.add(l);
      }
    }
    final wins = <MinesweeperLevel, int>{};
    final winsRaw = raw['wins'];
    if (winsRaw is Map) {
      for (final e in winsRaw.entries) {
        final l = level(e.key);
        if (l != null && e.value is num) wins[l] = (e.value as num).toInt();
      }
    }
    final daily = <String, Duration>{};
    final dailyRaw = raw['daily'];
    if (dailyRaw is Map) {
      for (final e in dailyRaw.entries) {
        if (e.value is num) daily['${e.key}'] = Duration(milliseconds: (e.value as num).toInt());
      }
    }
    return MinesweeperRecords(best: best, medals: medals, noFlags: noFlags, wins: wins, daily: daily);
  }

  /// Apunta una victoria. [day] solo si era el tablero del dia.
  (MinesweeperRecords, WinReport) recordWin({
    required MinesweeperLevel level,
    required Duration time,
    required bool usedFlags,
    DateTime? day,
  }) {
    if (day != null) {
      final key = dayKey(day);
      final previous = daily[key];
      final next = Map<String, Duration>.from(daily);
      if (previous == null || time < previous) next[key] = time;
      final keys = next.keys.toList()..sort();
      while (keys.length > _dailyKept) {
        next.remove(keys.removeAt(0));
      }
      return (
        MinesweeperRecords(best: best, medals: medals, noFlags: noFlags, wins: wins, daily: next),
        WinReport(
          time: time,
          best: previous == null || time < previous ? time : previous,
          newRecord: previous == null || time < previous,
          medal: null,
          newMedal: false,
          noFlags: !usedFlags,
          newStamp: false,
        ),
      );
    }

    final previous = best[level];
    final newRecord = previous == null || time < previous;
    final medal = medalFor(level, time);
    final oldMedal = medals[level];
    final newMedal = medal != null && (oldMedal == null || medal.index > oldMedal.index);
    final stamp = !usedFlags;
    final newStamp = stamp && !noFlags.contains(level);
    return (
      MinesweeperRecords(
        best: {...best, if (newRecord) level: time},
        medals: {...medals, if (newMedal) level: medal},
        noFlags: {...noFlags, if (stamp) level},
        wins: {...wins, level: (wins[level] ?? 0) + 1},
        daily: daily,
      ),
      WinReport(
        time: time,
        best: newRecord ? time : previous,
        newRecord: newRecord && previous != null,
        medal: medal,
        newMedal: newMedal,
        noFlags: stamp,
        newStamp: newStamp,
      ),
    );
  }
}

/// Lo que se enseña en la pantalla de resultados.
@immutable
class WinReport {
  const WinReport({
    required this.time,
    required this.best,
    required this.newRecord,
    required this.medal,
    required this.newMedal,
    required this.noFlags,
    required this.newStamp,
  });

  final Duration time;
  final Duration best;

  /// Mejora un tiempo que ya habia (la primera victoria no cuenta como
  /// récord: no habia nada que batir).
  final bool newRecord;
  final Medal? medal;
  final bool newMedal;

  /// Ganada sin poner banderas.
  final bool noFlags;
  final bool newStamp;
}

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

  Future<MinesweeperRecords> load() async {
    try {
      if (_file.path.isEmpty || !await _file.exists()) return const MinesweeperRecords();
      return MinesweeperRecords.fromJson(jsonDecode(await _file.readAsString()));
    } catch (e) {
      debugPrint('Ibasho: récords del buscaminas ilegibles ($e)');
      return const MinesweeperRecords();
    }
  }

  Future<void> save(MinesweeperRecords records) async {
    if (_file.path.isEmpty) return;
    try {
      await _file.writeAsString(jsonEncode(records.toJson()), flush: true);
    } catch (e) {
      debugPrint('Ibasho: no se han podido guardar los récords ($e)');
    }
  }
}
