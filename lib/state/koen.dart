// Ibasho — Tama Kōen: el parque de la cuenta y los de sus amigos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/gacha.dart' show TicketKind;
import '../backend/koen.dart';
import '../backend/koen_bonds.dart';
import '../backend/koen_rewards.dart';
import '../backend/models.dart' show serverTimestamp;
import '../backend/tama.dart';
import 'login_bonus.dart' show bonusDay;
import 'rewards.dart';
import 'session.dart';

@immutable
class KoenState {
  const KoenState({
    this.mine = const <KoenCard>[],
    this.friends = const <String, List<KoenCard>>{},
    this.links = const <String>{},
    this.loaded = false,
    this.loading = false,
    this.failed = false,
    this.album = const <KoenMemory, int>{},
    this.drags = const <String, int>{},
    this.dragsDay = 0,
    this.giftDay = 0,
    this.ticketWeek = 0,
    this.demo = false,
    this.demoEarned = 0,
    this.summary,
    this.bonds = const <String, KoenTally>{},
    this.mates = const <String, KoenTally>{},
    this.theirs = const <String, int>{},
    this.levels = const <String, KoenFriendLevel>{},
    this.rewarded = const <String, Set<int>>{},
    this.demoPrizes = const <String>{},
  });

  /// Los Tamas propios en el parque, por hueco.
  final List<KoenCard> mine;

  /// Los de cada amigo que tiene alguno en el parque.
  final Map<String, List<KoenCard>> friends;

  /// Las parejas de amigos que son amigos entre sí, como `koenPairKey`.
  final Set<String> links;

  final bool loaded;
  final bool loading;

  /// La última lectura no ha salido (sin red).
  final bool failed;

  /// Los recuerdos del álbum y el día en que salieron.
  final Map<KoenMemory, int> album;

  /// Los encuentros forzados de [dragsDay], por pareja.
  final Map<String, int> drags;
  final int dragsDay;

  /// El último día que trajeron una chuche y la última semana, un ticket.
  final int giftDay;
  final int ticketWeek;

  /// El parque de prueba de [KoenController.debugDemo]: no escribe nada y
  /// lleva las monedas en [demoEarned].
  final bool demo;
  final int demoEarned;

  /// Lo que ha pasado desde la última vez, para enseñarlo al entrar.
  final KoenSummary? summary;

  /// La amistad de cada pareja con algún Tama propio, por `koenPairKey`.
  final Map<String, KoenTally> bonds;

  /// Los puntos de amistad que lleva sumados la cuenta con cada amigo
  /// (`koen/friends/{amigo}`), y los que lleva sumados cada amigo con ella.
  final Map<String, KoenTally> mates;
  final Map<String, int> theirs;

  /// El nivel de amistad con cada amigo, tal como se guardó la última vez.
  final Map<String, KoenFriendLevel> levels;

  /// Los premios de nivel ya cobrados con cada amigo.
  final Map<String, Set<int>> rewarded;

  /// Los premios de la amistad que se ha llevado el parque de prueba.
  final Set<String> demoPrizes;

  /// Todo lo que hay en el parque. Un Tama cuidado a medias que hayan traído
  /// los dos sale una sola vez: el de la cuenta, si es uno de ellos.
  List<KoenCard> get all {
    final seen = <String>{};
    return [
      for (final c in [...mine, for (final c in friends.values) ...c])
        if (seen.add(c.tamaId)) c,
    ];
  }

  /// Lo bien que se conocen [a] y [b], de 0 a 1. Con un Tama propio sale de
  /// su amistad; entre dos de amigos, de los días que han coincidido.
  double closeness(KoenCard a, KoenCard b, [int? day]) {
    final bond = bonds[koenPairKey(a.tamaId, b.tamaId)];
    if (bond == null && !has(a.tamaId) && !has(b.tamaId)) return koenCloseness(day ?? bonusDay(), a, b);
    return koenBondCloseness(bond?.p ?? 0, siblings: a.holder == b.holder);
  }

  /// El nivel de amistad (1–5) entre [a] y [b] si alguno es propio.
  int? bondLevel(String a, String b) {
    final bond = bonds[koenPairKey(a, b)];
    return bond == null ? (has(a) || has(b) ? 1 : null) : koenBondLevel(bond.p);
  }

  /// El nivel de amistad con [friend]: los puntos de los dos sumados.
  KoenFriendLevel friendLevel(String friend) =>
      KoenFriendLevel.of((mates[friend]?.p ?? 0) + (theirs[friend] ?? 0));

