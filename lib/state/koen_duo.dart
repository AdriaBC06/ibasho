// Ibasho — Tama Kōen: los dúos, su racha y su casita.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/gacha.dart' show TicketKind;
import '../backend/ibasho_backend.dart';
import '../backend/koen_duo.dart';
import '../backend/models.dart' show serverTimestamp;
import 'login_bonus.dart' show bonusDay;
import 'session.dart';

@immutable
class KoenDuosState {
  const KoenDuosState({
    this.data = const <String, KoenDuoData>{},
    this.claimed = const <String, Set<int>>{},
    this.demoMine,
    this.demoFriend,
    this.demoWorn = false,
  });

  /// Lo leído de `/koen/{a_b}`, por amigo.
  final Map<String, KoenDuoData> data;

  /// Los premios de racha ya cobrados (`users/{me}/koen/duos/{a_b}/{días}`),
  /// por dúo.
  final Map<String, Set<int>> claimed;

  /// El dúo del parque de prueba: un Tama propio que haría de pareja de
  /// «Mochi» con un amigo inventado. No escribe nada.
  final String? demoMine;
  final String? demoFriend;

  /// Si en el dúo de prueba ya llevan el accesorio de pareja (solo se ve en
  /// la casita: no toca los Tamas).
  final bool demoWorn;

  KoenDuosState copyWith({
    Map<String, KoenDuoData>? data,
    Map<String, Set<int>>? claimed,
    String? demoMine,
    String? demoFriend,
    bool? demoWorn,
  }) => KoenDuosState(
    data: data ?? this.data,
    claimed: claimed ?? this.claimed,
    demoMine: demoMine ?? this.demoMine,
    demoFriend: demoFriend ?? this.demoFriend,
    demoWorn: demoWorn ?? this.demoWorn,
  );
}

/// Lo que ha pasado al apuntar el día de un dúo.
@immutable
class KoenDuoTick {
  const KoenDuoTick({this.streak = 0, this.prizes = const <KoenStreakPrize>[]});

  /// La racha nueva, o 0 si no se ha apuntado nada.
  final int streak;

  /// Los premios cobrados.
  final List<KoenStreakPrize> prizes;

  bool get isEmpty => streak == 0 && prizes.isEmpty;
}

/// Los dúos de la cuenta. Nada escucha en vivo: `/koen/{a_b}` se lee al abrir
/// el parque y la casita, y al apuntar la racha.
class KoenDuosController extends StateNotifier<KoenDuosState> {
  KoenDuosController({
    required IbashoBackend backend,
    required SessionController session,
    required int Function() coinsOf,
    required int Function(TicketKind kind) ticketsOf,
    bool Function(String key)? owns,
  }) : _backend = backend,
       _session = session,
       _coinsOf = coinsOf,
       _ticketsOf = ticketsOf,
       _owns = owns ?? _ownsNothing,
       super(const KoenDuosState());

  static bool _ownsNothing(String _) => false;

  final IbashoBackend _backend;
  final SessionController _session;
  final int Function() _coinsOf;
  final int Function(TicketKind kind) _ticketsOf;
  final bool Function(String key) _owns;

  String get _me => _session.state.accountId;

  /// Lee lo que comparten los [duos] y los premios ya cobrados.
  Future<void> load(List<KoenDuo> duos) async {
    final real = [for (final d in duos) if (!d.demo) d];
    if (_me.isEmpty || real.isEmpty) return;
    try {
      final token = await _session.freshToken();
      final reads = await Future.wait([
        _backend.read('/users/$_me/koen/duos', idToken: token).then<Object?>((v) => v, onError: (Object _) => null),
        for (final d in real)
          _backend.read('/koen/${d.key}', idToken: token).then<Object?>((v) => v, onError: (Object _) => null),
      ]);
      if (!mounted) return;
      final data = {...state.data};
      for (var i = 0; i < real.length; i++) {
        data[real[i].friend] = KoenDuoData.fromJson(reads[i + 1]);
      }
      state = state.copyWith(data: data, claimed: {...state.claimed, ...claimedFrom(reads.first)});
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer los dúos ($e)');
    }
  }

