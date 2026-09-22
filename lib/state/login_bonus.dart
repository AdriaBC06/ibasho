// Ibasho — el bono diario: unas monedas por entrar, una vez al dia.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import 'session.dart';

/// Si el bono se abre solo al entrar. Los tests lo apagan en
/// `test/flutter_test_config.dart`: si no, taparia cada recorrido.
bool loginBonusAutoOpen = true;

const int _dayMs = 86400000;

/// El dia UTC de [at]: `floor(ms / 86400000)`, como en las reglas.
int bonusDay([DateTime? at]) => (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ _dayMs;

/// El dia UTC [day] como fecha, a medianoche UTC.
DateTime bonusDate(int day) => DateTime.fromMillisecondsSinceEpoch(day * _dayMs, isUtc: true);

/// Lo que da el bono el dia [day]: el mismo para todo el mundo.
///
/// Viernes 10, sabado y domingo 15, y de lunes a jueves entre 3 y 7, segun
/// una cuenta fija del numero de dia que parece al azar: el hash
/// multiplicativo de Knuth, que reparte los cinco valores por igual y no
/// repite dos dias seguidos. Las reglas hacen la misma cuenta (`login/last`
/// en `database.rules.json`, que no tienen `floor` y dividen restando el
/// resto), asi que si cambia aqui tiene que cambiar alli.
int loginBonusFor(int day) {
  // El dia 0 (1-1-1970) fue jueves: con +3, el lunes da 0.
  final weekday = (day + 3) % 7;
  if (weekday == 4) return 10;
  if (weekday >= 5) return 15;
  const m = 4294967296;
  final x = day * 2654435761 % m;
  return 3 + x * 5 ~/ m;
}

@immutable
class LoginBonusState {
  const LoginBonusState({this.lastDay, this.days = const <int>{}, this.loaded = false});

  /// El ultimo dia cobrado.
  final int? lastDay;

  /// Los dias cobrados, para el calendario.
  final Set<int> days;

  final bool loaded;

  bool claimedOn(int day) => days.contains(day) || lastDay == day;

  bool get claimedToday => claimedOn(bonusDay());
}

class LoginBonusController extends StateNotifier<LoginBonusState> {
  LoginBonusController({
    required IbashoBackend backend,
    required SessionController session,
    required int Function() coinsOf,
  })  : _backend = backend,
        _session = session,
        _coinsOf = coinsOf,
        super(const LoginBonusState()) {
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
      final raw = await _backend.read('/users/$_me/login', idToken: await _session.freshToken());
      if (mounted) state = _parse(raw);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el bono diario ($e)');
      // Sin saber si ya se cobro, no se ofrece: mejor que un cobro rechazado.
    }
  }

  static LoginBonusState _parse(Object? raw) {
    if (raw is! Map) return const LoginBonusState(loaded: true);
    final last = raw['last'];
    final day = last is Map ? last['day'] : null;
    final days = raw['days'];
    return LoginBonusState(
      lastDay: day is num ? day.toInt() : null,
      days: {
        if (days is Map)
          for (final k in days.keys) ?int.tryParse('$k'),
      },
      loaded: true,
    );
  }

  /// Cobra el bono de hoy. Devuelve las monedas, o `null` si no se ha podido
  /// (ya cobrado, sin conexion o rechazado).
  Future<int?> claim() async {
    final day = bonusDay();
    if (!state.loaded || state.claimedOn(day)) return null;
    final amount = loginBonusFor(day);
    try {
      await _backend.merge(
        '/',
        {
          'users/$_me/login/last': {'day': day, 'at': serverTimestamp},
          'users/$_me/login/days/$day': true,
          'users/$_me/coins': _coinsOf() + amount,
        },
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar el bono diario ($e)');
      unawaited(_load());
      return null;
    }
    if (mounted) state = LoginBonusState(lastDay: day, days: {...state.days, day}, loaded: true);
    return amount;
  }

  /// Solo admin, en su propia cuenta: borra el bono para volver a probarlo.
  Future<bool> debugReset() async {
    try {
      await _backend.remove('/users/$_me/login', idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido borrar el bono diario ($e)');
      return false;
    }
    if (mounted) state = const LoginBonusState(loaded: true);
    return true;
  }
}