  /// Los encuentros forzados hoy entre [pairKey].
  int dragsToday(String pairKey, [int? day]) => dragsDay == (day ?? bonusDay()) ? drags[pairKey] ?? 0 : 0;

  KoenCard? slot(int i) => mine.where((c) => c.slot == i).firstOrNull;

  bool has(String tamaId) => mine.any((c) => c.tamaId == tamaId);

  /// Si los Tamas de [a] y [b] pueden encontrarse: la misma cuenta, o amigas.
  /// [me] es amigo de todos los de [friends].
  bool areFriends(String me, String a, String b) =>
      a == b || a == me || b == me || links.contains(koenPairKey(a, b));

  /// Los encuentros de hoy entre todo lo que se ve.
  List<KoenEncounter> encounters(String me, [int? day]) => koenEncounters(
    day: day ?? bonusDay(),
    cards: all,
    friends: (a, b) => areFriends(me, a, b),
  );

  KoenState copyWith({
    List<KoenCard>? mine,
    Map<String, List<KoenCard>>? friends,
    Set<String>? links,
    bool? loaded,
    bool? loading,
    bool? failed,
    Map<KoenMemory, int>? album,
    Map<String, int>? drags,
    int? dragsDay,
    int? giftDay,
    int? ticketWeek,
    bool? demo,
    int? demoEarned,
    KoenSummary? summary,
    bool clearSummary = false,
    Map<String, KoenTally>? bonds,
    Map<String, KoenTally>? mates,
    Map<String, int>? theirs,
    Map<String, KoenFriendLevel>? levels,
    Map<String, Set<int>>? rewarded,
    Set<String>? demoPrizes,
  }) => KoenState(
    mine: mine ?? this.mine,
    friends: friends ?? this.friends,
    links: links ?? this.links,
    loaded: loaded ?? this.loaded,
    loading: loading ?? this.loading,
    failed: failed ?? this.failed,
    album: album ?? this.album,
    drags: drags ?? this.drags,
    dragsDay: dragsDay ?? this.dragsDay,
    giftDay: giftDay ?? this.giftDay,
    ticketWeek: ticketWeek ?? this.ticketWeek,
    demo: demo ?? this.demo,
    demoEarned: demoEarned ?? this.demoEarned,
    summary: clearSummary ? null : summary ?? this.summary,
    bonds: bonds ?? this.bonds,
    mates: mates ?? this.mates,
    theirs: theirs ?? this.theirs,
    levels: levels ?? this.levels,
    rewarded: rewarded ?? this.rewarded,
    demoPrizes: demoPrizes ?? this.demoPrizes,
  );
}

/// Lo que ha traído el parque de una vez: lo que se enseña al entrar
/// («mientras no estabas») o tras un encuentro forzado.
@immutable
class KoenSummary {
  const KoenSummary({
    this.meets = 0,
    this.coins = 0,
    this.food,
    this.ticket = false,
    this.memories = const <KoenMemory>[],
    this.petted = const <String>[],
    this.quiet = false,
    this.bondUps = const <KoenBondUp>[],
    this.friendUps = const <KoenFriendUp>[],
    this.prizes = const <String>[],
  });

  /// Encuentros nuevos con Tamas de amigos.
  final int meets;
  final int coins;
  final TamaFood? food;
  final bool ticket;
  final List<KoenMemory> memories;

  /// Los nombres de los Tamas propios que vuelven contentos.
  final List<String> petted;

  /// Viene de un encuentro forzado: se avisa sin abrir el resumen.
  final bool quiet;

  /// Las parejas de Tamas que han subido de nivel de amistad.
  final List<KoenBondUp> bondUps;

  /// Los amigos con los que ha subido la amistad, y lo que se ha cobrado.
  final List<KoenFriendUp> friendUps;

  /// Los premios de la amistad entre Tamas (`bg_koen`, `momiji_red`).
  final List<String> prizes;

  /// Lo que hay que celebrar en grande aunque venga de arrastrar.
  bool get big => ticket || bondUps.isNotEmpty || friendUps.isNotEmpty || prizes.isNotEmpty;

  bool get isEmpty =>
      meets == 0 && coins == 0 && food == null && !ticket && memories.isEmpty && !big;

  KoenSummary copyWith({
    bool? ticket,
    List<KoenBondUp>? bondUps,
    List<KoenFriendUp>? friendUps,
    List<String>? prizes,
  }) => KoenSummary(
    meets: meets,
    coins: coins,
    food: food,
    ticket: ticket ?? this.ticket,
    memories: memories,
    petted: petted,
    quiet: quiet,
    bondUps: bondUps ?? this.bondUps,
    friendUps: friendUps ?? this.friendUps,
    prizes: prizes ?? this.prizes,
  );
}

