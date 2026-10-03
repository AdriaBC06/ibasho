// Ibasho — Tsumiki versus contra el backend falso: invitar, responder, jugar,
// acabar, abandonos y el buzón.
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

const String friend = 'zz-bea';

void main() {
  late FakeIbashoBackend backend;
  late ProviderContainer container;
  late String me;
  late DateTime now;
  late TsumikiVersusController vs;

  String room() => '/tsumiki/${tsumikiPairId(me, friend)}';
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    backend = FakeIbashoBackend();
    me = backend.uid;
    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        secureStoreProvider.overrideWithValue(FakeSecureStore(session: backend.tokens)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        initialPreferencesProvider.overrideWithValue(const Preferences()),
        batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
      ],
    );
    await container.read(sessionProvider.notifier).restore();
    now = DateTime.now();
    vs = TsumikiVersusController(
      backend: backend,
      session: container.read(sessionProvider.notifier),
      clock: () => now,
    );
  });

  tearDown(() {
    vs.dispose();
    container.dispose();
  });

  /// La sala esperando a que Bea acepte, como la deja [invite].
  Future<TsumikiRoom> invited() async {
    expect(await vs.invite(friend), isTrue);
    await settle();
    return TsumikiRoom.fromJson(backend.peek('${room()}/live'))!;
  }

  /// Bea acepta.
  Future<void> beaAccepts() async {
    backend.seed('${room()}/live/state', 'play');
    backend.seed('${room()}/live/p/$friend', {'ping': 1, 'board': ''});
    await settle();
  }

  test('invitar crea la sala en espera y deja la invitación en su buzón', () async {
    final r = await invited();
    expect(r.host, me);
    expect(r.guest, friend);
    expect(r.state, TsumikiRoomState.wait);
    expect(vs.state.phase, TsumikiVsPhase.waiting);
    final inbox = TsumikiInvite.listFrom(backend.peek('/users/$friend/tsumikiInbox'));
    expect(inbox.single.from, me);
    expect(inbox.single.id, r.id);
    expect(backend.peek('${room()}/a'), isNotNull);
  });

  test('si dice que no, se ve; si se cancela, se retira del buzón', () async {
    await invited();
    backend.seed('${room()}/live/state', 'no');
    await settle();
    expect(vs.state.phase, TsumikiVsPhase.declined);

    await invited();
    await vs.cancel();
    await settle();
    expect(vs.state.phase, TsumikiVsPhase.cancelled);
    expect(backend.peek('${room()}/live/state'), 'gone');
    expect(backend.peek('/users/$friend/tsumikiInbox/$me'), isNull);
  });

  test('a los 10 minutos caduca', () async {
    await invited();
    await vs.checkExpiry();
    expect(vs.state.phase, TsumikiVsPhase.waiting);
    now = now.add(const Duration(minutes: 11));
    await vs.checkExpiry();
    await settle();
    expect(vs.state.phase, TsumikiVsPhase.expired);
    expect(backend.peek('${room()}/live/state'), 'gone');
  });

  test('al aceptar empieza y llega cada ataque una sola vez', () async {
    await invited();
    final got = <TsumikiVsEvent>[];
    final sub = vs.incoming.listen(got.add);
    addTearDown(sub.cancel);
    await beaAccepts();
    expect(vs.state.phase, TsumikiVsPhase.playing);

    backend.seed('${room()}/live/atk/$friend/k1', {'rows': 2, 'hole': 3});
    await settle();
    backend.seed('${room()}/live/atk/$friend/k2', {'sab': 'fog'});
    await settle();
    expect(got.length, 2);
    expect(got[0].attack!.rows, 2);
    expect(got[1].sabotage, TsumikiSabotage.fog);

    // Lo mío no me llega a mí.
    await vs.send(const TsumikiVsEvent.attack(TsumikiAttack(1, 0)));
    await settle();
    expect(got.length, 2);
    expect((backend.peek('${room()}/live/atk/$me') as Map).length, 1);
  });

  test('publicar deja el tablero y la señal de vida', () async {
    await invited();
    await beaAccepts();
    await vs.publish(board: '.' * 199 + 'g', lines: 4, sent: 2, meter: 33.33, fx: {TsumikiSabotage.rush});
    final seat = TsumikiSeat.fromJson(backend.peek('${room()}/live/p/$me'));
    expect(seat.board.length, 200);
    expect(seat.height, 1);
    expect(seat.lines, 4);
    expect(seat.meter, 33.3);
    expect(seat.fx, {TsumikiSabotage.rush});
    expect(seat.ping, isNotNull);
  });

  test('perder da la victoria al otro, con historial y marcador', () async {
    final r = await invited();
    await beaAccepts();
    backend.seed('${room()}/live/p/$friend', {'ping': 2, 'board': '', 'lines': 7, 'sent': 3});
    backend.seed('${room()}/score/$friend', 4);
    await settle();
    now = now.add(const Duration(seconds: 42));
    expect(await vs.lose(lines: 5, sent: 1), isTrue);
    await settle();
    expect(vs.state.phase, TsumikiVsPhase.done);
    expect(vs.state.winner, friend);
    expect(backend.peek('${room()}/score/$friend'), 5);
    final h = TsumikiMatchRecord.listFrom(backend.peek('${room()}/history')).single;
    expect(h.id, r.id);
    expect(h.winner, friend);
    expect(h.end, TsumikiEnd.top);
    expect(h.seconds, 42);
    expect(h.lines, {me: 5, friend: 7});
    expect(h.sent, {me: 1, friend: 3});
  });

  test('si el otro calla 20 s, gano por abandono', () async {
    await invited();
    await beaAccepts();
    now = now.add(const Duration(seconds: 15));
    await vs.heartbeat();
    expect(vs.state.phase, TsumikiVsPhase.playing);

    // Da señal: vuelve a contar desde aquí.
    backend.seed('${room()}/live/p/$friend/ping', 99);
    await settle();
    now = now.add(const Duration(seconds: 15));
    await vs.heartbeat();
    expect(vs.state.phase, TsumikiVsPhase.playing);

    now = now.add(const Duration(seconds: 6));
    await vs.heartbeat();
    await settle();
    expect(vs.state.phase, TsumikiVsPhase.done);
    expect(vs.state.winner, me);
    expect(backend.peek('${room()}/live/result/why'), 'quit');
  });

  test('cerrar a media partida es irse: gana el otro', () async {
    await invited();
    await beaAccepts();
    await vs.close(lines: 2);
    expect(backend.peek('${room()}/live/result/w'), friend);
    expect(backend.peek('${room()}/live/result/why'), 'leave');
    expect(vs.state.phase, TsumikiVsPhase.idle);
  });

  group('responder', () {
    void beaInvites(String id, {DateTime? at}) {
      final t = (at ?? now).millisecondsSinceEpoch;
      backend.seed('${room()}/live', {
        'id': id,
        'seed': 7,
        'host': friend,
        'guest': me,
        'state': 'wait',
        'at': t,
        'p': {
          friend: {'ping': t},
        },
      });
      backend.seed('/users/$me/tsumikiInbox/$friend', {'at': t, 'id': id});
    }

    test('aceptar pasa la sala a juego y vacía el buzón', () async {
      beaInvites('m1');
      final inv = TsumikiInvite.listFrom(backend.peek('/users/$me/tsumikiInbox')).single;
      expect(await vs.accept(inv), isTrue);
      await settle();
      expect(backend.peek('${room()}/live/state'), 'play');
      expect(backend.peek('/users/$me/tsumikiInbox'), isNull);
      expect(vs.state.phase, TsumikiVsPhase.playing);
      expect(vs.state.room!.side(me), 1);
    });

    test('una invitación que ya no es la de la sala se tira', () async {
      beaInvites('m2');
      backend.seed('/users/$me/tsumikiInbox/$friend', {'at': now.millisecondsSinceEpoch, 'id': 'm1'});
      final inv = TsumikiInvite.listFrom(backend.peek('/users/$me/tsumikiInbox')).single;
      expect(await vs.accept(inv), isFalse);
      expect(backend.peek('/users/$me/tsumikiInbox'), isNull);
      expect(backend.peek('${room()}/live/state'), 'wait');
    });

    test('rechazar avisa a quien invita', () async {
      beaInvites('m1');
      await vs.decline(TsumikiInvite.listFrom(backend.peek('/users/$me/tsumikiInbox')).single);
      expect(backend.peek('${room()}/live/state'), 'no');
      expect(backend.peek('/users/$me/tsumikiInbox'), isNull);
    });

    test('revancha: si el otro ya la ha pedido, se acepta', () async {
      await invited();
      await beaAccepts();
      await vs.lose(lines: 0, sent: 0);
      await settle();
      expect(vs.state.rematchOffered, isFalse);
      beaInvites('m9');
      await settle();
      expect(vs.state.phase, TsumikiVsPhase.done);
      expect(vs.state.rematchOffered, isTrue);
      expect(await vs.rematch(), isTrue);
      await settle();
      expect(vs.state.matchId, 'm9');
      expect(vs.state.phase, TsumikiVsPhase.playing);
    });

    test('el buzón solo cuenta las que no han caducado', () async {
      beaInvites('m1', at: now.subtract(const Duration(minutes: 11)));
      backend.seed('/users/$me/tsumikiInbox/otra', {'at': now.millisecondsSinceEpoch, 'id': 'x'});
      final sub = container.listen(pendingTsumikiInvitesProvider, (_, _) {});
      addTearDown(sub.close);
      await settle();
      await settle();
      expect(container.read(pendingTsumikiInvitesProvider), 1);
    });
  });

  test('historial y marcador se leen de la sala', () async {
    backend.seed('${room()}/history', {
      'a': {'w': me, 'why': 'top', 'at': 1000, 'dur': 30},
      'b': {'w': friend, 'why': 'quit', 'at': 2000, 'dur': 50},
      'roto': {'w': me},
    });
    backend.seed('${room()}/score', {me: 3, friend: 1});
    final h = await container.read(tsumikiHistoryProvider(friend).future);
    expect([for (final r in h) r.id], ['b', 'a']);
    final s = await container.read(tsumikiScoreProvider(friend).future);
    expect((s.mine, s.theirs), (3, 1));
  });

  test('el id de la pareja no depende del orden', () {
    expect(tsumikiPairId('b', 'a'), 'a_b');
    expect(tsumikiPairId('a', 'b'), 'a_b');
  });
}
