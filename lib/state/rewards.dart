// Ibasho — los premios de los juegos: monedas por ganar, con tope diario por
// juego.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import 'session.dart';

/// Monedas que se pueden cobrar en un dia (UTC) en cada juego. Las reglas
/// exigen lo mismo.
const int dailyRewardCap = 20;

/// Tiempo minimo entre dos cobros, sean del juego que sean. Las reglas exigen
/// lo mismo.
const Duration rewardCooldown = Duration(seconds: 15);

const int _dayMs = 86400000;

/// Lo cobrado en un juego el ultimo dia que se cobro algo en el.
@immutable
class GameEarning {
  const GameEarning({required this.day, required this.earned});

  /// Dia UTC: `floor(ms / 86400000)`.
  final int day;
  final int earned;
}

/// Lo cobrado, tal y como esta en `/users/{cuenta}/earnings`.
@immutable
class RewardsState {
  const RewardsState({this.games = const <String, GameEarning>{}, this.at, this.loaded = false});

  final Map<String, GameEarning> games;

  /// Cuando fue el ultimo cobro, de cualquier juego.
  final DateTime? at;

  final bool loaded;

  static int today([DateTime? now]) =>
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ _dayMs;

  /// Lo cobrado hoy en [game]: si su ultimo cobro fue otro dia, cero.
  int earnedToday(String game, [DateTime? now]) {
    final e = games[game];
    return e != null && e.day == today(now) ? e.earned : 0;
  }

  int leftToday(String game, [DateTime? now]) => math.max(0, dailyRewardCap - earnedToday(game, now));
}

/// Como ha ido un cobro.
enum RewardStatus {
  /// Cobrado: [RewardOutcome.coins] monedas nuevas.
  granted,

  /// Ya se ha llegado al tope de hoy.
  capped,

  /// Sin conexion o rechazado: no se ha cobrado nada.
  failed,
}

@immutable
class RewardOutcome {
  const RewardOutcome(this.status, [this.coins = 0]);

  final RewardStatus status;
  final int coins;
}

class RewardsController extends StateNotifier<RewardsState> {
  RewardsController({
    required IbashoBackend backend,
    required SessionController session,
    required int Function() coinsOf,
  })  : _backend = backend,
        _session = session,
        _coinsOf = coinsOf,
        super(const RewardsState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_load());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final int Function() _coinsOf;

  String get _me => _session.state.accountId;

  Future<void> _load() async {
    try {
      final raw = await _backend.read('/users/$_me/earnings', idToken: await _session.freshToken());
      if (mounted) state = _parse(raw);
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los premios ($e)');
      if (mounted) state = RewardsState(games: state.games, at: state.at, loaded: true);
    }
  }

  static RewardsState _parse(Object? raw) {
    if (raw is! Map) return const RewardsState(loaded: true);
    final games = <String, GameEarning>{};
    for (final entry in raw.entries) {
      final v = entry.value;
      if (entry.key == 'last' || v is! Map) continue;
      final day = v['day'];
      final earned = v['earned'];
      if (day is num && earned is num) {
        games['${entry.key}'] = GameEarning(day: day.toInt(), earned: earned.toInt());
      }
    }
    final last = raw['last'];
    final at = last is Map ? last['at'] : null;
    return RewardsState(
      games: games,
      at: at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt()) : null,
      loaded: true,
    );
  }

  /// Cobra el premio de una victoria en [game]. Si con [amount] se pasaria
  /// del tope de ese juego, cobra lo que falte hasta el tope; si ya esta,
  /// nada.
  Future<RewardOutcome> claim({required String game, required int amount}) async {
    final now = DateTime.now();
    final left = state.leftToday(game, now);
    if (left <= 0) return const RewardOutcome(RewardStatus.capped);
    // Dos victorias seguidas en menos de 15 s: las reglas lo rechazarian.
    // Se espera lo que falte, que es poco, en vez de perder el premio.
    final at = state.at;
    if (at != null) {
      final wait = rewardCooldown - now.difference(at) + const Duration(milliseconds: 400);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!mounted) return const RewardOutcome(RewardStatus.failed);
    }

    final coins = math.min(amount, left);
    final day = RewardsState.today();
    final earned = state.earnedToday(game) + coins;
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/earnings/$game': {'day': day, 'earned': earned, 'at': serverTimestamp},
          'users/$_me/earnings/last': {'game': game, 'at': serverTimestamp},
          'users/$_me/coins': _coinsOf() + coins,
        },
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar el premio ($e)');
      // Si el servidor dice otra cosa (otro dispositivo cobro antes), se
      // relee para que la proxima vez las cuentas cuadren.
      unawaited(_load());
      return const RewardOutcome(RewardStatus.failed);
    }
    if (mounted) {
      state = RewardsState(
        games: {...state.games, game: GameEarning(day: day, earned: earned)},
        at: DateTime.now(),
        loaded: true,
      );
    }
    return RewardOutcome(RewardStatus.granted, coins);
  }
}
