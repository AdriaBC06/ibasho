// Ibasho — Malla online: el motor con saltos, lo que se guarda y una sala
// con dos cuentas sobre la misma base, del código a la revancha.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/malla.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/games/malla/malla_channel.dart' show mallaOnlineReward, mallaCpuReward;
import 'package:ibasho/games/malla/malla_ai.dart';
import 'package:ibasho/games/malla/malla_game.dart';
import 'package:ibasho/state/malla.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

/// Una cuenta: su doble del backend, su sesión y su sala.
class _Player {
  _Player(this.backend, this.name)
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
  final String name;
  final ProviderContainer container;
  late final MallaOnlineController malla;
  final List<MallaRecord> finished = <MallaRecord>[];
  DateTime now = DateTime(2026, 10, 4, 12);

  String get uid => backend.uid;

  MallaIdentity get me => MallaIdentity(
        name: name,
        marker: name[0],
        color: '#397d79',
        tama: const MallaTama(name: 'Mochi', personality: TamaPersonality.calm, look: TamaLook()),
      );

  Future<void> start() async {
    await container.read(sessionProvider.notifier).restore();
    malla = MallaOnlineController(backend: backend, session: container.read(sessionProvider.notifier), clock: () => now)
      ..onFinished = finished.add;
  }

  void dispose() {
    malla.dispose();
    container.dispose();
  }
}

