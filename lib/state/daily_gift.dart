// Ibasho — el regalo diario del Yatai: comida, un gachaken y un saquito de
// monedas, una vez al dia.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/gacha.dart';
import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import '../backend/tama.dart';
import 'login_bonus.dart' show bonusDay;
import 'session.dart';

/// Unidades de la comida del regalo.
const int dailyGiftFoodUnits = 2;

/// Gachaken del regalo.
const int dailyGiftTickets = 1;

/// Lo que puede traer el saquito, los dos incluidos. Las reglas exigen lo
/// mismo.
const int dailyGiftCoinsMin = 5;
const int dailyGiftCoinsMax = 10;

/// Lo que traia un regalo abierto.
@immutable
class DailyGift {
  const DailyGift({required this.day, required this.food, required this.coins});

  /// Dia UTC: `floor(ms / 86400000)`, como el bono diario.
  final int day;
  final TamaFood food;
  final int coins;
}

@immutable
class DailyGiftState {
  const DailyGiftState({this.last, this.loaded = false, this.busy = false});

  /// El ultimo regalo abierto, sea del dia que sea.
  final DailyGift? last;

  final bool loaded;

  /// Abriendo uno ahora mismo.
  final bool busy;

  bool claimedOn(int day) => last?.day == day;

  bool get claimedToday => claimedOn(bonusDay());

  /// Se puede abrir: ya se sabe que hoy no se ha abierto y no hay otro en
  /// camino.
  bool get available => loaded && !busy && !claimedToday;
}

class DailyGiftController extends StateNotifier<DailyGiftState> {
  DailyGiftController({
    required IbashoBackend backend,
    required SessionController session,
    required int Function() coinsOf,
    required int Function(TicketKind) ticketsOf,
    required int Function(TamaFood) pantryOf,
    math.Random? random,
  })  : _backend = backend,
        _session = session,
        _coinsOf = coinsOf,
        _ticketsOf = ticketsOf,
        _pantryOf = pantryOf,
        _random = random ?? math.Random(),
        super(const DailyGiftState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_load());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final int Function() _coinsOf;
  final int Function(TicketKind) _ticketsOf;
  final int Function(TamaFood) _pantryOf;
  final math.Random _random;

  String get _me => _session.state.accountId;

  Future<void> _load() async {
    try {
      final raw = await _backend.read('/users/$_me/gift', idToken: await _session.freshToken());
      if (mounted) state = DailyGiftState(last: _parse(raw), loaded: true);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el regalo diario ($e)');
      // Sin saber si ya se abrio, no se ofrece: mejor que un cobro rechazado.
    }
  }

  static DailyGift? _parse(Object? raw) {
    if (raw is! Map) return null;
    final day = raw['day'];
    final coins = raw['coins'];
    final food = TamaFood.values.where((f) => f.name == raw['food']).firstOrNull;
    if (day is! num || coins is! num || food == null) return null;
    return DailyGift(day: day.toInt(), food: food, coins: coins.toInt());
  }

  /// Abre el regalo de hoy. Devuelve lo que traia, o `null` si no se ha
  /// podido (ya abierto, sin conexion o rechazado).
  ///
  /// La comida y el saquito los echa a suertes la app: las reglas no
  /// pueden, solo comprueban que esten dentro de lo permitido.
  Future<DailyGift?> claim() async {
    if (!state.available) return null;
    final day = bonusDay();
    final food = TamaFood.values[_random.nextInt(TamaFood.values.length)];
    final coins = dailyGiftCoinsMin + _random.nextInt(dailyGiftCoinsMax - dailyGiftCoinsMin + 1);
    final gift = DailyGift(day: day, food: food, coins: coins);
    state = DailyGiftState(last: state.last, loaded: true, busy: true);
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/gift': {'day': day, 'at': serverTimestamp, 'food': food.name, 'coins': coins},
          'users/$_me/pantry/${food.name}': math.max(0, _pantryOf(food)) + dailyGiftFoodUnits,
          'users/$_me/tickets/${TicketKind.gachaken.name}':
              math.max(0, _ticketsOf(TicketKind.gachaken)) + dailyGiftTickets,
          'users/$_me/coins': _coinsOf() + coins,
        },
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido abrir el regalo diario ($e)');
      if (mounted) state = DailyGiftState(last: state.last, loaded: true);
      unawaited(_load());
      return null;
    }
    if (mounted) state = DailyGiftState(last: gift, loaded: true);
    return gift;
  }

  /// Solo admin, en su propia cuenta: borra el regalo para volver a probarlo.
  Future<bool> debugReset() async {
    try {
      await _backend.remove('/users/$_me/gift', idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido borrar el regalo diario ($e)');
      return false;
    }
    if (mounted) state = const DailyGiftState(loaded: true);
    return true;
  }
}
