// Ibasho — el gacha: tickets, tiradas, el deposito de bolas y el Catalogo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/errors.dart';
import '../backend/gacha.dart';
import '../backend/gacha_prizes.dart';
import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart';
import 'session.dart';

/// Por que no ha salido una tirada (o no se han podido cargar las bolas del
/// pinball).
enum PullFailure {
  /// No hay tickets de ese tipo para pagarla.
  noTickets,

  /// Al cargar el pinball: ya no quedan bolas de las elegidas.
  noBalls,

  network,
  rejected,
}

class PullException implements Exception {
  const PullException(this.failure);

  final PullFailure failure;

  @override
  String toString() => 'PullException(${failure.name})';
}

/// Las bolas de la partida de pinball cargada (`gacha/play`) que aun no se
/// han jugado, y cuantas se han jugado ya.
@immutable
class PinballLoad {
  const PinballLoad({
    this.balls = const <Rarity, int>{},
    this.marked = const <GachaCategory, Map<Rarity, int>>{},
    this.done = 0,
  });

  final Map<Rarity, int> balls;
  final Map<GachaCategory, Map<Rarity, int>> marked;
  final int done;

  int ballsOf(Rarity rarity) => balls[rarity] ?? 0;

  int markedOf(GachaCategory category, Rarity rarity) => marked[category]?[rarity] ?? 0;
}

/// Lo que hay en `/users/{cuenta}/tickets`, `/users/{cuenta}/gacha` y
/// `/users/{cuenta}/prizes`.
@immutable
class GachaState {
  const GachaState({
    this.tickets = const <TicketKind, int>{},
    this.balls = const <Rarity, int>{},
    this.marked = const <GachaCategory, Map<Rarity, int>>{},
    this.wish,
    this.prizes = const <String, int>{},
    this.play,
    this.pulledOnce = false,
    this.pachinkoPlayed = false,
    this.loaded = false,
    this.busy = false,
  });

  /// Tickets guardados, por tipo.
  final Map<TicketKind, int> tickets;

  /// El deposito: bolas sin abrir por rareza, esperando al pinball.
  final Map<Rarity, int> balls;

  /// Bolas dirigidas del Catalogo, por categoria y rareza.
  final Map<GachaCategory, Map<Rarity, int>> marked;

  /// El deseo puesto en el Catalogo del pinball.
  final GachaWish? wish;

  /// La coleccion: copias de cada premio, por clave (`cap_red`).
  final Map<String, int> prizes;

  /// La partida de pinball cargada, si hay.
  final PinballLoad? play;

  /// Si la cuenta ha tirado alguna vez (hay recibo en `gacha/last`). Es lo
  /// que desbloquea el pinball, aunque luego se gasten todas las bolas.
  final bool pulledOnce;

  /// Si la cuenta ha jugado alguna tanda de pachinko (hay recibo). Con la
  /// primera partida de pinball, desbloquea el canal en otros dispositivos.
  final bool pachinkoPlayed;

  final bool loaded;

  /// Una tirada en curso.
  final bool busy;

  /// Nunca menos de 0, aunque llegue algo raro de la base.
  int ticketsOf(TicketKind kind) => math.max(0, tickets[kind] ?? 0);

  int ballsOf(Rarity rarity) => balls[rarity] ?? 0;

  int markedOf(GachaCategory category, Rarity rarity) => marked[category]?[rarity] ?? 0;

  /// Copias de [key] en la coleccion.
  int copiesOf(String key) => prizes[key] ?? 0;

  bool owns(String key) => copiesOf(key) > 0;

  /// Bolas guardadas en total, dirigidas incluidas.
  int get totalBalls =>
      balls.values.fold(0, (a, b) => a + b) +
      marked.values.fold(0, (a, m) => a + m.values.fold(0, (x, y) => x + y));

  /// Si llega para una tirada de [balls] bolas con [kind].
  bool canPull(TicketKind kind, int balls) => ticketsOf(kind) >= pullCost(balls);

