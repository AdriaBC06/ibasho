// Ibasho — el controlador de misiones: recuentos semanales y repetibles.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/backend/missions.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

Future<ProviderContainer> _account(FakeIbashoBackend backend) async {
  final container = ProviderContainer(overrides: [
    backendProvider.overrideWithValue(backend),
    secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
    settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
    initialPreferencesProvider.overrideWithValue(const Preferences()),
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
  test('las partidas suman al recuento y cada 5 se cobra un gachaken, hasta 3', () async {
    final backend = FakeIbashoBackend();
    final week = gachaWeek();
    backend
      ..seed('/users/${backend.uid}/tickets', {'gachaken': 2, 'kinken': 0})
      ..seed('/users/${backend.uid}/missions/tally/play', {'week': week, 'n': 13, 'at': 1});
    final container = await _account(backend);
    addTearDown(container.dispose);
    container.read(gachaProvider);
    final missions = container.read(missionsProvider.notifier);

    // Sin esperar a la primera lectura: la señal espera ella sola.
    await missions.mark(MissionEvent.play);
    await missions.mark(MissionEvent.play);
    expect(container.read(missionsProvider).tally(MissionEvent.play, week), 15);
    expect(await backend.read('/users/${backend.uid}/missions/tally/play/n', idToken: ''), 15);
    expect(container.read(missionsProvider).doneThisWeek(MissionEvent.play, week), isTrue);

    await _until(() => container.read(gachaProvider).ticketsOf(TicketKind.gachaken) == 2);
    for (var i = 1; i <= repeatMissionTimes; i++) {
      expect(await missions.claimRepeat(RepeatMission.play, week), isTrue);
      await _until(() => container.read(gachaProvider).ticketsOf(TicketKind.gachaken) == 2 + i);
    }
    expect(await missions.claimRepeat(RepeatMission.play, week), isFalse);
    expect(await backend.read('/users/${backend.uid}/tickets/gachaken', idToken: ''), 5);
    expect(await backend.read('/users/${backend.uid}/missions/repeat/$week/play', idToken: ''), 3);
  });

  test('el recuento de la semana pasada vuelve a empezar', () async {
    final backend = FakeIbashoBackend();
    final week = gachaWeek();
    backend.seed('/users/${backend.uid}/missions/tally/feed', {'week': week - 1, 'n': 9, 'at': 1});
    final container = await _account(backend);
    addTearDown(container.dispose);
    final missions = container.read(missionsProvider.notifier);
    await missions.mark(MissionEvent.feed);
    expect(await backend.read('/users/${backend.uid}/missions/tally/feed', idToken: ''),
        containsPair('week', week));
    expect(await backend.read('/users/${backend.uid}/missions/tally/feed/n', idToken: ''), 1);
    expect(container.read(missionsProvider).canClaimRepeat(RepeatMission.feed, week), isFalse);
  });
}
