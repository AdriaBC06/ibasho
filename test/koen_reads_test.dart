// Ibasho — Tama Kōen: cuánto se lee al abrir el parque con 20 amigos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/koen.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

void main() {
  test('abrir el parque con 20 amigos, todos con 3 Tamas, son 61 lecturas pequeñas', () async {
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

    // Un Tama vestido entero, para que las fichas pesen lo que pesarían.
    final look = TamaLook(
      parts: {for (final p in TamaPart.values) p: 7},
      color: '#5BC8F5',
      outfit: const TamaOutfit(hat: 'kabuto_gold', accessories: ['dollar_chain', 'ribbon_red', 'star_wand']),
    );
    final friends = [for (var i = 0; i < 20; i++) 'amigo-${i.toString().padLeft(2, '0')}'];
    for (final f in friends) {
      for (var s = 0; s < koenSlots; s++) {
        final tama = Tama(
          id: '$f-tama-$s-0123456789',
          creator: f,
          keeper: f,
          name: 'Tama $s',
          look: look,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );
        backend.seed('/users/$f/koen/park/$s', KoenCard.ofTama(tama, holder: f, slot: s, at: 1).toJson());
      }
      backend
        ..seed('/users/$f/friends', {
          me: {'since': 1},
          for (final o in friends)
            if (o != f) o: {'since': 1},
        })
        ..seed('/users/$f/koen/friends/$me/p', 12);
    }

    backend.reads.clear();
    await container.read(koenProvider.notifier).refresh(friendIds: friends, tamas: const []);
    final state = container.read(koenProvider);
    expect(state.friends.length, 20);
    expect(state.links.length, 20 * 19 ~/ 2);

    // La propia, un parque por amigo, y de los que tienen Tamas su lista de
    // amigos (solo las claves) y lo que llevan sumado con la cuenta.
    final reads = [...backend.reads];
    printOnFailure(reads.join('\n'));
    expect(reads.length, 1 + 20 + 20 + 20);
    var bytes = 0;
    for (final path in reads) {
      final shallow = path.endsWith('/friends');
      final value = await backend.read(path, idToken: '', shallow: shallow);
      bytes += utf8.encode(jsonEncode(shallow && value is Map ? {for (final k in value.keys) k: true} : value)).length;
    }
    // Unos 40 KB: en el plan gratis (10 GB al mes) da para miles de visitas
    // al día.
    printOnFailure('$bytes bytes');
    expect(bytes, lessThan(60 * 1024));
  });
}