/// Dos Tamas que se han hecho más amigos: llegan a [level] (2–5).
@immutable
class KoenBondUp {
  const KoenBondUp(this.a, this.b, this.level);

  final KoenCard a;
  final KoenCard b;
  final int level;
}

/// La amistad con [friend] ha llegado a [level]; se han cobrado [coins].
@immutable
class KoenFriendUp {
  const KoenFriendUp(this.friend, this.level, this.coins);

  final String friend;
  final KoenFriendLevel level;
  final int coins;
}

/// Tama Kōen. `/users/{cuenta}/koen/park/{0..2}` guarda las fichas de los
/// Tamas que la cuenta tiene en el parque; lo leen sus amigos.
///
/// No escucha nada en vivo: se lee al abrir el canal y al refrescar
/// ([refresh]). Lee el parque propio, el de cada amigo y, de los amigos que
/// tienen Tamas allí, su lista de amigos, para saber qué Tamas pueden jugar
/// juntos.
class KoenController extends StateNotifier<KoenState> {
  KoenController({
    required IbashoBackend backend,
    required SessionController session,
    required RewardsState Function() rewardsOf,
    required Future<RewardOutcome> Function(int amount) claimCoins,
    required int Function(TamaFood food) pantryOf,
    required int Function(TicketKind kind) ticketsOf,
    required bool Function(String tamaId) isMine,
    required void Function(String tamaId) pet,
    required int Function() coinsOf,
    required bool Function(String key) owns,
    String? Function(String tamaId)? duoOf,
  }) : _backend = backend,
       _session = session,
       _rewardsOf = rewardsOf,
       _claimCoins = claimCoins,
       _pantryOf = pantryOf,
       _ticketsOf = ticketsOf,
       _isMine = isMine,
       _pet = pet,
       _coinsOf = coinsOf,
       _owns = owns,
       _duoOf = duoOf ?? _noDuo,
       super(const KoenState());

  final IbashoBackend _backend;
  final SessionController _session;
  final RewardsState Function() _rewardsOf;
  final Future<RewardOutcome> Function(int amount) _claimCoins;
  final int Function(TamaFood food) _pantryOf;
  final int Function(TicketKind kind) _ticketsOf;
  final bool Function(String tamaId) _isMine;
  final void Function(String tamaId) _pet;
  final int Function() _coinsOf;
  final bool Function(String key) _owns;

  /// El otro Tama del dúo de un Tama, para ponerlo en su ficha.
  final String? Function(String tamaId) _duoOf;

  static String? _noDuo(String _) => null;

  /// Se están cobrando monedas (van de 5 en 5, con 15 s entre cobro y cobro).
  bool _paying = false;

  String get _me => _session.state.accountId;

  String _park(String account) => '/users/$account/koen/park';

  /// Vuelve a leer el parque. [friendIds] son los amigos de la cuenta y
  /// [tamas] sus Tamas, para poner al día las fichas propias.
  Future<void> refresh({required List<String> friendIds, required List<Tama> tamas}) async {
    if (_me.isEmpty || state.loading) return;
    state = state.copyWith(loading: true);
    try {
      final token = await _session.freshToken();
      final parks = await Future.wait([
        _backend.read('/users/$_me/koen', idToken: token),
        for (final id in friendIds)
          _backend.read(_park(id), idToken: token).then<Object?>((v) => v, onError: (Object _) => null),
      ]);
      if (!mounted) return;
      final own = parks.first is Map ? parks.first! as Map : const <Object?, Object?>{};
      var mine = KoenCard.parkFromJson(_me, own['park']);
      final friends = <String, List<KoenCard>>{};
      for (var i = 0; i < friendIds.length; i++) {
        final cards = KoenCard.parkFromJson(friendIds[i], parks[i + 1]);
        if (cards.isNotEmpty) friends[friendIds[i]] = cards;
      }
      // Quién de ellos es amigo de quién: solo hace falta de los que tienen
      // Tamas en el parque, y solo las claves.
      final present = friends.keys.toList();
      final lists = await Future.wait([
        for (final id in present)
          _backend
              .read('/users/$id/friends', idToken: token, shallow: true)
              .then<Object?>((v) => v, onError: (Object _) => null),
      ]);
      final links = <String>{};
      for (var i = 0; i < present.length; i++) {
        final list = lists[i];
        if (list is! Map) continue;
        for (final other in list.keys) {
          if (friends.containsKey('$other')) links.add(koenPairKey(present[i], '$other'));
        }
      }
      // Lo que lleva sumado cada uno de ellos con la cuenta: solo cambia
      // mientras tienen Tamas en el parque.
      final halves = await Future.wait([
        for (final id in present)
          _backend
              .read('/users/$id/koen/friends/$_me/p', idToken: token)
              .then<Object?>((v) => v, onError: (Object _) => null),
      ]);
      final theirs = <String, int>{
        for (var i = 0; i < present.length; i++)
          if (halves[i] is num) present[i]: (halves[i]! as num).toInt(),
      };
      mine = await _tidy(mine, tamas, token);
      if (!mounted) return;
      state = KoenState(
        mine: mine,
        friends: friends,
        links: links,
        loaded: true,
        album: _albumFrom(own['album']),
        drags: _dragsFrom(own['drags']),
        dragsDay: _int((own['drags'] as Map?)?['day']),
        giftDay: _int((own['gift'] as Map?)?['day']),
        ticketWeek: _int((own['ticket'] as Map?)?['week']),
        bonds: _talliesFrom(own['bonds']),
        mates: _talliesFrom(own['friends']),
        theirs: theirs,
        levels: levelsFrom(own['friends']),
        rewarded: _rewardedFrom(own['rewards']),
      );
      unawaited(collect());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el parque ($e)');
      if (mounted) state = state.copyWith(loading: false, loaded: true, failed: true);
    }
  }

