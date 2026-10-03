// Ibasho — Tama Kōen: la racha de un dúo y sus premios, contra el backend falso.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/koen_duo.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/state/koen_duo.dart';
import 'package:ibasho/state/login_bonus.dart' show bonusDay;
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

void main() {
  test('apunta el día con los dos cuidados, sigue la racha y cobra lo que falta', () async {
    final backend = FakeIbashoBackend();
    final me = backend.uid;
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        initialPreferencesProvider.overrideWithValue(const Preferences()),
        batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).restore();

    final now = DateTime.now();
    Tama tama(String id, String creator, String carer, {bool petted = true}) => Tama(
      id: id,
      creator: creator,
      keeper: creator,
      carer: carer,
      name: id,
      care: TamaCare(lastFed: now, lastPetted: petted ? now : null),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final duo = KoenDuo(me: me, friend: 'zz-amigo', mine: [tama('a', me, 'zz-amigo')], theirs: [tama('b', 'zz-amigo', me)]);
    final today = bonusDay();
    backend
      ..seed('/koen/${duo.key}', {
        'a': duo.a,
        'b': 'zz-amigo',
        'streak': {'count': 6, 'day': today - 1, 'best': 6},
      })
      ..seed('/users/$me/koen/duos/${duo.key}/3', true);

    final controller = KoenDuosController(
      backend: backend,
      session: container.read(sessionProvider.notifier),
      coinsOf: () => 100,
      ticketsOf: (_) => 0,
    );
    addTearDown(controller.dispose);

    // Sin el mimo de uno de los dos, no cuenta.
    final early = await controller.tick(duo.copyWith(theirs: [tama('b', 'zz-amigo', me, petted: false)]));
    expect(early.streak, 0);
    expect(controller.state.data['zz-amigo']!.streak.count, 6);

    final tick = await controller.tick(duo);
    expect(tick.streak, 7);
    expect(tick.prizes.map((p) => p.days), [7]);
    final written = backend.writes.where((w) => w.$1 == '/').map((w) => w.$2! as Map).toList();
    expect(written.first['koen/${duo.key}/streak'], {'count': 7, 'day': today, 'best': 7});
    expect(written.first['koen/${duo.key}/slots'], {'left': 'a', 'right': 'b'});
    // Ya existía: no vuelve a escribir `a` y `b`.
    expect(written.first.containsKey('koen/${duo.key}/a'), isFalse);
    expect(written.last['users/$me/coins'], 120);
    expect(written.last['users/$me/koen/duos/${duo.key}/7'], true);

    // Otra vez el mismo día, nada.
    final again = await controller.tick(duo);
    expect(again.isEmpty, isTrue);
  });

  test('el accesorio de pareja: la forma, la mitad de cada lado y su cobro', () async {
    final backend = FakeIbashoBackend();
    final me = backend.uid;
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        initialPreferencesProvider.overrideWithValue(const Preferences()),
        batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.notifier).restore();

    Tama tama(String id, String creator, String carer) => Tama(
      id: id,
      creator: creator,
      keeper: creator,
      carer: carer,
      name: id,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    // La cuenta de prueba va antes que «zz-amigo»: su Tama va a la izquierda.
    final duo = KoenDuo(me: me, friend: 'zz-amigo', mine: [tama('a', me, 'zz-amigo')], theirs: [tama('b', 'zz-amigo', me)]);
    backend.seed('/koen/${duo.key}', {'a': duo.a, 'b': 'zz-amigo'});
    final owned = <String>{};
    final controller = KoenDuosController(
      backend: backend,
      session: container.read(sessionProvider.notifier),
      coinsOf: () => 0,
      ticketsOf: (_) => 0,
      owns: owned.contains,
    );
    addTearDown(controller.dispose);
    await controller.load([duo]);

    // Sin forma, no hay nada que cobrar.
    expect(await controller.claimCharm(duo), isNull);
    expect(await controller.chooseCharm(duo, KoenCharm.thread), isTrue);
    final code = koenCharmCode(duo.key);
    expect(backend.writes.last.$2, {'koen/${duo.key}/charm': {'shape': 'thread', 'code': code}});

    final fresh = duo.copyWith(data: controller.state.data['zz-amigo']);
    final key = await controller.claimCharm(fresh);
    expect(key, 'charm_thread_l_$code');
    final claim = backend.writes.last.$2! as Map;
    expect(claim['users/$me/prizes/$key'], 1);
    expect((claim['users/$me/koen/charm'] as Map)['pair'], duo.key);
    expect(claim['koen/${duo.key}/slots'], {'left': 'a', 'right': 'b'});

    // Si ya la tiene, no la vuelve a cobrar.
    owned.add(key!);
    final writes = backend.writes.length;
    expect(await controller.claimCharm(fresh), key);
    expect(backend.writes.length, writes);
  });
}
