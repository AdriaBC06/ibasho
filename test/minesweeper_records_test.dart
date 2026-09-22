// Ibasho — el buscaminas de la 0.5.0: tablero del dia, medallas, récords y
// premios con tope diario.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/minesweeper/minesweeper.dart';
import 'package:ibasho/games/minesweeper/minesweeper_store.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/state/rewards.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

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
  group('tablero del dia', () {
    test('el mismo dia da el mismo tablero y la misma salida', () {
      final a = MinesweeperGame.daily(DateTime(2026, 9, 22, 8));
      final b = MinesweeperGame.daily(DateTime(2026, 9, 22, 23));
      expect(a.start, b.start);
      for (var y = 0; y < a.height; y++) {
        for (var x = 0; x < a.width; x++) {
          expect(a.cellAt(x, y).mine, b.cellAt(x, y).mine);
        }
      }
      final other = MinesweeperGame.daily(DateTime(2026, 9, 23));
      final same = [
        for (var y = 0; y < a.height; y++)
          for (var x = 0; x < a.width; x++) a.cellAt(x, y).mine == other.cellAt(x, y).mine,
      ].every((e) => e);
      expect(same, isFalse);
    });

    test('las minas ya estan puestas y la salida es segura', () {
      final game = MinesweeperGame.daily(DateTime(2026, 9, 22));
      final mines = [for (final row in game.cells) ...row].where((c) => c.mine).length;
      expect(mines, game.mines);
      final (sx, sy) = game.start!;
      expect(game.cellAt(sx, sy).mine, isFalse);
      expect(game.cellAt(sx, sy).adjacent, 0);
      // Empezar por otra casilla no mueve las minas.
      final before = [for (final row in game.cells) ...row].map((c) => c.mine).toList();
      game.reveal(sx, sy);
      expect([for (final row in game.cells) ...row].map((c) => c.mine).toList(), before);
    });

    test('poner una bandera deja constancia aunque se quite', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 1)..reveal(4, 4);
      expect(game.usedFlags, isFalse);
      final (x, y) = [
        for (var y = 0; y < game.height; y++)
          for (var x = 0; x < game.width; x++)
            if (!game.cellAt(x, y).revealed) (x, y),
      ].first;
      game
        ..toggleFlag(x, y)
        ..toggleFlag(x, y);
      expect(game.usedFlags, isTrue);
    });
  });

  group('medallas y récords', () {
    test('la medalla sale del tiempo de cada nivel', () {
      expect(medalFor(MinesweeperLevel.easy, const Duration(seconds: 25)), Medal.gold);
      expect(medalFor(MinesweeperLevel.easy, const Duration(seconds: 45)), Medal.silver);
      expect(medalFor(MinesweeperLevel.easy, const Duration(seconds: 100)), Medal.bronze);
      expect(medalFor(MinesweeperLevel.easy, const Duration(seconds: 200)), isNull);
      expect(medalFor(MinesweeperLevel.hard, const Duration(seconds: 200)), Medal.silver);
    });

    test('una victoria apunta récord, medalla, sello y cuenta', () {
      const empty = MinesweeperRecords();
      final (r1, first) = empty.recordWin(
        level: MinesweeperLevel.easy,
        time: const Duration(seconds: 50),
        usedFlags: true,
      );
      expect(first.newRecord, isFalse, reason: 'la primera no bate nada');
      expect(first.medal, Medal.silver);
      expect(first.newMedal, isTrue);
      expect(r1.wins[MinesweeperLevel.easy], 1);

      final (r2, second) = r1.recordWin(
        level: MinesweeperLevel.easy,
        time: const Duration(seconds: 20),
        usedFlags: false,
      );
      expect(second.newRecord, isTrue);
      expect(second.medal, Medal.gold);
      expect(second.newStamp, isTrue);
      expect(r2.best[MinesweeperLevel.easy], const Duration(seconds: 20));
      expect(r2.noFlags, contains(MinesweeperLevel.easy));

      // Una peor no quita nada.
      final (r3, third) = r2.recordWin(
        level: MinesweeperLevel.easy,
        time: const Duration(seconds: 90),
        usedFlags: true,
      );
      expect(third.newRecord, isFalse);
      expect(third.newMedal, isFalse);
      expect(r3.medals[MinesweeperLevel.easy], Medal.gold);
      expect(r3.wins[MinesweeperLevel.easy], 3);
    });

    test('el tablero del dia se guarda por fecha y va y vuelve por JSON', () {
      final day = DateTime(2026, 9, 22);
      final (records, report) = const MinesweeperRecords().recordWin(
        level: MinesweeperLevel.medium,
        time: const Duration(seconds: 80),
        usedFlags: true,
        day: day,
      );
      expect(report.medal, isNull);
      expect(records.daily['2026-09-22'], const Duration(seconds: 80));
      expect(records.best, isEmpty);
      final back = MinesweeperRecords.fromJson(records.toJson());
      expect(back.daily['2026-09-22'], const Duration(seconds: 80));
    });

    test('lee el formato de antes (solo tiempos) y reparte medallas', () {
      final back = MinesweeperRecords.fromJson({'easy': 28000, 'hard': 700000});
      expect(back.best[MinesweeperLevel.easy], const Duration(seconds: 28));
      expect(back.medals[MinesweeperLevel.easy], Medal.gold);
      expect(back.medals.containsKey(MinesweeperLevel.hard), isFalse);
    });
  });

  group('premios', () {
    test('cobrar sube las monedas y apunta lo cobrado hoy', () async {
      final backend = FakeIbashoBackend()..seed('/users/${FakeIbashoBackend().uid}/coins', 10);
      final container = await _account(backend);
      addTearDown(container.dispose);
      container.read(rewardsProvider);
      await _until(() => container.read(coinsProvider) == 10);

      final out = await container.read(rewardsProvider.notifier).claim(game: 'minesweeper', amount: 5);
      expect(out.status, RewardStatus.granted);
      expect(out.coins, 5);
      expect(await backend.read('/users/${backend.uid}/coins', idToken: ''), 15);
      final node = await backend.read('/users/${backend.uid}/earnings', idToken: '') as Map;
      expect(node['minesweeper']['earned'], 5);
      expect(node['minesweeper']['day'], RewardsState.today());
      expect(node['last']['game'], 'minesweeper');
    });

    test('con el tope cerca cobra lo que falta, y luego nada', () async {
      final backend = FakeIbashoBackend();
      backend
        ..seed('/users/${backend.uid}/coins', 0)
        ..seed('/users/${backend.uid}/earnings', {
          'minesweeper': {
            'day': RewardsState.today(),
            'earned': dailyRewardCap - 2,
            'at': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          },
          'last': {
            'game': 'minesweeper',
            'at': DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
          },
        });
      final container = await _account(backend);
      addTearDown(container.dispose);
      container.read(rewardsProvider);
      await _until(() => container.read(rewardsProvider).earnedToday('minesweeper') > 0);

      final out = await container.read(rewardsProvider.notifier).claim(game: 'minesweeper', amount: 8);
      expect(out.status, RewardStatus.granted);
      expect(out.coins, 2);
      final again = await container.read(rewardsProvider.notifier).claim(game: 'minesweeper', amount: 3);
      expect(again.status, RewardStatus.capped);
      // El tope es de cada juego: Tsumiki sigue teniendo sus 20.
      expect(container.read(rewardsProvider).leftToday('tsumiki'), dailyRewardCap);
    });

    test('lo cobrado otro dia no cuenta para hoy', () {
      final yesterday = RewardsState(
        games: {'minesweeper': GameEarning(day: RewardsState.today() - 1, earned: dailyRewardCap)},
      );
      expect(yesterday.leftToday('minesweeper'), dailyRewardCap);
    });
  });
}
