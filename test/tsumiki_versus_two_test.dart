// Ibasho — Tsumiki versus con dos cuentas sobre la misma base: lo que hace
// una le llega a la otra de verdad, de la invitación a la revancha.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/tsumiki_versus.dart';
import 'package:ibasho/games/tsumiki/tsumiki_versus.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/state/tsumiki_versus.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

/// Una cuenta: su doble del backend, su sesión y su controlador.
class _Player {
  _Player(this.backend)
      : container = ProviderContainer(
          overrides: [
            backendProvider.overrideWithValue(backend),
            secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
            settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
            initialPreferencesProvider.overrideWithValue(const Preferences()),
            batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
          ],
        );

  final FakeIbashoBackend backend;
  final ProviderContainer container;
  late final TsumikiVersusController vs;
  final List<TsumikiVsEvent> got = <TsumikiVsEvent>[];

  String get uid => backend.uid;

  Future<void> start() async {
    await container.read(sessionProvider.notifier).restore();
    vs = TsumikiVersusController(backend: backend, session: container.read(sessionProvider.notifier));
    vs.incoming.listen(got.add);
  }

  void dispose() {
    vs.dispose();
    container.dispose();
  }
}

void main() {
  late _Player adri;
  late _Player mireia;

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    final base = FakeIbashoBackend()..seed('/allowlist/$kMireiaUid/mustChangePassword', false);
    adri = _Player(base);
    mireia = _Player(base.sharing(uid: kMireiaUid, username: 'mireia'));
    await adri.start();
    await mireia.start();
  });

  tearDown(() {
    adri.dispose();
    mireia.dispose();
  });

  /// Lo que le ha llegado a Mireia a su buzón, como lo ve su canal.
  Future<List<TsumikiInvite>> mireiaInbox() async {
    final sub = mireia.container.listen(tsumikiInvitesProvider, (_, _) {});
    addTearDown(sub.close);
    await settle();
    return mireia.container.read(tsumikiInvitesProvider).valueOrNull ?? const <TsumikiInvite>[];
  }

  /// Los dos dentro de la misma partida.
  Future<TsumikiRoom> playing() async {
    expect(await adri.vs.invite(kMireiaUid), isTrue);
    await settle();
    final inbox = await mireiaInbox();
    expect(inbox.single.from, adri.uid);
    expect(await mireia.vs.accept(inbox.single), isTrue);
    await settle();
    expect(adri.vs.state.phase, TsumikiVsPhase.playing);
    expect(mireia.vs.state.phase, TsumikiVsPhase.playing);
    return adri.vs.state.room!;
  }

  test('una partida entera: piezas, filas grises, trabas, final y marcador', () async {
    final room = await playing();
    expect(mireia.vs.state.room!.id, room.id);
    expect(room.side(adri.uid), isNot(room.side(kMireiaUid)));

    // Los dos con la misma semilla: las mismas piezas en el mismo orden.
    final mine = TsumikiDuel(seed: room.seed, side: room.side(adri.uid))..game.start();
    final hers = TsumikiDuel(seed: mireia.vs.state.room!.seed, side: room.side(kMireiaUid))..game.start();
    expect(hers.game.current!.type, mine.game.current!.type);
    expect(hers.game.next.take(5).toList(), mine.game.next.take(5).toList());

    // Le mando tres filas grises y una niebla: le llega cada cosa una vez.
    await adri.vs.send(const TsumikiVsEvent.attack(TsumikiAttack(3, 4)));
    await adri.vs.send(const TsumikiVsEvent.sabotage(TsumikiSabotage.fog));
    await settle();
    expect(adri.got, isEmpty);
    expect(mireia.got.length, 2);
    for (final e in mireia.got) {
      if (e.attack case final a?) hers.receive(a);
      if (e.sabotage case final s?) hers.suffer(s);
    }
    expect(hers.game.pendingGarbage, 3);
    expect(hers.foggy, isTrue);

    // Lo que publica cada uno lo ve el otro.
    await mireia.vs.publish(board: hers.game.encodeBoard(), lines: 0, sent: 0, meter: hers.meter, fx: hers.active.keys.toSet());
    await adri.vs.publish(board: mine.game.encodeBoard(), lines: 2, sent: 3, meter: 40, fx: const {});
    await settle();
    expect(adri.vs.state.room!.seat(kMireiaUid).fx, {TsumikiSabotage.fog});
    expect(mireia.vs.state.room!.seat(adri.uid).sent, 3);

    // Mireia apila en el centro hasta llegar arriba.
    for (var i = 0; i < 200 && !hers.game.isOver; i++) {
      hers.game.hardDrop();
      hers.game.tick(1);
    }
    expect(hers.game.isOver, isTrue);
    expect(await mireia.vs.lose(lines: hers.game.lines, sent: hers.sent), isTrue);
    await settle();

    for (final p in [adri, mireia]) {
      expect(p.vs.state.phase, TsumikiVsPhase.done);
      expect(p.vs.state.winner, adri.uid);
      expect(p.vs.state.room!.end, TsumikiEnd.top);
    }

    // El mismo marcador y el mismo historial, cada uno desde su lado.
    final adriScore = await adri.container.read(tsumikiScoreProvider(kMireiaUid).future);
    final herScore = await mireia.container.read(tsumikiScoreProvider(adri.uid).future);
    expect((adriScore.mine, adriScore.theirs), (1, 0));
    expect((herScore.mine, herScore.theirs), (0, 1));
    final history = await mireia.container.read(tsumikiHistoryProvider(adri.uid).future);
    expect(history.single.winner, adri.uid);
    expect(history.single.end, TsumikiEnd.top);
  });

  test('revancha: la pide uno, la acepta el otro y empieza otra partida', () async {
    final first = await playing();
    await adri.vs.lose(lines: 0, sent: 0);
    await settle();
    expect(mireia.vs.state.winner, kMireiaUid);

    expect(await mireia.vs.rematch(), isTrue);
    await settle();
    expect(adri.vs.state.rematchOffered, isTrue);
    expect(await adri.vs.rematch(), isTrue);
    await settle();

    final second = adri.vs.state.room!;
    expect(second.id, isNot(first.id));
    expect(mireia.vs.state.room!.id, second.id);
    expect(adri.vs.state.phase, TsumikiVsPhase.playing);
    expect(mireia.vs.state.phase, TsumikiVsPhase.playing);

    // Gana Adri la segunda: 1–1 para los dos.
    await mireia.vs.lose(lines: 0, sent: 0);
    await settle();
    final score = await adri.container.read(tsumikiScoreProvider(kMireiaUid).future);
    expect((score.mine, score.theirs), (1, 1));
  });

  test('si una cierra a media partida, la otra gana por abandono', () async {
    await playing();
    await mireia.vs.close(lines: 4, sent: 1);
    await settle();
    expect(adri.vs.state.phase, TsumikiVsPhase.done);
    expect(adri.vs.state.winner, adri.uid);
    expect(adri.vs.state.room!.end, TsumikiEnd.leave);
  });
}
