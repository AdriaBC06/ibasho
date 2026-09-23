// Ibasho — el Yatai: catalogo, modelos y la escritura que monta una compra.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/shop.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/state/shop.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

/// Una cuenta sin interfaz sobre un backend falso, como en friends_test.dart.
Future<ProviderContainer> _account(FakeIbashoBackend backend) async {
  final container = ProviderContainer(overrides: [
    backendProvider.overrideWithValue(backend),
    secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
    settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
    initialPreferencesProvider.overrideWithValue(const Preferences()),
    batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
  ]);
  await container.read(sessionProvider.notifier).restore();
  return container;
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('catalogo', () {
    test('un articulo por juego y uno por cada comida', () {
      expect(
        shopCatalog
            .where((i) => i.section == ShopSection.games && i.koroTier == null)
            .map((i) => i.gameId),
        ['minesweeper', 'tsumiki', 'nihongo'],
      );
      expect(
        shopCatalog.where((i) => i.koroTier != null).map((i) => i.koroTier),
        [1, 2, 3, 4],
      );
      final foods = shopCatalog.where((i) => i.section == ShopSection.tamas).toList();
      expect(foods.length, TamaFood.values.length);
      expect(foods.map((i) => i.food).toSet(), TamaFood.values.toSet());
    });

    test('los ids siguen el patron game_/food_', () {
      final minesweeper =
          shopCatalog.firstWhere((i) => i.section == ShopSection.games);
      expect(minesweeper.id, 'game_minesweeper');
      expect(minesweeper.gameId, 'minesweeper');

      final cookie = shopCatalog.firstWhere((i) => i.food == TamaFood.cookie);
      expect(cookie.id, 'food_cookie');
      expect(cookie.id, ShopItem.idForFood(TamaFood.cookie));
    });

    test('solo se puede comprar comida desbloqueada', () {
      final cookie = shopCatalog.firstWhere((i) => i.food == TamaFood.cookie);
      final mochi = shopCatalog.firstWhere((i) => i.food == TamaFood.mochi);
      final unlocked = {TamaFood.cookie, TamaFood.candy};
      expect(cookie.buyableWith(unlocked), isTrue);
      expect(mochi.buyableWith(unlocked), isFalse);
      // Un juego no depende de la despensa.
      final minesweeper =
          shopCatalog.firstWhere((i) => i.section == ShopSection.games);
      expect(minesweeper.buyableWith(const {}), isTrue);
    });
  });

  group('modelos', () {
    test('Receipt va y vuelve de json', () {
      final at = DateTime.fromMillisecondsSinceEpoch(1234567);
      final receipt = Receipt(item: 'food_cookie', qty: 5, at: at);
      final back = Receipt.fromJson(receipt.toJson());
      expect(back?.item, 'food_cookie');
      expect(back?.qty, 5);
      expect(back?.at, at);
    });

    test('Receipt.fromJson rechaza lo que no tiene forma', () {
      expect(Receipt.fromJson(null), isNull);
      expect(Receipt.fromJson(<String, Object?>{'item': 'x'}), isNull);
    });

    test('GameInstall va y vuelve de json', () {
      final at = DateTime.fromMillisecondsSinceEpoch(999);
      final install = GameInstall(state: GameState.gift, at: at);
      final back = GameInstall.fromJson(install.toJson());
      expect(back?.state, GameState.gift);
      expect(back?.at, at);
      expect(back?.copyWith(state: GameState.open).state, GameState.open);
    });
  });

  group('ShopController.buy', () {
    test('comprar comida con saldo escribe recibo, monedas y despensa', () async {
      final backend = FakeIbashoBackend();
      backend.seed('/shop/prices', {'food_cookie': 3, 'food_candy': 3});
      backend.seed('/users/${backend.uid}/coins', 100);
      backend.seed('/users/${backend.uid}/pantry/cookie', 5);
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(shopProvider).loaded);
      await _until(() => container.read(coinsProvider) == 100);
      await _until(() => container.read(pantryProvider).containsKey(TamaFood.cookie));

      final item = shopCatalog.firstWhere((i) => i.food == TamaFood.cookie);
      await container.read(shopProvider.notifier).buy(item, 5);

      final me = backend.uid;
      final write = backend.writes.last;
      expect(write.$1, '/');
      final payload = write.$2! as Map<String, Object?>;
      expect(payload['users/$me/coins'], 85);
      expect(payload['users/$me/pantry/cookie'], 10);
      final receipt = payload['users/$me/shop/last']! as Map<String, Object?>;
      expect(receipt['item'], 'food_cookie');
      expect(receipt['qty'], 5);
    });

    test('un juego a precio 0 no lleva monedas en la escritura', () async {
      final backend = FakeIbashoBackend();
      backend.seed('/shop/prices', {'game_minesweeper': 0});
      backend.seed('/users/${backend.uid}/coins', 0);
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(shopProvider).loaded);

      final item = shopCatalog.firstWhere((i) => i.section == ShopSection.games);
      await container.read(shopProvider.notifier).buy(item, 1);

      final me = backend.uid;
      final payload = backend.writes.last.$2! as Map<String, Object?>;
      expect(payload.containsKey('users/$me/coins'), isFalse);
      final install = payload['users/$me/games/minesweeper']! as Map<String, Object?>;
      expect(install['state'], 'gift');
    });

    test('sin saldo suficiente lanza ShopException', () async {
      final backend = FakeIbashoBackend();
      backend.seed('/shop/prices', {'food_cookie': 3});
      backend.seed('/users/${backend.uid}/coins', 2);
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(shopProvider).loaded);
      await _until(() => container.read(coinsProvider) == 2);

      final item = shopCatalog.firstWhere((i) => i.food == TamaFood.cookie);
      await expectLater(
        container.read(shopProvider.notifier).buy(item, 5),
        throwsA(isA<ShopException>().having(
          (e) => e.failure,
          'failure',
          ShopFailure.insufficientCoins,
        )),
      );
    });

    test('una comida que antes salia bloqueada ya se puede comprar', () async {
      final backend = FakeIbashoBackend();
      backend.seed('/shop/prices', {'food_mochi': 3});
      backend.seed('/users/${backend.uid}/coins', 100);
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(shopProvider).loaded);
      await _until(() => container.read(coinsProvider) == 100);

      final item = shopCatalog.firstWhere((i) => i.food == TamaFood.mochi);
      await container.read(shopProvider.notifier).buy(item, 1);
      await _until(() => container.read(pantryProvider)[TamaFood.mochi] == 1);
    });

    test('sin precio cargado lanza ShopException.noPrice', () async {
      final backend = FakeIbashoBackend();
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(shopProvider).loaded);

      final item = shopCatalog.firstWhere((i) => i.food == TamaFood.cookie);
      await expectLater(
        container.read(shopProvider.notifier).buy(item, 1),
        throwsA(isA<ShopException>().having(
          (e) => e.failure,
          'failure',
          ShopFailure.noPrice,
        )),
      );
    });
  });

  group('ShopController.debugSetGame', () {
    test('un admin se da un juego envuelto, lo abre y lo quita', () async {
      final backend = FakeIbashoBackend();
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(shopProvider).loaded);
      final shop = container.read(shopProvider.notifier);

      expect(await shop.debugSetGame('minesweeper', GameState.gift), isTrue);
      await _until(() => container.read(shopProvider).games.isNotEmpty);
      expect(container.read(shopProvider).games['minesweeper']?.state, GameState.gift);

      expect(await shop.debugSetGame('minesweeper', GameState.open), isTrue);
      await _until(() =>
          container.read(shopProvider).games['minesweeper']?.state == GameState.open);
      expect(container.read(shopProvider).games['minesweeper']?.state, GameState.open);

      expect(await shop.debugSetGame('minesweeper', null), isTrue);
      await _until(() => container.read(shopProvider).games.isEmpty);
      expect(container.read(shopProvider).games, isEmpty);
    });

    test('una cuenta normal no puede', () async {
      final backend = FakeIbashoBackend(uid: 'uid-ana', username: 'ana', isAdmin: false);
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(shopProvider).loaded);

      expect(
        await container.read(shopProvider.notifier).debugSetGame('minesweeper', GameState.open),
        isFalse,
      );
    });
  });

  group('PantryController', () {
    test('pide el stock inicial de las comidas de serie', () async {
      final backend = FakeIbashoBackend();
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(pantryProvider).length == 2);

      final state = container.read(pantryProvider);
      expect(state[TamaFood.cookie], starterFoodUnits);
      expect(state[TamaFood.candy], starterFoodUnits);
    });

    test('consume resta una unidad y devuelve false sin stock', () async {
      final backend = FakeIbashoBackend();
      backend.seed('/users/${backend.uid}/pantry/cookie', 1);
      final container = await _account(backend);
      addTearDown(container.dispose);
      await _until(() => container.read(pantryProvider)[TamaFood.cookie] == 1);

      final notifier = container.read(pantryProvider.notifier);
      expect(await notifier.consume(TamaFood.cookie), isTrue);
      expect(container.read(pantryProvider)[TamaFood.cookie], 0);
      expect(await notifier.consume(TamaFood.cookie), isFalse);
    });
  });
}
