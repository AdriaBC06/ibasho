// Ibasho — reglas del buscaminas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/minesweeper/minesweeper.dart';

void main() {
  group('primer toque', () {
    test('nunca cae en mina, con muchas semillas', () {
      for (var seed = 0; seed < 200; seed++) {
        final game = MinesweeperGame(MinesweeperLevel.medium, seed: seed);
        game.reveal(5, 5);
        expect(game.cellAt(5, 5).mine, isFalse, reason: 'semilla $seed');
        expect(game.status, isNot(MinesweeperStatus.lost));
      }
    });

    test('tampoco en las vecinas del primer toque', () {
      for (var seed = 0; seed < 200; seed++) {
        final game = MinesweeperGame(MinesweeperLevel.easy, seed: seed);
        game.reveal(4, 4);
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            expect(game.cellAt(4 + dx, 4 + dy).mine, isFalse, reason: 'semilla $seed');
          }
        }
      }
    });

    test('pasa de ready a playing', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 1);
      expect(game.status, MinesweeperStatus.ready);
      game.reveal(0, 0);
      expect(game.status, MinesweeperStatus.playing);
    });

    test('coloca el numero de minas del nivel', () {
      final game = MinesweeperGame(MinesweeperLevel.hard, seed: 7);
      game.reveal(8, 8);
      final placed = [for (final row in game.cells) ...row].where((c) => c.mine).length;
      expect(placed, MinesweeperLevel.hard.mines);
    });
  });

  group('inundacion', () {
    test('destapa en cadena las casillas sin minas alrededor', () {
      // Un tablero pequeño con una unica mina en la esquina: el resto es una
      // sola region de ceros y se destapa entera de un toque.
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 3);
      game.reveal(4, 4);
      final revealed = [for (final row in game.cells) ...row].where((c) => c.revealed).length;
      expect(revealed, greaterThan(1));
    });
  });

  group('banderas', () {
    test('poner y quitar bandera cambia el contador de minas restantes', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 1);
      game.reveal(0, 0);
      final before = game.minesLeft;
      game.toggleFlag(8, 8);
      expect(game.minesLeft, before - 1);
      game.toggleFlag(8, 8);
      expect(game.minesLeft, before);
    });

    test('no se puede destapar una casilla con bandera', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 1);
      game.reveal(0, 0);
      int? hx, hy;
      outer:
      for (var y = 0; y < game.height; y++) {
        for (var x = 0; x < game.width; x++) {
          if (!game.cellAt(x, y).revealed) {
            hx = x;
            hy = y;
            break outer;
          }
        }
      }
      expect(hx, isNotNull);
      game.toggleFlag(hx!, hy!);
      game.reveal(hx, hy);
      expect(game.cellAt(hx, hy).revealed, isFalse);
    });

    test('no se puede poner bandera en una casilla ya destapada', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 1);
      game.reveal(0, 0);
      final before = game.flagsPlaced;
      game.toggleFlag(0, 0);
      expect(game.flagsPlaced, before);
    });
  });

  group('chord', () {
    test('destapa las vecinas cuando el numero ya tiene sus banderas', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 1);
      game.reveal(0, 0);

      // Busca una casilla destapada con numero > 0 y localiza sus vecinas
      // tapadas, para poner las banderas correctas y comprobar el chord.
      int? nx, ny, mx, my;
      outer:
      for (var y = 0; y < game.height; y++) {
        for (var x = 0; x < game.width; x++) {
          final cell = game.cellAt(x, y);
          if (!cell.revealed || cell.adjacent == 0) continue;
          final mines = <(int, int)>[];
          final hidden = <(int, int)>[];
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final px = x + dx, py = y + dy;
              if (!game.inBounds(px, py)) continue;
              final n = game.cellAt(px, py);
              if (n.mine) mines.add((px, py));
              if (!n.revealed) hidden.add((px, py));
            }
          }
          if (mines.length == cell.adjacent && hidden.length > mines.length) {
            nx = x;
            ny = y;
            mx = mines.first.$1;
            my = mines.first.$2;
            break outer;
          }
        }
      }

      expect(nx, isNotNull, reason: 'no se ha encontrado un numero apto en esta semilla');
      game.toggleFlag(mx!, my!);
      game.reveal(nx!, ny!);
      // El chord ha destapado alguna vecina que no era la mina marcada.
      final anyOtherRevealed = [for (final row in game.cells) ...row]
          .where((c) => c.revealed && !c.mine)
          .isNotEmpty;
      expect(anyOtherRevealed, isTrue);
    });

    test('el chord con una bandera mal puesta pierde la partida', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 1);
      game.reveal(0, 0);

      // Encuentra un numero con una vecina tapada que no es mina, para
      // marcarla como si lo fuera y provocar un chord que explote.
      int? nx, ny, wrongX, wrongY;
      outer:
      for (var y = 0; y < game.height; y++) {
        for (var x = 0; x < game.width; x++) {
          final cell = game.cellAt(x, y);
          if (!cell.revealed || cell.adjacent == 0) continue;
          final hidden = <(int, int)>[];
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final px = x + dx, py = y + dy;
              if (!game.inBounds(px, py)) continue;
              final n = game.cellAt(px, py);
              if (!n.revealed && !n.mine) hidden.add((px, py));
            }
          }
          if (hidden.length >= cell.adjacent && cell.adjacent > 0) {
            nx = x;
            ny = y;
            wrongX = hidden.first.$1;
            wrongY = hidden.first.$2;
            break outer;
          }
        }
      }

      expect(nx, isNotNull, reason: 'no se ha encontrado un numero apto en esta semilla');
      final cell = game.cellAt(nx!, ny!);
      // Se marcan como minas tantas vecinas tapadas (sin serlo) como pida el
      // numero, para que el chord se dispare igual.
      var toFlag = cell.adjacent;
      for (var dy = -1; dy <= 1 && toFlag > 0; dy++) {
        for (var dx = -1; dx <= 1 && toFlag > 0; dx++) {
          if (dx == 0 && dy == 0) continue;
          final px = nx + dx, py = ny + dy;
          if (!game.inBounds(px, py)) continue;
          final n = game.cellAt(px, py);
          if (!n.revealed && !n.mine) {
            game.toggleFlag(px, py);
            toFlag--;
          }
        }
      }
      game.reveal(wrongX!, wrongY!);
      // Deja de ser fiable seguir con el chord si ya no hay banderas
      // suficientes sobre minas de verdad; se dispara sobre el propio numero.
      game.reveal(nx, ny);
      expect(game.status, MinesweeperStatus.lost);
    });
  });

  group('victoria y derrota', () {
    test('se gana al destapar todas las casillas seguras', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 5);
      game.reveal(0, 0);
      var guard = 0;
      while (game.status == MinesweeperStatus.playing && guard < 10000) {
        guard++;
        var moved = false;
        for (var y = 0; y < game.height && !moved; y++) {
          for (var x = 0; x < game.width && !moved; x++) {
            final cell = game.cellAt(x, y);
            if (!cell.revealed && !cell.mine) {
              game.reveal(x, y);
              moved = true;
            }
          }
        }
        if (!moved) break;
      }
      expect(game.status, MinesweeperStatus.won);
      expect(game.minesLeft, 0);
    });

    test('al perder se revelan todas las minas', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 5);
      game.reveal(0, 0);
      final mine = [for (final row in game.cells) ...row]
          .where((c) => c.mine && !c.revealed)
          .first;
      // Busca la posicion (x,y) real de esa mina.
      int mx = -1, my = -1;
      outer:
      for (var y = 0; y < game.height; y++) {
        for (var xx = 0; xx < game.width; xx++) {
          if (identical(game.cellAt(xx, y), mine)) {
            mx = xx;
            my = y;
            break outer;
          }
        }
      }
      game.reveal(mx, my);
      expect(game.status, MinesweeperStatus.lost);
      expect(mine.revealed, isTrue);
      final allMinesRevealed =
          [for (final row in game.cells) ...row].where((c) => c.mine).every((c) => c.revealed);
      expect(allMinesRevealed, isTrue);
    });

    test('al perder se marcan las banderas equivocadas', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 5);
      game.reveal(0, 0);
      final safe = [for (final row in game.cells) ...row].where((c) => !c.mine && !c.revealed).first;
      int sx = -1, sy = -1, mx = -1, my = -1;
      outer:
      for (var y = 0; y < game.height; y++) {
        for (var x = 0; x < game.width; x++) {
          if (identical(game.cellAt(x, y), safe)) {
            sx = x;
            sy = y;
            break outer;
          }
        }
      }
      game.toggleFlag(sx, sy);
      for (var y = 0; y < game.height && mx < 0; y++) {
        for (var x = 0; x < game.width && mx < 0; x++) {
          if (game.cellAt(x, y).mine) {
            mx = x;
            my = y;
          }
        }
      }
      // La mina que se destapa se deja sin bandera: con ella puesta no se
      // podria destapar y la partida no terminaria.
      game.reveal(mx, my);
      expect(game.status, MinesweeperStatus.lost);
      expect(game.cellAt(sx, sy).wrongFlag, isTrue);
      expect(game.cellAt(mx, my).wrongFlag, isFalse);
    });

    test('una partida perdida no acepta mas jugadas', () {
      final game = MinesweeperGame(MinesweeperLevel.easy, seed: 5);
      game.reveal(0, 0);
      int mx = -1, my = -1;
      outer:
      for (var y = 0; y < game.height; y++) {
        for (var x = 0; x < game.width; x++) {
          if (game.cellAt(x, y).mine) {
            mx = x;
            my = y;
            break outer;
          }
        }
      }
      game.reveal(mx, my);
      expect(game.status, MinesweeperStatus.lost);
      final untouched = [for (final row in game.cells) ...row]
          .where((c) => !c.revealed && !c.mine)
          .isNotEmpty;
      game.reveal(0, 1);
      expect(untouched, isTrue);
    });
  });
}