  /// Saca del parque los Tamas que ya no tiene la cuenta y reescribe las
  /// fichas de los que han cambiado de aspecto.
  Future<List<KoenCard>> _tidy(List<KoenCard> mine, List<Tama> tamas, String token) async {
    final byId = {for (final t in tamas) t.id: t};
    final patch = <String, Object?>{};
    final out = <KoenCard>[];
    for (final card in mine) {
      final tama = byId[card.tamaId];
      if (tama == null) {
        patch['${card.slot}'] = null;
      } else if (card.staleFor(tama, duo: _duoOf(tama.id))) {
        final fresh = KoenCard.ofTama(tama, holder: _me, slot: card.slot, at: card.at, duo: _duoOf(tama.id));
        patch['${card.slot}'] = fresh.toJson();
        out.add(fresh);
      } else {
        out.add(card);
      }
    }
    if (patch.isNotEmpty) {
      try {
        await _backend.merge(_park(_me), patch, idToken: token);
      } catch (e) {
        debugPrint('Ibasho: no se han podido poner al día las fichas del parque ($e)');
      }
    }
    return out;
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static Map<KoenMemory, int> _albumFrom(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is num && KoenMemory.byName('${e.key}') != null)
          KoenMemory.byName('${e.key}')!: (e.value as num).toInt(),
  };