  static Map<String, Set<int>> claimedFrom(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is Map)
          '${e.key}': {
            for (final d in (e.value as Map).keys) ?int.tryParse('$d'),
          },
  };

  /// Escribe [patch] (rutas relativas a `/koen/{a_b}`) y, si el dúo aún no
  /// existe, `a` y `b` con él. Si otro lo ha creado a la vez, vuelve a
  /// probar sin ellos.
  Future<bool> _write(KoenDuo duo, Map<String, Object?> patch) async {
    final base = 'koen/${duo.key}';
    final b = duo.a == _me ? duo.friend : _me;
    for (final create in [!(state.data[duo.friend] ?? duo.data).exists, false]) {
      try {
        await _backend.merge('/', {
          if (create) ...{'$base/a': duo.a, '$base/b': b},
          for (final e in patch.entries) '$base/${e.key}': e.value,
        }, idToken: await _session.freshToken());
        if (mounted) _put(duo, (state.data[duo.friend] ?? duo.data).copyWith(exists: true));
        return true;
      } catch (e) {
        if (!create) {
          debugPrint('Ibasho: no se ha podido guardar el dúo ($e)');
          return false;
        }
      }
    }
    return false;
  }

  void _put(KoenDuo duo, KoenDuoData data) => state = state.copyWith(data: {...state.data, duo.friend: data});

  /// Los Tamas de la casita, cada uno en su lado.
  Future<bool> setPair(KoenDuo duo, String left, String right) async {
    final data = (state.data[duo.friend] ?? duo.data).copyWith(left: left, right: right);
    if (duo.demo) {
      _put(duo, data);
      return true;
    }
    final ok = await _write(duo, {'slots': {'left': left, 'right': right}});
    if (ok && mounted) _put(duo, data.copyWith(exists: true));
    return ok;
  }

  /// Pone [furniture] en el hueco [spot] (o lo vacía con `null`). Si ese
  /// mueble estaba en otro hueco, se mueve.
  Future<bool> place(KoenDuo duo, int spot, KoenFurniture? furniture) async {
    final current = state.data[duo.friend] ?? duo.data;
    final decor = {...current.decor};
    final patch = <String, Object?>{};
    if (furniture != null) {
      for (final e in current.decor.entries) {
        if (e.value == furniture && e.key != spot) {
          decor.remove(e.key);
          patch['house/decor/${e.key}'] = null;
        }
      }
      decor[spot] = furniture;
    } else {
      decor.remove(spot);
    }
    patch['house/decor/$spot'] = furniture?.name;
    if (duo.demo) {
      _put(duo, current.copyWith(decor: decor));
      return true;
    }
    final ok = await _write(duo, patch);
    if (ok && mounted) _put(duo, (state.data[duo.friend] ?? current).copyWith(decor: decor, exists: true));
    return ok;
  }

  /// La forma del accesorio de pareja. La puede elegir (y cambiar)
  /// cualquiera de los dos; el color sale de la pareja.
  Future<bool> chooseCharm(KoenDuo duo, KoenCharm shape) async {
    final charm = KoenCharmChoice(shape, duo.charmCode);
    final data = (state.data[duo.friend] ?? duo.data).copyWith(charm: charm);
    if (duo.demo) {
      _put(duo, data);
      return true;
    }
    final ok = await _write(duo, {'charm': charm.toJson()});
    if (ok && mounted) _put(duo, (state.data[duo.friend] ?? data).copyWith(charm: charm, exists: true));
    return ok;
  }

  /// La mitad del accesorio de pareja que le toca al Tama propio de la
  /// casita, en la colección: si aún no la tiene, la cobra con su recibo
  /// (`koen/charm`), que las reglas cruzan con la forma elegida, el lado de
  /// la casita y la amistad. Devuelve la clave, o `null` si no ha podido.
  ///
  /// Antes vuelve a escribir los lados de la casita, por si aún no estaban
  /// guardados: de ellos sale qué mitad le toca a cada uno.
  Future<String?> claimCharm(KoenDuo duo) async {
    final charm = (state.data[duo.friend] ?? duo.data).charm;
    if (charm == null) return null;
    final (_, left) = duo.myHalf;
    final key = charm.keyFor(left: left);
    if (duo.demo || _owns(key)) return key;
    final (l, r) = duo.pair;
    try {
      await _backend.merge('/', {
        'koen/${duo.key}/slots': {'left': l.id, 'right': r.id},
        'users/$_me/koen/charm': {'key': key, 'pair': duo.key, 'at': serverTimestamp},
        'users/$_me/prizes/$key': 1,
      }, idToken: await _session.freshToken());
      return key;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cobrar el accesorio de pareja ($e)');
      return null;
    }
  }

  /// En el dúo de prueba, se lo ponen o se lo quitan los dos (sin escribir).
  void demoWear(bool worn) => state = state.copyWith(demoWorn: worn);

  /// Apunta el día de hoy en la racha si los dos Tamas de la casita ya han
  /// comido y les han hecho un mimo, y cobra los premios que falten.
  Future<KoenDuoTick> tick(KoenDuo duo) async {
    final today = bonusDay();
    // Sin leer lo que hay, la racha y los premios saldrían de cero.
    if (!duo.demo && !state.data.containsKey(duo.friend)) {
      await load([duo]);
      if (!mounted || !state.data.containsKey(duo.friend)) return const KoenDuoTick();
    }
    var data = state.data[duo.friend] ?? duo.data;
    var counted = 0;
    if (duo.caredOn(today) && !data.streak.countedOn(today)) {
      final next = data.streak.advance(today);
      final (left, right) = duo.pair;
      final ok = duo.demo ||
          await _write(duo, {
            'slots': {'left': left.id, 'right': right.id},
            'streak': next.toJson(),
          });
      if (!mounted) return const KoenDuoTick();
      if (ok) {
        data = data.copyWith(streak: next, left: left.id, right: right.id, exists: !duo.demo || data.exists);
        _put(duo, data);
        counted = next.count;
      }
    }
    final prizes = await _claim(duo, data.streak.best);
    return KoenDuoTick(streak: counted, prizes: prizes);
  }

  /// Los premios de racha hasta [best] que aún no se han cobrado. Cada cobro
  /// lleva su recibo (`koen/duo`) y su sello (`koen/duos/{a_b}/{días}`).
  Future<List<KoenStreakPrize>> _claim(KoenDuo duo, int best) async {
    final out = <KoenStreakPrize>[];
    for (final prize in koenStreakPrizes) {
      if (prize.days > best || (state.claimed[duo.key]?.contains(prize.days) ?? false)) continue;
      if (!duo.demo) {
        try {
          await _backend.merge('/', {
            'users/$_me/koen/duo': {'pair': duo.key, 'days': prize.days, 'at': serverTimestamp},
            'users/$_me/koen/duos/${duo.key}/${prize.days}': true,
            if (prize.coins > 0) 'users/$_me/coins': _coinsOf() + prize.coins,
            if (prize.ticket) 'users/$_me/tickets/${TicketKind.gachaken.name}': _ticketsOf(TicketKind.gachaken) + 1,
          }, idToken: await _session.freshToken());
        } catch (e) {
          debugPrint('Ibasho: no se ha podido cobrar el premio de la racha ($e)');
          break;
        }
      }
      if (!mounted) break;
      state = state.copyWith(claimed: {
        ...state.claimed,
        duo.key: {...?state.claimed[duo.key], prize.days},
      });
      out.add(prize);
    }
    return out;
  }

  /// El dúo de prueba: [mine] (un Tama propio) con el Tama de prueba que
  /// cuida la cuenta, de [friend]. Lleva 6 días de racha hasta ayer, así que
  /// al cuidar hoy a los dos llega a la semana y se ven los premios.
  void debugDemo({required String mine, required String friend}) {
    final yesterday = bonusDay() - 1;
    state = KoenDuosState(
      data: {
        ...state.data,
        friend: KoenDuoData(
          streak: KoenStreak(count: 6, day: yesterday, best: 6),
          decor: const {0: KoenFurniture.zabuton},
        ),
      },
      claimed: {...state.claimed, koenDuoKey(_me, friend): {3}},
      demoMine: mine,
      demoFriend: friend,
    );
  }
}
