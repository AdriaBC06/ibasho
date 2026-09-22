// Ibasho — los premios de los juegos: monedas por ganar, con tope diario.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import 'session.dart';

/// Monedas que se pueden cobrar en un dia (UTC) entre todos los juegos. Las
/// reglas exigen lo mismo.
const int dailyRewardCap = 20;

/// Tiempo minimo entre dos cobros. Las reglas exigen lo mismo.
const Duration rewardCooldown = Duration(seconds: 15);

const int _dayMs = 86400000;

/// Lo cobrado hoy, tal y como esta en `/users/{cuenta}/rewards`.
@immutable
class RewardsState {
  const RewardsState({this.day = 0, this.earned = 0, this.at});

  /// Dia UTC del ultimo cobro: `floor(ms / 86400000)`.
  final int day;
  final int earned;
  final DateTime? at;

  static int today([DateTime? now]) =>
      (now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ _dayMs;

  /// Lo cobrado hoy: si el ultimo cobro fue otro dia, cero.
  int earnedToday([DateTime? now]) => day == today(now) ? earned : 0;

  int leftToday([DateTime? now]) => math.max(0, dailyRewardCap - earnedToday(now));
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
      final raw = await _backend.read('/users/$_me/rewards', idToken: await _session.freshToken());
      if (mounted) state = _parse(raw);
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los premios ($e)');
    }
  }

  static RewardsState _parse(Object? raw) {
    if (raw is! Map) return const RewardsState();
    final day = raw['day'];
    final earned = raw['earned'];
    final at = raw['at'];
    return RewardsState(
      day: day is num ? day.toInt() : 0,
      earned: earned is num ? earned.toInt() : 0,
      at: at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt()) : null,
    );
  }

  /// Cobra el premio de una victoria en [game]. Si con [amount] se pasaria
  /// del tope, cobra lo que falte hasta el tope; si ya esta, nada.
  Future<RewardOutcome> claim({required String game, required int amount}) async {
    final now = DateTime.now();
    final left = state.leftToday(now);
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
    final earned = state.earnedToday() + coins;
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/rewards': {
            'game': game,
            'day': day,
            'earned': earned,
            'at': serverTimestamp,
          },
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
    if (mounted) state = RewardsState(day: day, earned: earned, at: DateTime.now());
    return RewardOutcome(RewardStatus.granted, coins);
  }
}