void main() {
  group('motor', () {
    test('quien queda fuera pierde el turno y sus aristas se quedan', () {
      final game = MallaGame(size: 3, playerCount: 3, startSeat: 0, chain: false);
      final edge = game.legalEdges.first.key;
      expect(game.applyMove(edge, 0).accepted, isTrue);
      expect(game.currentPlayer, 1);
      game.applyOut(1);
      expect(game.currentPlayer, 2);
      expect(game.edges[edge]!.owner, 0);
      final next = game.legalEdges.first.key;
      expect(game.applyMove(next, 2).accepted, isTrue);
      expect(game.currentPlayer, 0, reason: 'el 1 está fuera: del 2 se pasa al 0');
      expect(game.finished, isFalse);
    });

    test('si queda uno solo, gana aunque falten aristas', () {
      final game = MallaGame(size: 3, playerCount: 3, startSeat: 0, chain: false)
        ..applyOut(1)
        ..applyOut(2);
      expect(game.finished, isTrue);
      expect(game.lastStanding, isTrue);
      expect(game.winners, [0]);
    });

    test('rejugar con salidas da lo mismo que jugar', () {
      final game = MallaGame(size: 4, playerCount: 3, startSeat: 1, chain: true);
      for (var i = 0; i < 12; i++) {
        game.applyMove(game.legalEdges.first.key, game.currentPlayer);
        if (i == 5) game.applyOut(2);
      }
      final again = MallaGame.replay(size: 4, playerCount: 3, startSeat: 1, chain: true, moves: game.moves);
      expect(again.currentPlayer, game.currentPlayer);
      expect(again.scores, game.scores);
      expect(again.out, {2});
    });
  });

  group('lo que se guarda', () {
    test('los códigos no llevan letras que se confunden', () {
      for (var i = 0; i < 200; i++) {
        final code = generateMallaCode();
        expect(mallaCodePattern.hasMatch(code), isTrue);
      }
      expect(cleanMallaCode('ab-c 2o3i4z'), 'ABC234');
    });

    test('la sala se lee igual venga en lista o en mapa', () {
      final asList = MallaRoom.fromJson('ABC234', {
        'host': 'a',
        'at': 1,
        'size': 3,
        'max': 2,
        'chain': false,
        'state': 'play',
        'count': 2,
        'members': {
          'a': {'name': 'Ana', 'marker': 'A', 'color': '#397d79', 'at': 1},
          'b': {'name': 'Bea', 'marker': 'B', 'color': '#bd6f57', 'at': 2},
        },
        'order': ['a', 'b'],
        'start': 0,
        'turn': 1,
        'n': 2,
        'moves': [
          {'k': MallaGame(size: 3, playerCount: 2, startSeat: 0, chain: false).legalEdges.first.key, 'p': 0},
          {'o': 1},
        ],
      })!;
      expect(asList.order, ['a', 'b']);
      expect(asList.moves.length, 2);
      expect(asList.moves.last.isOut, isTrue);
      expect(asList.seatOf('b'), 1);
      final game = asList.toGame();
      expect(game.finished, isTrue);
      expect(game.winners, [0]);
    });

    test('el historial va y vuelve', () {
      final record = MallaRecord(
        code: 'ABC234',
        at: _epoch,
        size: 4,
        me: 1,
        end: MallaEnd.board,
        players: const [
          MallaHistoryPlayer(account: 'a', name: 'Ana', score: 3, marker: 'A', color: '#397d79'),
          MallaHistoryPlayer(account: 'b', name: 'Bea', score: 6, marker: 'B', color: '#bd6f57'),
        ],
        winners: [1],
      );
      final back = MallaRecord.fromJson('ABC234', record.toJson(1000))!;
      expect(back.won, isTrue);
      expect(back.players.map((p) => p.name), ['Ana', 'Bea']);
      expect(mallaOnlineReward(back), 5);
    });

    test('monedas: 3 contra la máquina (1 en fácil), 5 o 1 online, 0 al irse', () {
      expect(mallaCpuReward(won: true, difficulty: MallaDifficulty.hard), 3);
      expect(mallaCpuReward(won: true, difficulty: MallaDifficulty.easy), 1);
      expect(mallaCpuReward(won: false, difficulty: MallaDifficulty.hard), 0);
      MallaRecord rec(MallaEnd end, List<int> winners) => MallaRecord(
            code: 'ABC234',
            at: _epoch,
            size: 3,
            me: 0,
            end: end,
            players: const [
              MallaHistoryPlayer(account: 'a', name: 'A', score: 0),
              MallaHistoryPlayer(account: 'b', name: 'B', score: 0),
            ],
            winners: winners,
          );
      expect(mallaOnlineReward(rec(MallaEnd.board, [1])), 1);
      expect(mallaOnlineReward(rec(MallaEnd.last, [0])), 5);
      expect(mallaOnlineReward(rec(MallaEnd.left, [1])), 0);
    });
  });

  group('dos cuentas', () {
    late _Player adri;
    late _Player mireia;

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    setUp(() async {
      final base = FakeIbashoBackend()..seed('/allowlist/$kMireiaUid/mustChangePassword', false);
      adri = _Player(base, 'Adri');
      mireia = _Player(base.sharing(uid: kMireiaUid, username: 'mireia'), 'Mireia');
      await adri.start();
      await mireia.start();
    });

    tearDown(() {
      adri.dispose();
      mireia.dispose();
    });

    /// Adri crea la sala, invita a Mireia y ella entra con la invitación.
    Future<String> together() async {
      expect(await adri.malla.create(size: 3, max: 3, chain: false, me: adri.me), isTrue);
      await settle();
      expect(adri.malla.state.phase, MallaPhase.lobby);
      final code = adri.malla.state.code!;
      expect(await adri.malla.invite(kMireiaUid), isTrue);
      final sub = mireia.container.listen(mallaInvitesProvider, (_, _) {});
      addTearDown(sub.close);
      await settle();
      final invite = mireia.container.read(mallaInvitesProvider).valueOrNull!.single;
      expect(invite.code, code);
      expect(await mireia.malla.join(invite.code, me: mireia.me), isTrue);
      await settle();
      expect(mireia.malla.state.phase, MallaPhase.lobby);
      expect(adri.malla.state.room!.lobby.map((m) => m.name), ['Adri', 'Mireia']);
      expect(adri.malla.state.room!.members[kMireiaUid]!.tama!.name, 'Mochi');
      return code;
    }

    _Player turnOf() {
      final game = adri.malla.state.game!;
      return game.currentPlayer == adri.malla.seat ? adri : mireia;
    }

    test('crear, invitar, empezar y jugar hasta el final, con historial', () async {
      final code = await together();
      expect(await mireia.malla.start(), isFalse, reason: 'solo empieza quien la creó');
      expect(await adri.malla.start(), isTrue);
      await settle();
      expect(adri.malla.state.phase, MallaPhase.playing);
      expect(mireia.malla.state.phase, MallaPhase.playing);
      expect(adri.malla.seat, isNot(mireia.malla.seat));

      var guard = 0;
      while (adri.malla.state.phase == MallaPhase.playing && guard++ < 200) {
        final who = turnOf();
        final other = who == adri ? mireia : adri;
        final game = who.malla.state.game!;
        final key = game.legalEdges.first.key;
        expect(await other.malla.play(key), isFalse, reason: 'no es su turno');
        expect(await who.malla.play(key), isTrue);
        await settle();
        expect(mireia.malla.state.game!.scores, adri.malla.state.game!.scores);
      }
      expect(adri.malla.state.phase, MallaPhase.done);
      expect(mireia.malla.state.phase, MallaPhase.done);
      expect(adri.malla.state.room!.phase, MallaRoomPhase.done);
      expect(adri.finished.single.code, code);
      expect(mireia.finished.single.end, MallaEnd.board);
      await settle();
      final history = await adri.backend.read('/mallaHistory/${adri.uid}', idToken: 't');
      expect(MallaRecord.listFrom(history).single.players.length, 2);
    });

    test('quien se va queda fuera y el otro gana', () async {
      await together();
      await adri.malla.start();
      await settle();
      await mireia.malla.close();
      await settle();
      expect(mireia.malla.state.phase, MallaPhase.idle);
      expect(mireia.finished.single.end, MallaEnd.left);
      expect(adri.malla.state.phase, MallaPhase.done);
      expect(adri.finished.single.end, MallaEnd.last);
      expect(adri.finished.single.won, isTrue);
    });

    test('a quien pasa 25 s sin señal se le salta', () async {
      await together();
      await adri.malla.start();
      await settle();
      adri.now = adri.now.add(const Duration(seconds: 30));
      // El servidor falso no mira la hora: la regla de los 20 s está en los
      // tests de reglas.
      await adri.malla.heartbeat();
      await settle();
      expect(adri.malla.state.game!.out, {mireia.malla.seat});
      expect(adri.malla.state.phase, MallaPhase.done);
    });

    test('la revancha mete a todos en una sala nueva', () async {
      await together();
      await adri.malla.start();
      await settle();
      await mireia.malla.close();
      await settle();
      // Mireia vuelve a la sala acabada para la revancha (como si no se
      // hubiera ido): basta con que siga escuchando. Aquí, Adri sola.
      final old = adri.malla.state.code;
      expect(await adri.malla.rematch(me: adri.me), isTrue);
      await settle();
      expect(adri.malla.state.code, isNot(old));
      expect(adri.malla.state.phase, MallaPhase.lobby);
    });

    test('cerrar la sala antes de empezar echa a los demás', () async {
      await together();
      await adri.malla.close();
      await settle();
      expect(mireia.malla.state.phase, MallaPhase.closed);
    });

    test('un código que no existe o una sala llena no dejan entrar', () async {
      expect(await mireia.malla.join('ZZZ999', me: mireia.me), isFalse);
      expect(mireia.malla.state.problem, MallaProblem.notFound);
      expect(await adri.malla.create(size: 3, max: 2, chain: false, me: adri.me), isTrue);
      await settle();
      final code = adri.malla.state.code!;
      await adri.backend.write('/malla/$code/members/other', {'name': 'X', 'marker': 'X', 'color': '#000000', 'at': 5},
          idToken: 't');
      await settle();
      expect(await mireia.malla.join(code, me: mireia.me), isFalse);
      expect(mireia.malla.state.problem, MallaProblem.full);
    });
  });
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
