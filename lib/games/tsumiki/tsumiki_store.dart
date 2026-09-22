// Ibasho — los récords de Tsumiki: mejor puntuacion, filas y sellos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../game_store.dart';

@immutable
class TsumikiRecords {
  const TsumikiRecords({
    this.bestScore = 0,
    this.bestLines = 0,
    this.bestLevel = 0,
    this.games = 0,
    this.totalLines = 0,
    this.tsumikis = 0,
  });

  final int bestScore;
  final int bestLines;
  final int bestLevel;
  final int games;
  final int totalLines;

  /// Veces que se han borrado cuatro filas de golpe, en total.
  final int tsumikis;

  static TsumikiRecords fromJson(Map<String, Object?> j) => TsumikiRecords(
        bestScore: readInt(j['bestScore']),
        bestLines: readInt(j['bestLines']),
        bestLevel: readInt(j['bestLevel']),
        games: readInt(j['games']),
        totalLines: readInt(j['totalLines']),
        tsumikis: readInt(j['tsumikis']),
      );

  Map<String, Object?> toJson() => {
        'bestScore': bestScore,
        'bestLines': bestLines,
        'bestLevel': bestLevel,
        'games': games,
        'totalLines': totalLines,
        'tsumikis': tsumikis,
      };

  (TsumikiRecords, TsumikiReport) record({
    required int score,
    required int lines,
    required int level,
    required int tsumikis,
    required int maxCombo,
  }) {
    final next = TsumikiRecords(
      bestScore: math.max(bestScore, score),
      bestLines: math.max(bestLines, lines),
      bestLevel: math.max(bestLevel, level),
      games: games + 1,
      totalLines: totalLines + lines,
      tsumikis: this.tsumikis + tsumikis,
    );
    return (
      next,
      TsumikiReport(
        score: score,
        lines: lines,
        level: level,
        tsumikis: tsumikis,
        maxCombo: maxCombo,
        best: next.bestScore,
        // La primera partida no bate nada: no habia récord.
        newRecord: games > 0 && score > bestScore,
        newLines: games > 0 && lines > bestLines,
      ),
    );
  }
}

@immutable
class TsumikiReport {
  const TsumikiReport({
    required this.score,
    required this.lines,
    required this.level,
    required this.tsumikis,
    required this.maxCombo,
    required this.best,
    required this.newRecord,
    required this.newLines,
  });

  final int score;
  final int lines;
  final int level;
  final int tsumikis;
  final int maxCombo;
  final int best;
  final bool newRecord;
  final bool newLines;
}
