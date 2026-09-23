// Ibasho — cada bola del pinball se guarda: baja de la partida, deja su
// premio en la coleccion y sube el Catalogo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/backdrops.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/backend/gacha_music.dart';
import 'package:ibasho/backend/gacha_prizes.dart';
import 'package:ibasho/backend/prizes.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

/// Una cuenta sin interfaz sobre un backend falso, como en shop_test.dart.
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
  group('el sorteo del premio', () {
    test('sale uno de la categoria y la rareza de la bola', () {
      final random = math.Random(1);
      for (var i = 0; i < 50; i++) {
        final item = prizeItem(
          rollGachaPrize(GachaCategory.hats, Rarity.ur, random),
        )!;
        expect(item.prize.rarity, Rarity.ur);
        expect(item.prize.slot, PrizeSlot.head);
      }
    });

    test('la dirigida da uno que no se tenga mientras quede alguno', () {
      final all = prizeItemsOf(GachaCategory.accessories, Rarity.ssr);
      final owned = {for (final i in all.skip(1)) i.key};
      final random = math.Random(2);
      for (var i = 0; i < 20; i++) {
        expect(
          rollGachaPrize(
            GachaCategory.accessories,
            Rarity.ssr,
            random,
            owned: owned,
            fresh: true,
          ),
          all.first.key,
        );
      }
      // Con todos, sale repetido.
      final every = {for (final i in all) i.key};
      expect(
        every,
        contains(
          rollGachaPrize(
            GachaCategory.accessories,
            Rarity.ssr,
            random,
            owned: every,
            fresh: true,
          ),
        ),
      );
    });

    // La 0.6.0 no daba nada en estos dos agujeros: la bola se gastaba sin
    // premio.
    test('los fondos y las musicas dan premio en todas las rarezas', () {
      final random = math.Random(3);
      for (final rarity in Rarity.values) {
        for (var i = 0; i < 20; i++) {
          final bg = rollGachaPrize(GachaCategory.backdrops, rarity, random);
          expect(backdropByKey(bg)?.rarity, rarity, reason: '$bg');
          final mu = rollGachaPrize(GachaCategory.music, rarity, random);
          expect(gachaMusicByKey(mu), isNotNull, reason: '$mu');
          expect(gachaPrizeCategory(mu), GachaCategory.music);
        }
      }
    });

    test('sin musica SSR, la bola SSR da la de la rareza de debajo', () {
      expect(gachaPrizeKeysOf(GachaCategory.music, Rarity.ssr), isEmpty);
      expect(gachaPrizePool(GachaCategory.music, Rarity.ssr), ['mu_feria']);
    });

    test('todas las categorias y rarezas tienen premio', () {
      for (final category in GachaCategory.values) {
        for (final rarity in Rarity.values) {
          expect(
            gachaPrizePool(category, rarity),
            isNotEmpty,
            reason: '$category $rarity',
          );
        }
      }
    });
  });

  group('las jugadas', () {
    late FakeIbashoBackend backend;
    late ProviderContainer container;

    setUp(() async {
      backend = FakeIbashoBackend(tamas: [sampleTama()], profileTamaId: sampleTama().id)
        ..seed('/users/${FakeIbashoBackend().uid}/gacha', {
          'balls': {'n': 0, 'r': 0, 'sr': 0, 'ssr': 0, 'ur': 0, 'mu': 0},
          'play': {
            'at': 1,
            'count': 3,
            'balls': {'n': 2},
            'marked': {
              'hats': {'ssr': 1},
            },
          },
          'wish': {'category': 'accessories', 'rarity': 'sr', 'count': 68},
        })
        ..seed('/users/${FakeIbashoBackend().uid}/prizes', {'cap_red': 1});
      container = await _account(backend);
      await _until(() => container.read(gachaProvider).loaded);
    });

    tearDown(() => container.dispose());

    Object? at(String path) => backend.peek('/users/${backend.uid}/$path');

    test('una bola con premio lo suma y baja la partida', () async {
      final gacha = container.read(gachaProvider.notifier);
      final wish = await gacha.playTurn(index: 0, ball: const GachaBall(Rarity.n), prize: 'cap_red');
      expect(wish, isFalse);
      expect(at('prizes/cap_red'), 2);
      expect(at('gacha/play/balls/n'), 1);
      expect(at('gacha/play/done'), 1);
      expect(at('gacha/wish/count'), 69);
      expect((at('gacha/turn')! as Map)['prize'], 'cap_red');
    });

    test('en la bola 70 llega la dirigida del deseo', () async {
      final gacha = container.read(gachaProvider.notifier);
      await gacha.playTurn(index: 0, ball: const GachaBall(Rarity.n));
      final wish = await gacha.playTurn(index: 1, ball: const GachaBall(Rarity.n));
      expect(wish, isTrue);
      expect(at('gacha/wish/count'), 0);
      expect(at('gacha/marked/accessories/sr'), 1);
      expect(at('gacha/play/balls/n'), isNull);
    });

    test('la dirigida baja de lo cargado en su categoria', () async {
      final gacha = container.read(gachaProvider.notifier);
      await gacha.playTurn(
        index: 0,
        ball: const GachaBall(Rarity.ssr, category: GachaCategory.hats),
        prize: 'crown_gold',
      );
      expect(at('gacha/play/marked/hats/ssr'), isNull);
      expect(at('prizes/crown_gold'), 1);
      expect((at('gacha/turn')! as Map)['category'], 'hats');
    });

    // En la 0.6.0 una musica ganada solo salia en la lista de Ajustes: ni en
    // el perfil ni como musica del menu hasta elegirla una vez.
    test('una musica ganada entra en la biblioteca', () async {
      container.read(musicLibraryProvider);
      await _until(() => container.read(musicLibraryProvider).loaded);
      await container.read(gachaProvider.notifier).playTurn(index: 0, ball: const GachaBall(Rarity.n), prize: 'mu_nana');
      await _until(() => at('music/unlocked/nana') == true);
      expect(at('prizes/mu_nana'), 1);
      expect(at('music/unlocked/nana'), isTrue);
      expect(container.read(musicLibraryProvider).unlocked, contains('nana'));
    });

    test('una jugada ya guardada no se repite', () async {
      final gacha = container.read(gachaProvider.notifier);
      await gacha.playTurn(index: 0, ball: const GachaBall(Rarity.n), prize: 'cap_red');
      final writes = backend.writes.length;
      await gacha.playTurn(index: 0, ball: const GachaBall(Rarity.n), prize: 'cap_red');
      expect(backend.writes.length, writes);
      expect(at('prizes/cap_red'), 2);
    });
  });
}
