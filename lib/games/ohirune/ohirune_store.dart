// Ibasho — los récords de Ohirune, en local.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import '../game_store.dart';
import 'ohirune.dart';

/// Lo que se recuerda de Ohirune.
@immutable
class OhiruneRecords {
  const OhiruneRecords({
    this.best = const <OhiruneLevel, Duration>{},
    this.wins = const <OhiruneLevel, int>{},
    this.flawless = const <OhiruneLevel>{},
    this.daily = const <int, Duration>{},
  });

  /// Mejor tiempo por nivel.
  final Map<OhiruneLevel, Duration> best;

  /// Siestas completas por nivel.
  final Map<OhiruneLevel, int> wins;

  /// Niveles ganados alguna vez sin perder ninguna vida: el sello.
  final Set<OhiruneLevel> flawless;

  /// Tablero del día ganado (`bonusDay()`) → su tiempo con las vidas
  /// perdidas ya sumadas.
  final Map<int, Duration> daily;

  bool dailyDone(int day) => daily.containsKey(day);

  /// Apunta una victoria. Devuelve los récords nuevos y si es el mejor
  /// tiempo del nivel.
  (OhiruneRecords, bool) recordWin({
    required OhiruneLevel level,
    required Duration time,
    required int livesLost,
    int? day,
  }) {
    final old = best[level];
    final record = old == null || time < old;
    // Solo se guardan los ultimos días: el registro no crece sin fin.
    final days = {
      for (final e in daily.entries)
        if (day == null || e.key > day - 60) e.key: e.value,
      ?day: time + ohiruneLifePenalty * livesLost,
    };
    return (
      OhiruneRecords(
        best: {...best, level: record ? time : old},
        wins: {...wins, level: (wins[level] ?? 0) + 1},
        flawless: {...flawless, if (livesLost == 0) level},
        daily: days,
      ),
      record,
    );
  }

  Map<String, Object?> toJson() => {
    'best': {for (final e in best.entries) e.key.name: e.value.inMilliseconds},
    'wins': {for (final e in wins.entries) e.key.name: e.value},
    'flawless': [for (final l in flawless) l.name],
    'daily': {for (final e in daily.entries) '${e.key}': e.value.inMilliseconds},
  };

  static OhiruneRecords fromJson(Map<String, Object?> json) {
    OhiruneLevel? level(Object? name) => OhiruneLevel.values.where((l) => l.name == name).firstOrNull;
    Map<OhiruneLevel, int> perLevel(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if (level(e.key) != null) level(e.key)!: readInt(e.value),
    };
    final daily = json['daily'];
    final flawless = json['flawless'];
    return OhiruneRecords(
      best: perLevel(json['best']).map((k, v) => MapEntry(k, Duration(milliseconds: v))),
      wins: perLevel(json['wins']),
      flawless: {
        if (flawless is List)
          for (final name in flawless)
            if (level(name) != null) level(name)!,
      },
      daily: {
        if (daily is Map)
          for (final e in daily.entries)
            if (int.tryParse('${e.key}') != null) int.parse('${e.key}'): Duration(milliseconds: readInt(e.value)),
      },
    );
  }
}

/// Abre y guarda `ohirune.json`.
class OhiruneStore {
  OhiruneStore._(this._store);

  final GameStore _store;

  static Future<OhiruneStore> open() async => OhiruneStore._(await GameStore.open('ohirune'));

  Future<OhiruneRecords> load() async => OhiruneRecords.fromJson(await _store.load());

  Future<void> save(OhiruneRecords records) => _store.save(records.toJson());
}
