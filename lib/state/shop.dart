// Ibasho — el Yatai: precios, juegos comprados y el flujo de compra.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/errors.dart';
import '../backend/gacha.dart';
import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart';
import '../backend/shop.dart';
import '../backend/tama.dart';
import 'session.dart';

/// Por que no ha salido una compra.
enum ShopFailure {
  /// El articulo no tiene precio: no se puede comprar todavia.
  noPrice,

  /// No llega el saldo.
  insufficientCoins,

  /// Es una comida que la cuenta no tiene desbloqueada.
  foodLocked,

  /// Ya se han comprado todos los tickets de esta semana.
  weeklyLimit,

  /// Ese juego ya esta en la cuenta (regalado o abierto).
  alreadyOwned,

  network,
  rejected,
}

class ShopException implements Exception {
  const ShopException(this.failure);

  final ShopFailure failure;

  @override
  String toString() => 'ShopException(${failure.name})';
}

@immutable
class ShopState {
  const ShopState({
    this.prices = const <String, int>{},
    this.games = const <String, GameInstall>{},
    this.week,
    this.loaded = false,
    this.busy = false,
  });

  /// `/shop/prices`, por id de articulo. Sin entrada, el articulo no esta a
  /// la venta.
  final Map<String, int> prices;

  /// `/users/{cuenta}/games`, por id de juego.
  final Map<String, GameInstall> games;

  /// `/users/{cuenta}/shop/week`: los tickets comprados esta semana. Sin
  /// nodo todavia, nadie ha comprado ninguno.
  final WeekTickets? week;

  final bool loaded;

  /// Una compra o un desenvolver en curso.
  final bool busy;

  /// Tickets de [kind] que aun se pueden comprar esta semana.
  int ticketsLeftThisWeek(TicketKind kind, [DateTime? now]) =>
      week?.leftOf(kind, now) ?? (weeklyTicketLimit[kind] ?? 0);

  ShopState copyWith({
    Map<String, int>? prices,
    Map<String, GameInstall>? games,
    WeekTickets? week,
    bool? loaded,
    bool? busy,
  }) => ShopState(
    prices: prices ?? this.prices,
    games: games ?? this.games,
    week: week ?? this.week,
    loaded: loaded ?? this.loaded,
    busy: busy ?? this.busy,
  );
}