  static Map<String, KoenTally> _talliesFrom(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is Map) '${e.key}': KoenTally.fromJson(e.value),
  };

  /// Los niveles de amistad guardados en `koen/friends` (`l` de cada amigo).
  static Map<String, KoenFriendLevel> levelsFrom(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.value is Map && (e.value as Map)['l'] is num)
          '${e.key}': KoenFriendLevel.values[((e.value as Map)['l'] as num).toInt().clamp(0, KoenFriendLevel.values.length - 1)],
  };

  static Map<String, Set<int>> _rewardedFrom(Object? raw) => {
    if (raw is Map)
      for (final e in raw.entries)
        '${e.key}': {
          if (e.value is Map)
            for (final k in (e.value as Map).keys) ?int.tryParse('$k'),
          if (e.value is List)
            for (var i = 0; i < (e.value as List).length; i++)
              if ((e.value as List)[i] != null) i,
        },
  };

  static Map<String, int> _dragsFrom(Object? raw) {
    final pairs = raw is Map ? raw['pairs'] : null;
    return {
      if (pairs is Map)
        for (final e in pairs.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    };
  }

  int get _earnedToday => state.demo ? state.demoEarned : _rewardsOf().earnedToday(koenGame);

  /// Cobra lo que haya dejado el parque desde la última vez: las monedas de
  /// los encuentros con Tamas de amigos (los del día que ya han pasado y los
  /// forzados), la chuche del día, el ticket de la semana al llenar el
  /// medidor, los recuerdos nuevos y un mimo a los Tamas propios que han
  /// jugado. Deja en [KoenState.summary] lo que haya.
  ///
  /// [extra] son los recuerdos de un encuentro forzado que acaba de pasar.
  Future<void> collect({DateTime? now, Set<KoenMemory> extra = const {}, bool quiet = false}) async {
    if (_me.isEmpty || !state.loaded || _paying) return;
    // Sin saber lo cobrado hoy no se puede saber qué falta por cobrar.
    if (!state.demo && !_rewardsOf().loaded) return;
    now ??= DateTime.now();
    final day = bonusDay();
    final season = koenSeason(now, south: koenSouthern(WidgetsBinding.instance.platformDispatcher.locale.countryCode));
    final all = state.encounters(_me, day);
    final done = koenDone(all, now);

    // Monedas: 5 por encuentro con un amigo, hasta el tope. Lo ya cobrado
    // hoy dice cuántos encuentros se han pagado.
    final paying = done.where((e) => koenPays(e, _me)).toList();
    final dragged = [
      for (final e in all.where((e) => koenPays(e, _me)))
        for (var i = 0; i < state.dragsToday(e.pairKey, day); i++) e,
    ];
    // Los forzados de parejas que hoy no se encuentran solas no salen en
    // `all`: se cuentan aparte.
    final looseDrags = state.dragsDay == day
        ? state.drags.entries
            .where((d) => !all.any((e) => e.pairKey == d.key) && _paysPair(d.key))
            .fold<int>(0, (n, d) => n + d.value)
        : 0;
    final owed = paying.length + dragged.length + looseDrags;
    final earned = _earnedToday;
    final paid = (earned + koenCoinsPerMeet - 1) ~/ koenCoinsPerMeet;
    final fresh = math.max(0, owed - paid);
    final cap = rewardCapFor(koenGame);
    final coins = math.min(fresh * koenCoinsPerMeet, math.max(0, cap - earned));

    // Recuerdos.
    final memories = <KoenMemory>{...extra};
    var count = 0;
    for (final e in done) {
      if (koenPays(e, _me)) count++;
      memories.addAll(koenMemoriesOf(
        e,
        me: _me,
        season: season,
        closeness: state.closeness(e.a, e.b, day),
        paidToday: count,
      ));
    }
    memories.removeWhere(state.album.containsKey);

    // La chuche del día, con el primer encuentro con un amigo.
    final food = owed > 0 && state.giftDay != day ? koenGiftFood(day, _me) : null;

    // Un mimo a los propios que han jugado hoy con alguien.
    final petted = <String>[];
    for (final c in state.mine) {
      if (done.any((e) => e.involves(c.tamaId)) && _isMine(c.tamaId)) {
        if (!state.demo) _pet(c.tamaId);
        petted.add(c.name);
      }
    }

    // La amistad: entre cada pareja con un Tama propio y con cada amigo.
    final friendship = _befriend(day, now, all);

    var summary = KoenSummary(
      meets: fresh,
      coins: coins,
      food: food,
      memories: memories.toList()..sort((a, b) => a.index.compareTo(b.index)),
      petted: petted,
      quiet: quiet,
      bondUps: friendship.bondUps,
    );
    state = state.copyWith(
      album: {...state.album, for (final m in memories) m: day},
      giftDay: food != null ? day : null,
      summary: summary.isEmpty ? null : summary,
      bonds: friendship.bonds,
      mates: friendship.mates,
      levels: friendship.levels,
    );
    if (!state.demo) {
      final token = await _session.freshToken();
      try {
        await _backend.merge('/', {
          for (final m in memories) 'users/$_me/koen/album/${m.name}': day,
          ...friendship.patch,
          if (food != null) ...{
            'users/$_me/koen/gift': {'day': day, 'food': food.name, 'at': serverTimestamp},
            'users/$_me/pantry/${food.name}': _pantryOf(food) + 1,
          },
        }, idToken: token);
      } catch (e) {
        debugPrint('Ibasho: no se han podido guardar los recuerdos o el regalo del parque ($e)');
      }
    }

    // Las monedas, de 5 en 5 (el último cobro, lo que falte hasta el tope).
    if (coins > 0) {
      _paying = true;
      try {
        var left = coins;
        while (left > 0 && mounted) {
          final step = math.min(koenCoinsPerMeet, left);
          if (state.demo) {
            state = state.copyWith(demoEarned: state.demoEarned + step);
          } else {
            final out = await _claimCoins(step);
            if (out.status != RewardStatus.granted) break;
          }
          left -= step;
        }
      } finally {
        _paying = false;
      }
    }

    // El ticket de la semana, al llenar el medidor del parque.
    final week = koenWeek(now);
    if (mounted && _earnedToday >= cap && state.ticketWeek != week) {
      var ok = state.demo;
      if (!ok) {
        try {
          await _backend.merge('/', {
            'users/$_me/koen/ticket': {'week': week, 'at': serverTimestamp},
            'users/$_me/tickets/${TicketKind.gachaken.name}': _ticketsOf(TicketKind.gachaken) + 1,
          }, idToken: await _session.freshToken());
          ok = true;
        } catch (e) {
          debugPrint('Ibasho: no se ha podido cobrar el ticket del parque ($e)');
        }
      }
      if (ok && mounted) {
        summary = summary.copyWith(ticket: true);
        state = state.copyWith(ticketWeek: week, summary: summary);
      }
    }

    // Los premios de la amistad: entre Tamas, el fondo y el gorro; con cada
    // amigo, las monedas de cada nivel.
    final prizes = mounted ? await _claimBondPrizes() : const <String>[];
    final ups = mounted ? await _claimFriendRewards(friendship.raised) : const <KoenFriendUp>[];
    if (mounted && (prizes.isNotEmpty || ups.isNotEmpty)) {
      summary = summary.copyWith(prizes: prizes, friendUps: ups);
      state = state.copyWith(summary: summary);
    }
  }

  /// Suma la amistad de hoy. Devuelve lo nuevo y lo que hay que escribir.
  _Friendship _befriend(int day, DateTime now, List<KoenEncounter> all) {
    final byId = {for (final c in state.all) c.tamaId: c};
    bool mine(String id) => state.has(id);
    final today = koenTodayByPair(
      all: all,
      now: now,
      drags: (k) => state.dragsToday(k, day),
      draggedPairs: state.dragsDay == day ? state.drags.keys : const <String>[],
    );
    final bonds = {...state.bonds};
    final perFriend = <String, int>{};
    final ups = <KoenBondUp>[];
    final patch = <String, Object?>{};
    for (final entry in today.entries) {
      final ids = entry.key.split('_');
      if (ids.length != 2) continue;
      final a = byId[ids[0]];
      final b = byId[ids[1]];
      if (a == null || b == null || (!mine(a.tamaId) && !mine(b.tamaId))) continue;
      final total = math.min(entry.value, koenBondDailyCap);
      final before = bonds[entry.key] ?? const KoenTally();
      final after = before.count(day, total);
      if (after != before) {
        bonds[entry.key] = after;
        patch['users/$_me/koen/bonds/${entry.key}'] = after.toJson();
        final level = koenBondLevel(after.p);
        if (level > koenBondLevel(before.p)) ups.add(KoenBondUp(a, b, level));
      }
      if (a.holder != b.holder) {
        final friend = a.holder == _me ? b.holder : a.holder;
        perFriend[friend] = (perFriend[friend] ?? 0) + total;
      }
    }
    final mates = {...state.mates};
    final levels = {...state.levels};
    final raised = <String>{};
    final friends = {...perFriend.keys, ...state.theirs.keys};
    for (final friend in friends) {
      final before = mates[friend] ?? const KoenTally();
      final after = before.count(day, math.min(perFriend[friend] ?? 0, koenFriendDailyCap));
      final level = KoenFriendLevel.of(after.p + (state.theirs[friend] ?? 0));
      final known = levels[friend] ?? KoenFriendLevel.none;
      if (after == before && level == known) continue;
      mates[friend] = after;
      levels[friend] = level;
      // `d` tiene que ser hoy para las reglas, aunque hoy no sume nada.
      final saved = after.d == day ? after : KoenTally(p: after.p, d: day);
      patch['users/$_me/koen/friends/$friend'] = {...saved.toJson(), 'l': level.index};
      if (level.index > known.index) raised.add(friend);
    }
    ups.sort((x, y) => y.level.compareTo(x.level));
    return _Friendship(bonds: bonds, mates: mates, levels: levels, bondUps: ups, raised: raised, patch: patch);
  }

  /// El fondo y el gorro de la amistad entre Tamas, la primera vez que una
  /// pareja propia llega a su nivel. Cada uno va con su recibo
  /// (`koen/prize`), que las reglas cruzan con la amistad de esa pareja.
  Future<List<String>> _claimBondPrizes() async {
    final out = <String>[];
    for (final MapEntry(key: level, value: key) in koenBondPrizes.entries) {
      if (_owns(key) || state.demoPrizes.contains(key)) continue;
      final pair = state.bonds.entries.where((b) => koenBondLevel(b.value.p) >= level).firstOrNull?.key;
      if (pair == null) continue;
      if (state.demo) {
        state = state.copyWith(demoPrizes: {...state.demoPrizes, key});
        out.add(key);
        continue;
      }
      try {
        await _backend.merge('/', {
          'users/$_me/koen/prize': {'key': key, 'pair': pair, 'at': serverTimestamp},
          'users/$_me/prizes/$key': 1,
        }, idToken: await _session.freshToken());
        out.add(key);
      } catch (e) {
        debugPrint('Ibasho: no se ha podido cobrar el premio de la amistad ($e)');
      }
    }
    return out;
  }

  /// Las monedas de cada nivel de amistad con un amigo, una vez por nivel.
  /// Cada cobro lleva su recibo (`koen/reward`), que las reglas cruzan con
  /// los puntos de los dos.
  Future<List<KoenFriendUp>> _claimFriendRewards(Set<String> raised) async {
    final out = <KoenFriendUp>[];
    for (final friend in {...raised, ...state.levels.keys}) {
      final level = state.friendLevel(friend);
      var paid = 0;
      for (final l in KoenFriendLevel.values) {
        if (l.coins == 0 || l.index > level.index) continue;
        if (state.rewarded[friend]?.contains(l.index) ?? false) continue;
        var ok = state.demo;
        if (!ok) {
          try {
            await _backend.merge('/', {
              'users/$_me/koen/reward': {'friend': friend, 'level': l.index, 'at': serverTimestamp},
              'users/$_me/koen/rewards/$friend/${l.index}': true,
              'users/$_me/coins': _coinsOf() + l.coins,
            }, idToken: await _session.freshToken());
            ok = true;
          } catch (e) {
            debugPrint('Ibasho: no se ha podido cobrar el premio de amistad ($e)');
          }
        }
        if (!ok || !mounted) break;
        paid += l.coins;
        state = state.copyWith(rewarded: {
          ...state.rewarded,
          friend: {...?state.rewarded[friend], l.index},
        });
      }
      if (raised.contains(friend) && level.index >= KoenFriendLevel.friends.index) {
        out.add(KoenFriendUp(friend, level, paid));
      }
    }
    return out;
  }

  /// Si la pareja [pairKey] da monedas: uno de los dos es propio y el otro
  /// de un amigo.
  bool _paysPair(String pairKey) {
    final byId = {for (final c in state.all) c.tamaId: c};
    final ids = pairKey.split('_');
    if (ids.length != 2) return false;
    final a = byId[ids[0]];
    final b = byId[ids[1]];
    return a != null && b != null && a.holder != b.holder && (a.holder == _me || b.holder == _me);
  }

  /// Ya se ha enseñado el resumen.
  void clearSummary() => state = state.copyWith(clearSummary: true);

  /// Apunta un encuentro forzado entre [a] y [b] (arrastrando uno hasta el
  /// otro). `false` si esa pareja ya ha llegado al tope de hoy.
  Future<bool> drag(KoenCard a, KoenCard b) async {
    final day = bonusDay();
    final key = koenPairKey(a.tamaId, b.tamaId);
    final used = state.dragsToday(key, day);
    if (used >= koenDragsPerPair) return false;
    final drags = {if (state.dragsDay == day) ...state.drags, key: used + 1};
    state = state.copyWith(drags: drags, dragsDay: day);
    if (!state.demo) {
      try {
        await _backend.write('/users/$_me/koen/drags', {'day': day, 'pairs': drags},
            idToken: await _session.freshToken());
      } catch (e) {
        debugPrint('Ibasho: no se ha podido apuntar el encuentro del parque ($e)');
      }
    }
    if (!mounted) return true;
    final e = KoenEncounter(a: a.tamaId.compareTo(b.tamaId) < 0 ? a : b, b: a.tamaId.compareTo(b.tamaId) < 0 ? b : a,
        zone: KoenZone.tree, hour: 12, variant: 0, inPlace: true);
    final season = koenSeason(DateTime.now(), south: koenSouthern(WidgetsBinding.instance.platformDispatcher.locale.countryCode));
    await collect(
      extra: koenMemoriesOf(e, me: _me, season: season, closeness: state.closeness(a, b, day), dragged: true),
      quiet: true,
    );
    return true;
  }

  /// Manda [tama] al parque, al primer hueco libre. `false` si no hay hueco
  /// o no ha salido.
  Future<bool> send(Tama tama) async {
    if (state.has(tama.id)) return true;
    // Uno cuidado a medias que ya ha traído el otro.
    if (state.all.any((c) => c.tamaId == tama.id)) return false;
    final free = [for (var i = 0; i < koenSlots; i++) i].where((i) => state.slot(i) == null).firstOrNull;
    if (free == null) return false;
    final card = KoenCard.ofTama(
      tama,
      holder: _me,
      slot: free,
      at: DateTime.now().millisecondsSinceEpoch,
      duo: _duoOf(tama.id),
    );
    final before = state;
    state = state.copyWith(mine: [...state.mine, card]..sort((a, b) => a.slot.compareTo(b.slot)));
    try {
      await _backend.write('${_park(_me)}/$free', card.toJson(), idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido mandar el Tama al parque ($e)');
      if (mounted) state = before;
      return false;
    }
  }

  /// Saca del parque a [tamaId].
  Future<bool> recall(String tamaId) async {
    final card = state.mine.where((c) => c.tamaId == tamaId).firstOrNull;
    if (card == null) return true;
    final before = state;
    state = state.copyWith(mine: [...state.mine.where((c) => c.tamaId != tamaId)]);
    try {
      await _backend.remove('${_park(_me)}/${card.slot}', idToken: await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido sacar el Tama del parque ($e)');
      if (mounted) state = before;
      return false;
    }
  }

  /// Solo para probar en una build de depuración: llena el parque en local
  /// (sin escribir nada) con [tamas] propios y dos amigos inventados, amigos
  /// entre sí, con Tamas de aspecto al azar.
  void debugDemo(List<Tama> tamas) {
    final random = math.Random(7);
    const colors = ['#FFB3C8', '#9FD4FF', '#FFE08A', '#A8E6C4', '#C9B6FF', '#FF9F7A'];
    const names = ['Pumi', 'Kiko', 'Nube', 'Tofu', 'Mame', 'Yuzu'];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    Tama fake(int i) => Tama(
      id: '-demo${i.toString().padLeft(15, '0')}',
      creator: 'demo-${i ~/ 3}',
      keeper: 'demo-${i ~/ 3}',
      name: names[i],
      personality: TamaPersonality.values[random.nextInt(TamaPersonality.values.length)],
      look: TamaLook(
        parts: {for (final p in TamaPart.values) p: random.nextInt(p.variants)},
        color: colors[i],
      ),
      createdAt: epoch,
      updatedAt: epoch,
    );
    // Como si llevaran desde siempre, para que los encuentros de hoy cuenten.
    const now = 1;
    state = KoenState(
      demo: true,
      mine: [
        for (var i = 0; i < math.min(koenSlots, tamas.length); i++)
          KoenCard.ofTama(tamas[i], holder: _me, slot: i, at: now, duo: _duoOf(tamas[i].id)),
      ],
      friends: {
        for (var f = 0; f < 2; f++)
          'demo-$f': [
            for (var i = 0; i < 3; i++) KoenCard.ofTama(fake(f * 3 + i), holder: 'demo-$f', slot: i, at: now),
          ],
      },
      links: {koenPairKey('demo-0', 'demo-1')},
      loaded: true,
    );
    // A punto de subir de nivel, para ver las celebraciones: las parejas
    // propias con los del primer amigo, justo por debajo de cada nivel, y
    // los dos amigos, a un paso de «amigos» y de «buenos amigos».
    final mineCards = state.mine;
    final firstFriend = state.friends['demo-0'] ?? const <KoenCard>[];
    final bonds = <String, KoenTally>{
      for (var i = 0; i < mineCards.length; i++)
        for (var j = 0; j < firstFriend.length; j++)
          koenPairKey(mineCards[i].tamaId, firstFriend[j].tamaId):
              KoenTally(p: koenBondSteps[1 + (i + j) % (koenBondSteps.length - 1)] - 1),
    };
    state = state.copyWith(
      bonds: bonds,
      theirs: {
        'demo-0': KoenFriendLevel.friends.points - 1,
        'demo-1': KoenFriendLevel.good.points - 1,
      },
      levels: {'demo-0': KoenFriendLevel.acquainted, 'demo-1': KoenFriendLevel.friends},
      rewarded: {
        'demo-1': {KoenFriendLevel.friends.index},
      },
    );
    unawaited(collect());
  }
}

/// Lo que deja la amistad de una vez (ver [KoenController._befriend]).
class _Friendship {
  const _Friendship({
    required this.bonds,
    required this.mates,
    required this.levels,
    required this.bondUps,
    required this.raised,
    required this.patch,
  });

  final Map<String, KoenTally> bonds;
  final Map<String, KoenTally> mates;
  final Map<String, KoenFriendLevel> levels;
  final List<KoenBondUp> bondUps;

  /// Los amigos con los que ha subido el nivel.
  final Set<String> raised;
  final Map<String, Object?> patch;
}
