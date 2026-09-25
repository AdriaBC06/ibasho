// Ibasho — tirar del gacha contra el backend falso: tiradas de 1 a 9 bolas y
// los tickets, que nunca bajan de 0.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/state/gacha.dart';
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
  test('solo hay tiradas de 1 a 9 bolas y la de 11', () {
    expect([for (var n = 0; n <= 12; n++) if (isPullSize(n)) n], [1, 2, 3, 4, 5, 6, 7, 8, 9, 11]);
    expect(pullCost(5), 5);
    expect(pullCost(multiPullBalls), multiPullCost);
  });

  test('gastar el ultimo ticket deja 0, no -1', () async {
    final backend = FakeIbashoBackend();
    backend.seed('/users/${backend.uid}/tickets', {'gachaken': 3, 'kinken': 0});
    final container = await _account(backend);
    addTearDown(container.dispose);

    final gacha = container.read(gachaProvider.notifier);
    await _until(() => container.read(gachaProvider).ticketsOf(TicketKind.gachaken) == 3);

    final result = await gacha.pull(TicketKind.gachaken, balls: 3);
    expect(result.balls, hasLength(3));
    // Deja que llegue el eco del stream de tickets.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final state = container.read(gachaProvider);
    expect(state.tickets[TicketKind.gachaken], 0);
    expect(state.ticketsOf(TicketKind.gachaken), 0);
    expect(state.totalBalls, 3);
    expect(backend.peek('/users/${backend.uid}/tickets/gachaken'), 0);

    await expectLater(
      gacha.pull(TicketKind.gachaken),
      throwsA(isA<PullException>().having((e) => e.failure, 'failure', PullFailure.noTickets)),
    );
  });

  test('ticketsOf nunca devuelve un negativo', () {
    const state = GachaState(tickets: {TicketKind.gachaken: -1});
    expect(state.ticketsOf(TicketKind.gachaken), 0);
  });
}
