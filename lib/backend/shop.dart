// Ibasho — el catalogo del Yatai y lo que se guarda de una compra.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'tama.dart';

/// Unidades del stock inicial de una comida de serie. Las reglas exigen
/// exactamente este numero la primera vez que se lee.
const int starterFoodUnits = 5;

/// Cantidad maxima que se puede comprar de una tacada. Las reglas exigen lo
/// mismo.
const int maxPurchaseQty = 99;

/// Tope de unidades por comida en la despensa. Las reglas exigen lo mismo.
const int pantryMaxUnits = 9999;

/// Las tres secciones del Yatai.
enum ShopSection { games, tamas, gacha }

/// Un articulo del catalogo. El catalogo entero es codigo, no datos de la
/// base: solo el precio de cada uno vive en `/shop/prices/{id}`.
@immutable
class ShopItem {
  const ShopItem({
    required this.id,
    required this.section,
    this.food,
    this.gameId,
  });

  /// Clave de `/shop/prices/{id}` y de `shop/last.item`. Para un juego,
  /// `'game_' + gameId`; para una comida, `'food_' + food.name`.
  final String id;

  final ShopSection section;

  /// Solo si [section] es [ShopSection.tamas].
  final TamaFood? food;

  /// Solo si [section] es [ShopSection.games]. Coincide con la clave de
  /// `/users/{cuenta}/games/{gameId}`.
  final String? gameId;

  /// Si hoy se puede comprar, dado el conjunto de comidas desbloqueadas. Un
  /// articulo de comida bloqueada se ensena igual en la rejilla, hundido y
  /// con un candado, pero no se puede pedir.
  bool buyableWith(Set<TamaFood> unlockedFoods) =>
      food == null || unlockedFoods.contains(food);

  static String idForFood(TamaFood food) => 'food_${food.name}';
  static String idForGame(String gameId) => 'game_$gameId';
}

/// El catalogo del Yatai, fijo en el codigo. Los juegos y una comida por
/// cada [TamaFood]: las que no vienen de serie salen bloqueadas hasta que un
/// checkpoint futuro las desbloquee.
final List<ShopItem> shopCatalog = List<ShopItem>.unmodifiable(<ShopItem>[
  const ShopItem(id: 'game_minesweeper', section: ShopSection.games, gameId: 'minesweeper'),
  const ShopItem(id: 'game_tsumiki', section: ShopSection.games, gameId: 'tsumiki'),
  const ShopItem(id: 'game_nihongo', section: ShopSection.games, gameId: 'nihongo'),
  for (final food in TamaFood.values)
    ShopItem(id: ShopItem.idForFood(food), section: ShopSection.tamas, food: food),
]);

/// `/users/{cuenta}/shop/last`: el recibo de la ultima compra.
///
/// Sirve para que las reglas comprueben que la escritura de al lado (las
/// monedas, la despensa o el juego) va acompañada de una compra de verdad,
/// hecha en ese mismo instante. No se guarda un historial: solo el ultimo.
@immutable
class Receipt {
  const Receipt({required this.item, required this.qty, required this.at});

  final String item;
  final int qty;
  final DateTime at;

  static Receipt? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final item = raw['item'];
    final qty = raw['qty'];
    final at = raw['at'];
    if (item is! String || qty is! num || at is! num) return null;
    return Receipt(
      item: item,
      qty: qty.toInt(),
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    );
  }

  Map<String, Object?> toJson() => {
        'item': item,
        'qty': qty,
        'at': at.millisecondsSinceEpoch,
      };
}

/// En que estado esta un juego comprado.
enum GameState {
  /// Recien comprado: en la rejilla se ensena como un regalo envuelto.
  gift,

  /// Ya desenvuelto: es un canal normal.
  open;

  static GameState byName(Object? raw) =>
      values.firstWhere((s) => s.name == raw, orElse: () => GameState.gift);
}

/// `/users/{cuenta}/games/{gameId}`: un juego comprado.
@immutable
class GameInstall {
  const GameInstall({required this.state, required this.at});

  final GameState state;
  final DateTime at;

  bool get isGift => state == GameState.gift;

  static GameInstall? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! num) return null;
    return GameInstall(
      state: GameState.byName(raw['state']),
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    );
  }

  Map<String, Object?> toJson() => {
        'state': state.name,
        'at': at.millisecondsSinceEpoch,
      };

  GameInstall copyWith({GameState? state}) =>
      GameInstall(state: state ?? this.state, at: at);
}