  GachaState copyWith({
    Map<TicketKind, int>? tickets,
    Map<Rarity, int>? balls,
    Map<GachaCategory, Map<Rarity, int>>? marked,
    Object? wish = _keep,
    Map<String, int>? prizes,
    Object? play = _keep,
    bool? pulledOnce,
    bool? pachinkoPlayed,
    bool? loaded,
    bool? busy,
  }) => GachaState(
    tickets: tickets ?? this.tickets,
    balls: balls ?? this.balls,
    marked: marked ?? this.marked,
    wish: identical(wish, _keep) ? this.wish : wish as GachaWish?,
    prizes: prizes ?? this.prizes,
    play: identical(play, _keep) ? this.play : play as PinballLoad?,
    pulledOnce: pulledOnce ?? this.pulledOnce,
    pachinkoPlayed: pachinkoPlayed ?? this.pachinkoPlayed,
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
  );
}

const Object _keep = Object();

/// La maquina de capsulas.
///
/// El sorteo lo hace la app ([rollPull]): las reglas no pueden echar a suertes
/// nada, solo comprobar que los tickets bajan lo que cuesta la tirada y que
/// el deposito sube en tantas bolas como se han tirado. Por eso una tirada es
/// **una sola escritura multi-ruta**, igual que una compra.
class GachaController extends StateNotifier<GachaState> {
  GachaController({
    required IbashoBackend backend,
    required SessionController session,
    math.Random? random,
  })  : _backend = backend,
        _session = session,
        _random = random ?? math.Random.secure(),
        super(const GachaState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final math.Random _random;

  final List<StreamSubscription<DatabaseEvent>> _watches = <StreamSubscription<DatabaseEvent>>[];

  Object? _ticketsTree;
  Object? _gachaTree;
  Object? _prizesTree;

  /// Las jugadas del pinball van de una en una: cada una parte de lo que
  /// dejo la anterior.
  Future<void> _turns = Future<void>.value();

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    for (final w in _watches) {
      unawaited(w.cancel());
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final results = await Future.wait([
        _backend.read('/users/$_me/tickets', idToken: token),
        _backend.read('/users/$_me/gacha', idToken: token),
        _backend.read('/users/$_me/prizes', idToken: token),
      ]);
      _ticketsTree = results[0];
      _gachaTree = results[1];
      _prizesTree = results[2];
      if (mounted) state = _merged(loaded: true);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el gacha ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    if (!mounted) return;

    _watches.add(
      _backend.watch('/users/$_me/tickets', token: _session.freshToken).listen((event) {
        _ticketsTree = applyDatabaseEvent(_ticketsTree, event);
        if (mounted) state = _merged(loaded: true, busy: state.busy);
      }, onError: (Object e) => debugPrint('Ibasho: stream de tickets ($e)')),
    );
    _watches.add(
      _backend.watch('/users/$_me/gacha', token: _session.freshToken).listen((event) {
        _gachaTree = applyDatabaseEvent(_gachaTree, event);
        if (mounted) state = _merged(loaded: true, busy: state.busy);
      }, onError: (Object e) => debugPrint('Ibasho: stream del gacha ($e)')),
    );
    _watches.add(
      _backend.watch('/users/$_me/prizes', token: _session.freshToken).listen((event) {
        _prizesTree = applyDatabaseEvent(_prizesTree, event);
        if (mounted) state = _merged(loaded: true, busy: state.busy);
      }, onError: (Object e) => debugPrint('Ibasho: stream de la coleccion ($e)')),
    );
  }

  GachaState _merged({bool loaded = false, bool busy = false}) =>
      _merge(_ticketsTree, _gachaTree, _prizesTree, loaded: loaded, busy: busy);

  static GachaState _merge(Object? tickets, Object? gacha, Object? prizes, {bool loaded = false, bool busy = false}) =>
      GachaState(
        tickets: _parseTickets(tickets),
        balls: _parseBalls(gacha is Map ? gacha['balls'] : null),
        marked: _parseMarked(gacha is Map ? gacha['marked'] : null),
        wish: GachaWish.fromJson(gacha is Map ? gacha['wish'] : null),
        prizes: _parsePrizes(prizes),
        play: _parsePlay(gacha is Map ? gacha['play'] : null),
        pulledOnce: gacha is Map && gacha['last'] != null,
        pachinkoPlayed: gacha is Map && (gacha['pachinko'] != null || gacha['settle'] != null),
        loaded: loaded,
        busy: busy,
      );

  static Map<TicketKind, int> _parseTickets(Object? raw) {
    if (raw is! Map) return const <TicketKind, int>{};
    final out = <TicketKind, int>{};
    for (final entry in raw.entries) {
      final kind = TicketKind.byName('${entry.key}');
      final value = entry.value;
      // Un negativo de una cuenta que quedo mal se trata como si no hubiera
      // ninguno: ni se ensena ni se puede gastar mas.
      if (kind != null && value is num) out[kind] = value.toInt() < 0 ? 0 : value.toInt();
    }
    return Map<TicketKind, int>.unmodifiable(out);
  }

  static Map<Rarity, int> _parseBalls(Object? raw) {
    if (raw is! Map) return const <Rarity, int>{};
    final out = <Rarity, int>{};
    for (final entry in raw.entries) {
      final rarity = Rarity.byName('${entry.key}');
      final value = entry.value;
      // Igual que con los tickets: un negativo se lee como 0.
      if (rarity != null && value is num) out[rarity] = value.toInt() < 0 ? 0 : value.toInt();
    }
    return Map<Rarity, int>.unmodifiable(out);
  }

  static Map<GachaCategory, Map<Rarity, int>> _parseMarked(Object? raw) {
    if (raw is! Map) return const <GachaCategory, Map<Rarity, int>>{};
    final out = <GachaCategory, Map<Rarity, int>>{};
    for (final entry in raw.entries) {
      final category = GachaCategory.byName('${entry.key}');
      if (category == null) continue;
      final byRarity = _parseBalls(entry.value);
      if (byRarity.isNotEmpty) out[category] = byRarity;
    }
    return Map<GachaCategory, Map<Rarity, int>>.unmodifiable(out);
  }

  static Map<String, int> _parsePrizes(Object? raw) {
    if (raw is! Map) return const <String, int>{};
    return Map<String, int>.unmodifiable(<String, int>{
      for (final entry in raw.entries)
        if (entry.value is num && (entry.value as num) > 0) '${entry.key}': (entry.value as num).toInt(),
    });
  }

  static PinballLoad? _parsePlay(Object? raw) {
    if (raw is! Map) return null;
    final done = raw['done'];
    return PinballLoad(
      balls: _parseBalls(raw['balls']),
      marked: _parseMarked(raw['marked']),
      done: done is num ? done.toInt() : 0,
    );
  }

  /// Tira [balls] bolas (de 1 a 9, u 11 por 10 tickets) con [kind].
  /// Devuelve lo que ha salido, ya guardado en el deposito.
  Future<PullResult> pull(TicketKind kind, {int balls = singlePullBalls}) async {
    if (!isPullSize(balls)) throw const PullException(PullFailure.rejected);
    final cost = pullCost(balls);
    if (state.ticketsOf(kind) < cost) throw const PullException(PullFailure.noTickets);
    // Lo que queda se calcula una sola vez, antes de escribir: el stream de
    // tickets puede traer el valor nuevo mientras se espera a la escritura, y
    // volver a restar sobre el estado de despues lo dejaba en -1.
    final left = state.ticketsOf(kind) - cost;

    final rolled = rollPull(kind: kind, balls: balls, random: _random);

    // El deposito entero, que es lo que comprueban las reglas: la suma sube
    // exactamente en las bolas tiradas.
    final newBalls = <String, int>{
      for (final rarity in Rarity.values) rarity.name: state.ballsOf(rarity),
    };
    for (final ball in rolled) {
      newBalls[ball.rarity.name] = newBalls[ball.rarity.name]! + 1;
    }

    final writes = <String, Object?>{
      'users/$_me/gacha/last': {'kind': kind.name, 'count': balls, 'at': serverTimestamp},
      'users/$_me/gacha/balls': newBalls,
      'users/$_me/tickets/${kind.name}': left,
      // Señal para la mision «tira del gachapon» (`lib/backend/missions.dart`).
      'users/$_me/missions/signal/pull': {'at': serverTimestamp},
    };

    state = state.copyWith(busy: true);
    try {
      await _backend.merge('/', writes, idToken: await _session.freshToken());
    } on IbashoException catch (e) {
      throw PullException(
        e.failure == IbashoFailure.network ? PullFailure.network : PullFailure.rejected,
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido tirar del gacha ($e)');
      throw const PullException(PullFailure.rejected);
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }

    if (mounted) {
      state = state.copyWith(
        tickets: {...state.tickets, kind: left},
        balls: {for (final entry in newBalls.entries) Rarity.byName(entry.key)!: entry.value},
        pulledOnce: true,
      );
    }
    return PullResult(kind: kind, balls: rolled);
  }

  /// Saca del deposito las bolas de [queue] para jugarlas en el pinball. Es
  /// una sola escritura con el recibo `gacha/play`: las reglas comprueban que
  /// cada rareza del deposito baja justo lo cargado. Desde aqui las
  /// bolas viven en la partida guardada en el dispositivo.
  Future<void> loadPinball(List<GachaBall> queue) async {
    final (plain, directed) = _split(queue);
    for (final entry in plain.entries) {
      if (state.ballsOf(entry.key) < entry.value) throw const PullException(PullFailure.noBalls);
    }
    for (final c in directed.entries) {
      for (final r in c.value.entries) {
        if (state.markedOf(c.key, r.key) < r.value) throw const PullException(PullFailure.noBalls);
      }
    }

    final newBalls = <String, int>{
      for (final rarity in Rarity.values) rarity.name: state.ballsOf(rarity) - (plain[rarity] ?? 0),
    };
    final writes = <String, Object?>{
      'users/$_me/gacha/play': {
        'at': serverTimestamp,
        'count': queue.length,
        if (plain.isNotEmpty) 'balls': {for (final e in plain.entries) e.key.name: e.value},
        if (directed.isNotEmpty)
          'marked': {
            for (final c in directed.entries) c.key.name: {for (final r in c.value.entries) r.key.name: r.value},
          },
      },
      'users/$_me/gacha/balls': newBalls,
      for (final c in directed.entries)
        for (final r in c.value.entries)
          'users/$_me/gacha/marked/${c.key.name}/${r.key.name}': state.markedOf(c.key, r.key) - r.value,
    };

    await _writePinball(writes, 'cargar');

    if (mounted) {
      final newMarked = <GachaCategory, Map<Rarity, int>>{
        for (final c in state.marked.entries)
          c.key: <Rarity, int>{
            for (final r in c.value.entries) r.key: r.value - (directed[c.key]?[r.key] ?? 0),
          },
      };
      state = state.copyWith(
        balls: {for (final entry in newBalls.entries) Rarity.byName(entry.key)!: entry.value},
        marked: newMarked,
        play: PinballLoad(balls: plain, marked: directed),
      );
    }
  }

  /// Las bolas de [queue] contadas por rareza: las normales y las dirigidas
  /// de cada categoria.
  static (Map<Rarity, int>, Map<GachaCategory, Map<Rarity, int>>) _split(List<GachaBall> queue) {
    final plain = <Rarity, int>{};
    final directed = <GachaCategory, Map<Rarity, int>>{};
    for (final ball in queue) {
      final category = ball.category;
      if (category == null) {
        plain[ball.rarity] = (plain[ball.rarity] ?? 0) + 1;
      } else {
        final byRarity = directed.putIfAbsent(category, () => <Rarity, int>{});
        byRarity[ball.rarity] = (byRarity[ball.rarity] ?? 0) + 1;
      }
    }
    return (plain, directed);
  }

  Future<void> _writePinball(Map<String, Object?> writes, String what) async {
    state = state.copyWith(busy: true);
    try {
      await _backend.merge('/', writes, idToken: await _session.freshToken());
    } on IbashoException catch (e) {
      debugPrint('Ibasho: no se han podido $what las bolas del pinball (${e.failure})');
      throw PullException(
        e.failure == IbashoFailure.network ? PullFailure.network : PullFailure.rejected,
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido $what las bolas del pinball ($e)');
      throw const PullException(PullFailure.rejected);
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Cancela la partida del pinball y devuelve al deposito (y al Catalogo
  /// las dirigidas) las bolas de [unplayed], las que aun no habian salido.
  Future<void> cancelPinball(List<GachaBall> unplayed) async {
    final (plain, directed) = _split(unplayed);
    final newBalls = <String, int>{
      for (final rarity in Rarity.values) rarity.name: state.ballsOf(rarity) + (plain[rarity] ?? 0),
    };
    final writes = <String, Object?>{
      'users/$_me/gacha/back': {'at': serverTimestamp},
      'users/$_me/gacha/play': null,
      'users/$_me/gacha/balls': newBalls,
      for (final c in directed.entries)
        for (final r in c.value.entries)
          'users/$_me/gacha/marked/${c.key.name}/${r.key.name}': state.markedOf(c.key, r.key) + r.value,
    };
    await _writePinball(writes, 'devolver');
    if (mounted) {
      final newMarked = <GachaCategory, Map<Rarity, int>>{
        for (final c in <GachaCategory>{...state.marked.keys, ...directed.keys})
          c: <Rarity, int>{
            for (final r in <Rarity>{...?state.marked[c]?.keys, ...?directed[c]?.keys})
              r: state.markedOf(c, r) + (directed[c]?[r] ?? 0),
          },
      };
      state = state.copyWith(
        balls: {for (final entry in newBalls.entries) Rarity.byName(entry.key)!: entry.value},
        marked: newMarked,
        play: null,
      );
    }
  }

  /// Cierra la bola numero [index] (0 la primera) de la partida cargada: la
  /// baja de `gacha/play`, guarda [prize] en la coleccion si ha dado premio y
  /// sube el contador del Catalogo. Es una sola escritura con el recibo
  /// `gacha/turn`. Van en fila: la siguiente espera a que acabe esta.
  ///
  /// Si la bola ya estaba guardada (se reintenta tras un corte), no vuelve a
  /// escribir. Devuelve si llega la bola dirigida del Catalogo al deposito.
  Future<bool> playTurn({required int index, required GachaBall ball, String? prize}) {
    final done = _turns.then((_) => _playTurn(index, ball, prize));
    _turns = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<bool> _playTurn(int index, GachaBall ball, String? prize) async {
    final play = state.play;
    if (play == null) throw const PullException(PullFailure.noBalls);
    if (play.done > index) return false;
    if (play.done < index) throw const PullException(PullFailure.rejected);

    final category = ball.category;
    final left = category == null ? play.ballsOf(ball.rarity) : play.markedOf(category, ball.rarity);
    if (left <= 0) throw const PullException(PullFailure.noBalls);

    final wish = state.wish;
    final arrived = wish != null && wish.count + 1 >= wishPulls;
    final newWish = wish?.copyWith(count: arrived ? 0 : wish.count + 1);

    final writes = <String, Object?>{
      'users/$_me/gacha/turn': {
        'at': serverTimestamp,
        'rarity': ball.rarity.name,
        if (category != null) 'category': category.name,
        'prize': ?prize,
      },
      'users/$_me/gacha/play/done': index + 1,
      if (category == null)
        'users/$_me/gacha/play/balls/${ball.rarity.name}': left > 1 ? left - 1 : null
      else
        'users/$_me/gacha/play/marked/${category.name}/${ball.rarity.name}': left > 1 ? left - 1 : null,
      if (prize != null) 'users/$_me/prizes/$prize': state.copiesOf(prize) + 1,
      'users/$_me/gacha/wish': ?newWish?.toJson(),
      if (arrived)
        'users/$_me/gacha/marked/${wish.category.name}/${wish.rarity.name}': state.markedOf(wish.category, wish.rarity) + 1,
    };

    try {
      await _backend.merge('/', writes, idToken: await _session.freshToken());
    } on IbashoException catch (e) {
      debugPrint('Ibasho: no se ha podido guardar la bola del pinball (${e.failure})');
      throw PullException(e.failure == IbashoFailure.network ? PullFailure.network : PullFailure.rejected);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar la bola del pinball ($e)');
      throw const PullException(PullFailure.rejected);
    }

    if (mounted) {
      final current = state.play ?? play;
      state = state.copyWith(
        play: PinballLoad(
          balls: category == null ? {...current.balls, ball.rarity: left - 1} : current.balls,
          marked: category == null
              ? current.marked
              : {
                  ...current.marked,
                  category: {...?current.marked[category], ball.rarity: left - 1},
                },
          done: index + 1,
        ),
        prizes: prize == null ? state.prizes : {...state.prizes, prize: state.copiesOf(prize) + 1},
        wish: newWish ?? state.wish,
        marked: arrived
            ? {
                ...state.marked,
                wish.category: {
                  ...?state.marked[wish.category],
                  wish.rarity: state.markedOf(wish.category, wish.rarity) + 1,
                },
              }
            : state.marked,
      );
    }
    return arrived;
  }

  /// Saca del deposito las bolas de una tanda de pachinko ([balls], por
  /// rareza, de N a SSR). Es una sola escritura con el recibo
  /// `gacha/pachinko`: las reglas comprueban que cada rareza baja justo lo
  /// cargado. Desde aqui las bolas viven en la tanda guardada en el
  /// dispositivo.
  Future<void> loadPachinko(Map<Rarity, int> balls) async {
    final loaded = <Rarity, int>{
      for (final e in balls.entries)
        if (e.value > 0) e.key: e.value,
    };
    for (final e in loaded.entries) {
      if (state.ballsOf(e.key) < e.value) throw const PullException(PullFailure.noBalls);
    }
    final newBalls = <String, int>{
      for (final rarity in Rarity.values) rarity.name: state.ballsOf(rarity) - (loaded[rarity] ?? 0),
    };
    await _writePinball(<String, Object?>{
      'users/$_me/gacha/pachinko': {
        'at': serverTimestamp,
        'count': loaded.values.fold(0, (a, b) => a + b),
        'balls': {for (final e in loaded.entries) e.key.name: e.value},
      },
      'users/$_me/gacha/balls': newBalls,
    }, 'cargar');
    if (mounted) {
      state = state.copyWith(
        balls: {for (final entry in newBalls.entries) Rarity.byName(entry.key)!: entry.value},
        pachinkoPlayed: true,
      );
    }
  }

  /// Cierra la tanda de pachinko: devuelve al deposito [payout] (los premios
  /// y las bolas que no se llegaron a soltar) y borra el recibo.
  Future<void> settlePachinko(Map<Rarity, int> payout) async {
    final newBalls = <String, int>{
      for (final rarity in Rarity.values) rarity.name: state.ballsOf(rarity) + (payout[rarity] ?? 0),
    };
    await _writePinball(<String, Object?>{
      'users/$_me/gacha/settle': {'at': serverTimestamp},
      'users/$_me/gacha/pachinko': null,
      'users/$_me/gacha/balls': newBalls,
    }, 'cobrar');
    if (mounted) {
      state = state.copyWith(
        balls: {for (final entry in newBalls.entries) Rarity.byName(entry.key)!: entry.value},
      );
    }
  }


  /// Pone (o cambia) el deseo del Catalogo. Cambiar de deseo no pierde las
  /// bolas acumuladas: solo se reinician cuando la bola dirigida llega.
  Future<bool> setWish(GachaCategory category, Rarity rarity) async {
    if (!canWish(rarity)) return false;
    final wish = GachaWish(category: category, rarity: rarity, count: state.wish?.count ?? 0);
    try {
      await _backend.write('/users/$_me/gacha/wish', wish.toJson(), idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido poner el deseo ($e)');
      return false;
    }
    if (mounted) state = state.copyWith(wish: wish);
    return true;
  }

  /// Depuracion (solo admin, y solo en su cuenta): se da una copia de cada
  /// premio que aun no tenga, de las cuatro categorias. Las reglas solo lo
  /// aceptan de un admin en su cuenta.
  Future<bool> debugGiveAllPrizes() async {
    if (!_session.state.isAdmin) return false;
    final missing = [for (final key in allGachaPrizeKeys) if (!state.owns(key)) key];
    if (missing.isEmpty) return true;
    try {
      await _backend.merge(
        '/users/$_me/prizes',
        {for (final key in missing) key: 1},
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido dar los premios ($e)');
      return false;
    }
    if (mounted) state = state.copyWith(prizes: {...state.prizes, for (final key in missing) key: 1});
    return true;
  }

  /// Depuracion (solo admin, y solo en su cuenta): vacia la coleccion entera.
  /// Lo que lleven puesto sus Tamas se queda puesto.
  Future<bool> debugRemoveAllPrizes() async {
    if (!_session.state.isAdmin) return false;
    try {
      await _backend.remove('/users/$_me/prizes', idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se han podido quitar los premios ($e)');
      return false;
    }
    if (mounted) state = state.copyWith(prizes: const <String, int>{});
    return true;
  }

  /// Depuracion (solo admin, y solo en su cuenta): se da tickets sin pasar
  /// por la tienda. Las reglas lo rechazan a cualquier otra cuenta.
  Future<bool> debugGiveTickets(TicketKind kind, int amount) async {
    if (!_session.state.isAdmin) return false;
    final total = math.max(0, math.min(maxTickets, state.ticketsOf(kind) + amount));
    try {
      await _backend.write(
        '/users/$_me/tickets/${kind.name}',
        total,
        idToken: await _session.freshToken(),
      );
    } catch (e) {
      debugPrint('Ibasho: no se han podido dar tickets ($e)');
      return false;
    }
    if (mounted) state = state.copyWith(tickets: {...state.tickets, kind: total});
    return true;
  }
}