/// El escaparate del Yatai: precios y juegos comprados, y la compra en si.
class ShopController extends StateNotifier<ShopState> {
  ShopController({
    required IbashoBackend backend,
    required SessionController session,
    required int Function() coinsOf,
    required int Function(TamaFood food) pantryQtyOf,
    required Set<TamaFood> Function() unlockedFoodsOf,
    required int Function(TicketKind kind) ticketsOf,
  }) : _backend = backend,
       _session = session,
       _coinsOf = coinsOf,
       _pantryQtyOf = pantryQtyOf,
       _unlockedFoodsOf = unlockedFoodsOf,
       _ticketsOf = ticketsOf,
       super(const ShopState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final int Function() _coinsOf;
  final int Function(TamaFood food) _pantryQtyOf;
  final Set<TamaFood> Function() _unlockedFoodsOf;
  final int Function(TicketKind kind) _ticketsOf;

  final List<StreamSubscription<DatabaseEvent>> _watches =
      <StreamSubscription<DatabaseEvent>>[];

  /// Copias de los nodos vigilados: el stream trae cambios sueltos (un juego
  /// nuevo llega como `/minesweeper`, desenvolverlo como `/minesweeper/state`)
  /// ademas del nodo entero.
  Object? _pricesTree;
  Object? _gamesTree;

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
        _backend.read('/shop/prices', idToken: token),
        _backend.read('/users/$_me/games', idToken: token),
        _backend.read('/users/$_me/shop/week', idToken: token),
      ]);
      _pricesTree = results[0];
      _gamesTree = results[1];
      if (mounted) {
        state = ShopState(
          prices: _parsePrices(results[0]),
          games: _parseGames(results[1]),
          week: WeekTickets.fromJson(results[2]),
          loaded: true,
        );
      }
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el Yatai ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    if (!mounted) return;

    _watches.add(
      _backend.watch('/shop/prices', token: _session.freshToken).listen((
        event,
      ) {
        _pricesTree = applyDatabaseEvent(_pricesTree, event);
        if (mounted) state = state.copyWith(prices: _parsePrices(_pricesTree));
      }, onError: (Object e) => debugPrint('Ibasho: stream de precios ($e)')),
    );

    _watches.add(
      _backend.watch('/users/$_me/games', token: _session.freshToken).listen((
        event,
      ) {
        _gamesTree = applyDatabaseEvent(_gamesTree, event);
        if (mounted) state = state.copyWith(games: _parseGames(_gamesTree));
      }, onError: (Object e) => debugPrint('Ibasho: stream de juegos ($e)')),
    );

    _watches.add(
      _backend.watch('/users/$_me/shop/week', token: _session.freshToken).listen((
        event,
      ) {
        if (event.path != '/') return;
        if (mounted) state = state.copyWith(week: WeekTickets.fromJson(event.data));
      }, onError: (Object e) => debugPrint('Ibasho: stream de la semana ($e)')),
    );
  }

  static Map<String, int> _parsePrices(Object? raw) {
    if (raw is! Map) return const <String, int>{};
    final out = <String, int>{};
    for (final entry in raw.entries) {
      final price = entry.value;
      if (price is num) out['${entry.key}'] = price.toInt();
    }
    return Map<String, int>.unmodifiable(out);
  }

  static Map<String, GameInstall> _parseGames(Object? raw) {
    if (raw is! Map) return const <String, GameInstall>{};
    final out = <String, GameInstall>{};
    for (final entry in raw.entries) {
      final install = GameInstall.fromJson(entry.value);
      if (install != null) out['${entry.key}'] = install;
    }
    return Map<String, GameInstall>.unmodifiable(out);
  }

  /// Compra un articulo. Escritura multi-ruta unica: el recibo, y ademas las
  /// monedas (si el precio no es 0), la despensa o el juego regalado, segun
  /// el articulo. Lanza [ShopException] si no se puede pedir.
  Future<void> buy(ShopItem item, int qty) async {
    if (qty < 1 || qty > maxPurchaseQty) {
      throw const ShopException(ShopFailure.rejected);
    }
    final food = item.food;
    if (food != null && !_unlockedFoodsOf().contains(food)) {
      throw const ShopException(ShopFailure.foodLocked);
    }
    final gameId = item.gameId;
    if (gameId != null && state.games.containsKey(gameId)) {
      throw const ShopException(ShopFailure.alreadyOwned);
    }
    final ticket = item.ticket;
    if (ticket != null && qty > state.ticketsLeftThisWeek(ticket)) {
      throw const ShopException(ShopFailure.weeklyLimit);
    }
    final price = state.prices[item.id];
    if (price == null) throw const ShopException(ShopFailure.noPrice);
    final cost = price * qty;
    if (price > 0 && _coinsOf() < cost) {
      throw const ShopException(ShopFailure.insufficientCoins);
    }

    final writes = <String, Object?>{
      'users/$_me/shop/last': {
        'item': item.id,
        'qty': qty,
        'at': serverTimestamp,
      },
      if (price > 0) 'users/$_me/coins': _coinsOf() - cost,
      if (food != null)
        'users/$_me/pantry/${food.name}': _pantryQtyOf(food) + qty,
      if (gameId != null)
        'users/$_me/games/$gameId': {
          'state': GameState.gift.name,
          'at': serverTimestamp,
        },
      if (ticket != null) ...<String, Object?>{
        'users/$_me/tickets/${ticket.name}': _ticketsOf(ticket) + qty,
        'users/$_me/shop/week':
            (state.week ?? WeekTickets(week: gachaWeek())).afterBuying(ticket, qty),
      },
      // Señal para la mision «compra algo en el Yatai» (`missions.dart`).
      'users/$_me/missions/signal/buy': {'at': serverTimestamp},
    };

    state = state.copyWith(busy: true);
    try {
      await _backend.merge('/', writes, idToken: await _session.freshToken());
    } on IbashoException catch (e) {
      throw ShopException(
        e.failure == IbashoFailure.network
            ? ShopFailure.network
            : ShopFailure.rejected,
      );
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Depuracion (solo admin, y solo en su cuenta): pone un juego en el
  /// estado que se pida sin pasar por el Yatai, o lo quita con `null`. Las
  /// reglas rechazan esto a cualquier otra cuenta.
  Future<bool> debugSetGame(String gameId, GameState? to) async {
    if (!_session.state.isAdmin) return false;
    state = state.copyWith(busy: true);
    try {
      final path = '/users/$_me/games/$gameId';
      final token = await _session.freshToken();
      if (to == null) {
        await _backend.remove(path, idToken: token);
      } else {
        await _backend.write(
          path,
          {'state': to.name, 'at': serverTimestamp},
          idToken: token,
        );
      }
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cambiar el juego ($e)');
      return false;
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Desenvuelve un regalo: pasa un juego de `gift` a `open`. No toca `at`.
  Future<bool> unwrap(String gameId) async {
    final install = state.games[gameId];
    if (install == null || install.state != GameState.gift) return false;
    try {
      await _backend.write(
        '/users/$_me/games/$gameId/state',
        GameState.open.name,
        idToken: await _session.freshToken(),
      );
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido desenvolver ($e)');
      return false;
    }
  }
}
