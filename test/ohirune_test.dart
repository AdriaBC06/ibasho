// Ibasho — pruebas del motor de Ohirune.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/ohirune/ohirune.dart';

void main() {
  group('generador', () {
    for (final level in OhiruneLevel.values) {
      test('${level.name}: una sola solución, zonas unidas y sin tocarse', () {
        for (var seed = 0; seed < 12; seed++) {
          final p = OhirunePuzzle.generate(level.size, seed: seed);
          final n = p.size;
          expect(p.regions.toSet(), {for (var r = 0; r < n; r++) r});
          expect(p.solution.toSet().length, n);
          for (var y = 1; y < n; y++) {
            expect((p.solution[y] - p.solution[y - 1]).abs(), greaterThan(1));
          }
          expect({for (var y = 0; y < n; y++) p.regionAt(p.solution[y], y)}.length, n);
          expect(solveOhirune(n, p.regions, avoid: p.solution), isNull);
          for (var r = 0; r < n; r++) {
            final cells = [for (var i = 0; i < n * n; i++) if (p.regions[i] == r) i];
            final seen = <int>{cells.first};
            final queue = [cells.first];
            while (queue.isNotEmpty) {
              final i = queue.removeLast();
              for (final j in [i - 1, i + 1, i - n, i + n]) {
                if (j < 0 || j >= n * n) continue;
                if ((j == i - 1 || j == i + 1) && j ~/ n != i ~/ n) continue;
                if (p.regions[j] == r && seen.add(j)) queue.add(j);
              }
            }
            expect(seen.length, cells.length, reason: 'zona $r partida');
          }
        }
      });
    }

    test('la misma semilla da el mismo puzle, y el del día es igual para todos', () {
      final a = OhirunePuzzle.generate(7, seed: 42), b = OhirunePuzzle.generate(7, seed: 42);
      expect(a.regions, b.regions);
      expect(a.solution, b.solution);
      expect(OhirunePuzzle.daily(20000).regions, OhirunePuzzle.daily(20000).regions);
      expect(OhirunePuzzle.daily(20000).size, ohiruneDailyLevel.size);
    });
  });

  group('partida', () {
    test('fallar cuesta una vida y deja una X; tres fallos acaban', () {
      final game = OhiruneGame(OhirunePuzzle.generate(5, seed: 1));
      final wrong = [
        for (var y = 0; y < 5; y++)
          for (var x = 0; x < 5; x++)
            if (!game.puzzle.isAnswer(x, y)) (x, y),
      ];
      expect(game.place(wrong[0].$1, wrong[0].$2), OhirunePlace.miss);
      expect(game.lives, 2);
      expect(game.markAt(wrong[0].$1, wrong[0].$2), OhiruneMark.cross);
      // Sobre una X no se pone nada: hay que quitarla antes.
      expect(game.place(wrong[0].$1, wrong[0].$2), OhirunePlace.ignored);
      game.place(wrong[1].$1, wrong[1].$2);
      game.place(wrong[2].$1, wrong[2].$2);
      expect(game.status, OhiruneStatus.lost);
      expect(game.place(game.puzzle.solution[0], 0), OhirunePlace.ignored);
    });

    test('un fallo dice que regla rompe, y su X roja no se quita', () {
      final game = OhiruneGame(OhirunePuzzle.generate(6, seed: 5));
      final p = game.puzzle;
      game.place(p.solution[0], 0);
      // Misma columna que el Tama de la fila 0, dos filas mas abajo.
      final clash = game.clashAt(p.solution[0], 2);
      expect(clash.column, isTrue);
      expect(clash.row, isFalse);
      expect(clash.culprits, {p.solution[0]});
      expect(game.clashArea(p.solution[0], 2, clash), {for (var y = 0; y < 6; y++) y * 6 + p.solution[0]});
      // Justo debajo en diagonal: se tocan.
      final dx = p.solution[0] == 0 ? 1 : -1;
      final touch = game.clashAt(p.solution[0] + dx, 1);
      expect(touch.touching, isTrue);
      expect(game.clashArea(p.solution[0] + dx, 1, touch), contains(p.solution[0]));

      expect(game.place(p.solution[0], 2), OhirunePlace.miss);
      final i = 2 * 6 + p.solution[0];
      expect(game.misses, {i});
      game.toggleCross(p.solution[0], 2);
      game.setCross(p.solution[0], 2, false);
      expect(game.markAt(p.solution[0], 2), OhiruneMark.cross);
    });

    test('las X no cuestan nada y todos los Tamas en su sitio ganan', () {
      final game = OhiruneGame(OhirunePuzzle.generate(6, seed: 3));
      game.toggleCross(0, 0);
      game.toggleCross(0, 0);
      game.setCross(1, 0, true);
      expect(game.lives, ohiruneLives);
      for (var y = 0; y < 6; y++) {
        final x = game.puzzle.solution[y];
        if (game.markAt(x, y) == OhiruneMark.cross) game.toggleCross(x, y);
        expect(game.place(x, y), OhirunePlace.placed);
      }
      expect(game.status, OhiruneStatus.won);
    });
  });
}
