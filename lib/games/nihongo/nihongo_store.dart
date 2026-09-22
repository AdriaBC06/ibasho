// Ibasho — lo que recuerda Nihongo: cuanto sabes de cada kana y tus rondas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../game_store.dart';
import 'kana.dart';

@immutable
class NihongoRecords {
  const NihongoRecords({
    this.stats = const <String, KanaStat>{},
    this.best = const <String, int>{},
    this.perfects = const <String, int>{},
    this.rounds = 0,
    this.groups = const {KanaGroup.basic},
    this.mode = AnswerMode.choices,
  });

  /// Por kana (el caracter es la clave: hiragana y katakana no chocan).
  final Map<String, KanaStat> stats;

  /// Mejor ronda por `escritura.modo`.
  final Map<String, int> best;

  /// Plenos por escritura.
  final Map<String, int> perfects;
  final int rounds;

  /// Lo ultimo elegido, para no tener que volver a marcarlo.
  final Set<KanaGroup> groups;
  final AnswerMode mode;

  static String key(KanaScript s, AnswerMode m) => '${s.name}.${m.name}';

  int mastered(KanaScript s) => kanaTable[s]!.where((k) => stats[k.char]?.mastered ?? false).length;

  static NihongoRecords fromJson(Map<String, Object?> j) {
    Map<String, int> ints(Object? raw) =>
        raw is Map ? {for (final e in raw.entries) '${e.key}': readInt(e.value)} : const <String, int>{};
    final rawStats = j['stats'];
    final groups = j['groups'];
    return NihongoRecords(
      stats: rawStats is Map
          ? {
              for (final e in rawStats.entries)
                if (e.value is List && (e.value as List).length == 3)
                  '${e.key}': KanaStat(
                    seen: readInt((e.value as List)[0]),
                    right: readInt((e.value as List)[1]),
                    streak: readInt((e.value as List)[2]),
                  ),
            }
          : const <String, KanaStat>{},
      best: ints(j['best']),
      perfects: ints(j['perfects']),
      rounds: readInt(j['rounds']),
      groups: groups is List
          ? {for (final g in KanaGroup.values) if (groups.contains(g.name)) g}
          : const {KanaGroup.basic},
      mode: j['mode'] == AnswerMode.write.name ? AnswerMode.write : AnswerMode.choices,
    );
  }

  Map<String, Object?> toJson() => {
        'stats': {for (final e in stats.entries) e.key: [e.value.seen, e.value.right, e.value.streak]},
        'best': best,
        'perfects': perfects,
        'rounds': rounds,
        'groups': [for (final g in groups) g.name],
        'mode': mode.name,
      };

  NihongoRecords copyWith({Set<KanaGroup>? groups, AnswerMode? mode}) => NihongoRecords(
        stats: stats,
        best: best,
        perfects: perfects,
        rounds: rounds,
        groups: groups ?? this.groups,
        mode: mode ?? this.mode,
      );

  NihongoRecords answered(Kana k, bool ok) => NihongoRecords(
        stats: {...stats, k.char: (stats[k.char] ?? const KanaStat()).answered(ok)},
        best: best,
        perfects: perfects,
        rounds: rounds,
        groups: groups,
        mode: mode,
      );

  /// Al acabar una ronda. Devuelve tambien si mejora la mejor.
  (NihongoRecords, bool) finished(KanaRound round) {
    if (round.review) return (this, false);
    final k = key(round.script, round.mode);
    final before = best[k];
    return (
      NihongoRecords(
        stats: stats,
        best: {...best, k: math.max(before ?? 0, round.right)},
        perfects: {
          ...perfects,
          if (round.perfect) round.script.name: (perfects[round.script.name] ?? 0) + 1,
        },
        rounds: rounds + 1,
        groups: groups,
        mode: mode,
      ),
      before != null && round.right > before,
    );
  }
}
