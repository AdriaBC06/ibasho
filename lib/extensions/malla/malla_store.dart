// Malla — preferencias, sesión y estadísticas locales.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import '../../games/game_store.dart';
import 'malla_ai.dart';
import 'malla_online.dart';

class MallaStats {
  MallaStats({
    this.games = 0,
    this.wins = 0,
    this.draws = 0,
    this.onlineWins = 0,
    this.cpuWins = 0,
    this.secondWins = 0,
    this.closeWins = 0,
    this.maxMargin = 0,
    this.perfectWins = 0,
    this.fiveWins = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.hexes = 0,
    this.fullTableGames = 0,
    this.multi4Wins = 0,
    this.lastTouchCaptures = 0,
    this.majorityWins = 0,
    Set<String>? unlocked,
    List<String>? recorded,
  }) : unlocked = unlocked ?? <String>{},
       recorded = recorded ?? <String>[];

  int games;
  int wins;
  int draws;
  int onlineWins;
  int cpuWins;
  int secondWins;
  int closeWins;
  int maxMargin;
  int perfectWins;
  int fiveWins;
  int streak;
  int bestStreak;
  int hexes;
  int fullTableGames;
  int multi4Wins;
  int lastTouchCaptures;
  int majorityWins;
  final Set<String> unlocked;
  final List<String> recorded;

  static MallaStats fromJson(Object? raw) {
    if (raw is! Map) return MallaStats();
    final m = Map<String, Object?>.from(raw);
    int i(String key) => m[key] is num ? (m[key] as num).toInt() : 0;
    return MallaStats(
      games: i('games'),
      wins: i('wins'),
      draws: i('draws'),
      onlineWins: i('onlineWins'),
      cpuWins: i('cpuWins'),
      secondWins: i('secondWins'),
      closeWins: i('closeWins'),
      maxMargin: i('maxMargin'),
      perfectWins: i('perfectWins'),
      fiveWins: i('fiveWins'),
      streak: i('streak'),
      bestStreak: i('bestStreak'),
      hexes: i('hexes'),
      fullTableGames: i('fullTableGames'),
      multi4Wins: i('multi4Wins'),
      lastTouchCaptures: i('lastTouchCaptures'),
      majorityWins: i('majorityWins'),
      unlocked: m['unlocked'] is List
          ? <String>{for (final v in m['unlocked'] as List) v.toString()}
          : <String>{},
      recorded: m['recorded'] is List
          ? <String>[for (final v in m['recorded'] as List) v.toString()]
          : <String>[],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'games': games,
    'wins': wins,
    'draws': draws,
    'onlineWins': onlineWins,
    'cpuWins': cpuWins,
    'secondWins': secondWins,
    'closeWins': closeWins,
    'maxMargin': maxMargin,
    'perfectWins': perfectWins,
    'fiveWins': fiveWins,
    'streak': streak,
    'bestStreak': bestStreak,
    'hexes': hexes,
    'fullTableGames': fullTableGames,
    'multi4Wins': multi4Wins,
    'lastTouchCaptures': lastTouchCaptures,
    'majorityWins': majorityWins,
    'unlocked': unlocked.toList()..sort(),
    'recorded': recorded,
  };
}

class MallaSaveData {
  MallaSaveData({
    this.marker = 'A',
    this.color = '#397d79',
    this.onlineChain = false,
    this.cpuChain = false,
    this.cpuOpponents = 1,
    this.cpuSize = 3,
    this.cpuDifficulty = MallaDifficulty.normal,
    this.cpuStarter = 'random',
    this.soundEnabled = true,
    this.guardBest = 0,
    MallaStats? stats,
    this.session,
  }) : stats = stats ?? MallaStats();

  String marker;
  String color;
  bool onlineChain;
  bool cpuChain;
  int cpuOpponents;
  int cpuSize;
  MallaDifficulty cpuDifficulty;
  String cpuStarter;
  bool soundEnabled;
  int guardBest;
  MallaStats stats;
  MallaSession? session;

  static MallaSaveData fromJson(Map<String, Object?> raw) {
    final difficulty = switch (raw['cpuDifficulty']?.toString()) {
      'easy' => MallaDifficulty.easy,
      'hard' => MallaDifficulty.hard,
      _ => MallaDifficulty.normal,
    };
    final starter = switch (raw['cpuStarter']?.toString()) {
      'human' => 'human',
      'cpu' => 'cpu',
      _ => 'random',
    };
    final marker = raw['marker']?.toString().trim();
    final color = raw['color']?.toString().toLowerCase();
    return MallaSaveData(
      marker: marker == null || marker.isEmpty ? 'A' : marker,
      color: color != null && RegExp(r'^#[0-9a-f]{6}$').hasMatch(color)
          ? color
          : '#397d79',
      onlineChain: raw['onlineChain'] == true,
      cpuChain: raw['cpuChain'] == true,
      cpuOpponents: _clampInt(raw['cpuOpponents'], 1, 5, 1),
      cpuSize: _clampInt(raw['cpuSize'], 3, 7, 3),
      cpuDifficulty: difficulty,
      cpuStarter: starter,
      soundEnabled: raw['soundEnabled'] != false,
      guardBest: _clampInt(raw['guardBest'], 0, 1 << 30, 0),
      stats: MallaStats.fromJson(raw['stats']),
      session: MallaSession.fromJson(raw['session']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'format': 2,
    'marker': marker,
    'color': color,
    'onlineChain': onlineChain,
    'cpuChain': cpuChain,
    'cpuOpponents': cpuOpponents,
    'cpuSize': cpuSize,
    'cpuDifficulty': cpuDifficulty.name,
    'cpuStarter': cpuStarter,
    'soundEnabled': soundEnabled,
    'guardBest': guardBest,
    'stats': stats.toJson(),
    if (session != null) 'session': session!.toJson(),
  };
}

class MallaStore {
  MallaStore._(this._store);

  final GameStore _store;

  static Future<MallaStore> open() async =>
      MallaStore._(await GameStore.open('malla'));

  Future<MallaSaveData> load() async =>
      MallaSaveData.fromJson(await _store.load());

  Future<void> save(MallaSaveData data) => _store.save(data.toJson());
}

int _clampInt(Object? raw, int min, int max, int fallback) {
  if (raw is! num) return fallback;
  return raw.toInt().clamp(min, max).toInt();
}
