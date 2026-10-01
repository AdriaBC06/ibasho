// Ibasho — los récords de Hebi: mejor longitud, partidas y comidas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../game_store.dart';

@immutable
class HebiRecords {
  const HebiRecords({
    this.bestLength = 0,
    this.bestSpeed = 0,
    this.games = 0,
    this.totalEaten = 0,
  });

  final int bestLength;
  final int bestSpeed;
  final int games;
  final int totalEaten;

  static HebiRecords fromJson(Map<String, Object?> j) => HebiRecords(
        bestLength: readInt(j['bestLength']),
        bestSpeed: readInt(j['bestSpeed']),
        games: readInt(j['games']),
        totalEaten: readInt(j['totalEaten']),
      );

  Map<String, Object?> toJson() => {
        'bestLength': bestLength,
        'bestSpeed': bestSpeed,
        'games': games,
        'totalEaten': totalEaten,
      };

  (HebiRecords, HebiReport) record({
    required int length,
    required int eaten,
    required int speed,
    required double seconds,
    required bool won,
  }) {
    final next = HebiRecords(
      bestLength: math.max(bestLength, length),
      bestSpeed: math.max(bestSpeed, speed),
      games: games + 1,
      totalEaten: totalEaten + eaten,
    );
    return (
      next,
      HebiReport(
        length: length,
        eaten: eaten,
        speed: speed,
        seconds: seconds,
        best: next.bestLength,
        won: won,
        // La primera partida no bate nada: no habia récord.
        newRecord: games > 0 && length > bestLength,
      ),
    );
  }
}

@immutable
class HebiReport {
  const HebiReport({
    required this.length,
    required this.eaten,
    required this.speed,
    required this.seconds,
    required this.best,
    required this.won,
    required this.newRecord,
  });

  final int length;
  final int eaten;
  final int speed;
  final double seconds;
  final int best;
  final bool won;
  final bool newRecord;
}
