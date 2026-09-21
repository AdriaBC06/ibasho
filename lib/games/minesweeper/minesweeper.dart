// Ibasho — logica pura del buscaminas, sin nada de Flutter.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

/// Las tres dificultades, con su tablero y su numero de minas.
enum MinesweeperLevel {
  easy(9, 9, 10),
  medium(12, 12, 24),
  hard(16, 16, 40);

  const MinesweeperLevel(this.width, this.height, this.mines);

  final int width;
  final int height;
  final int mines;
}

/// Como va la partida.
enum MinesweeperStatus {
  /// Tablero recien creado: las minas aun no se han colocado.
  ready,
  playing,
  won,
  lost,
}

/// Una casilla del tablero.
class MinesweeperCell {
  bool mine = false;

  /// Minas en las ocho vecinas. Solo tiene sentido si no es mina.
  int adjacent = 0;

  bool revealed = false;
  bool flagged = false;

  /// Se marca al perder: una bandera puesta donde no habia mina.
  bool wrongFlag = false;
}

/// Una partida de buscaminas.
///
/// El tablero se crea vacio de minas: se colocan en el primer toque, sin caer
/// nunca en esa casilla ni en sus vecinas, asi que el primer click siempre es
/// seguro. A partir de ahi todo es determinista salvo la semilla del azar, que
/// se puede fijar para que un test reproduzca la misma partida.
class MinesweeperGame {
  MinesweeperGame(this.level, {int? seed})
      : width = level.width,
        height = level.height,
        mines = level.mines,
        _random = Random(seed),
        cells = List.generate(
          level.height,
          (_) => List.generate(level.width, (_) => MinesweeperCell()),
        );

  final MinesweeperLevel level;
  final int width;
  final int height;
  final int mines;
  final Random _random;

  /// `cells[y][x]`.
  final List<List<MinesweeperCell>> cells;

  MinesweeperStatus status = MinesweeperStatus.ready;

  /// Banderas puestas ahora mismo.
  int flagsPlaced = 0;

  /// Casillas seguras ya destapadas. Se gana cuando quedan justo las minas.
  int _revealedSafe = 0;

  /// Ultima casilla que exploto, para resaltarla.
  int? losingX;
  int? losingY;

  bool get isOver => status == MinesweeperStatus.won || status == MinesweeperStatus.lost;

  int get minesLeft => mines - flagsPlaced;

  MinesweeperCell cellAt(int x, int y) => cells[y][x];

  bool inBounds(int x, int y) => x >= 0 && x < width && y >= 0 && y < height;

  Iterable<(int, int)> _neighbours(int x, int y) sync* {
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (inBounds(nx, ny)) yield (nx, ny);
      }
    }
  }

  void _placeMines(int safeX, int safeY) {
    final forbidden = <int>{safeY * width + safeX};
    for (final (nx, ny) in _neighbours(safeX, safeY)) {
      forbidden.add(ny * width + nx);
    }
    final candidates = [
      for (var i = 0; i < width * height; i++)
        if (!forbidden.contains(i)) i,
    ]..shuffle(_random);

    final count = min(mines, candidates.length);
    for (var i = 0; i < count; i++) {
      final index = candidates[i];
      cells[index ~/ width][index % width].mine = true;
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final cell = cells[y][x];
        if (cell.mine) continue;
        cell.adjacent =
            _neighbours(x, y).where((p) => cells[p.$2][p.$1].mine).length;
      }
    }
  }

  /// Toca una casilla: la destapa, o si ya estaba destapada intenta el
  /// *chord* (destapar sus vecinas cuando ya tiene todas sus banderas).
  void reveal(int x, int y) {
    if (isOver) return;
    final cell = cellAt(x, y);
    if (cell.flagged) return;

    if (status == MinesweeperStatus.ready) {
      _placeMines(x, y);
      status = MinesweeperStatus.playing;
    }

    if (cell.revealed) {
      _chord(x, y);
      return;
    }

    _revealCell(x, y);
    _checkWin();
  }

  void _revealCell(int x, int y) {
    final cell = cellAt(x, y);
    if (cell.revealed || cell.flagged) return;
    cell.revealed = true;

    if (cell.mine) {
      _lose(x, y);
      return;
    }

    _revealedSafe++;
    if (cell.adjacent == 0) {
      for (final (nx, ny) in _neighbours(x, y)) {
        if (!isOver) _revealCell(nx, ny);
      }
    }
  }

  /// Destapa las vecinas de un numero ya destapado, si tiene puestas todas
  /// sus banderas. Una bandera mal puesta en medio hace perder, como en
  /// cualquier buscaminas de verdad.
  void _chord(int x, int y) {
    final cell = cellAt(x, y);
    if (!cell.revealed || cell.mine || cell.adjacent == 0) return;

    final neighbours = _neighbours(x, y).toList();
    final flagged = neighbours.where((p) => cellAt(p.$1, p.$2).flagged).length;
    if (flagged != cell.adjacent) return;

    for (final (nx, ny) in neighbours) {
      if (isOver) return;
      if (!cellAt(nx, ny).flagged) _revealCell(nx, ny);
    }
    if (!isOver) _checkWin();
  }

  /// Pone o quita la bandera de una casilla tapada.
  void toggleFlag(int x, int y) {
    if (isOver) return;
    final cell = cellAt(x, y);
    if (cell.revealed) return;
    cell.flagged = !cell.flagged;
    flagsPlaced += cell.flagged ? 1 : -1;
  }

  void _lose(int x, int y) {
    status = MinesweeperStatus.lost;
    losingX = x;
    losingY = y;
    for (final row in cells) {
      for (final cell in row) {
        if (cell.mine) cell.revealed = true;
        if (cell.flagged && !cell.mine) cell.wrongFlag = true;
      }
    }
  }

  void _checkWin() {
    if (status != MinesweeperStatus.playing) return;
    if (_revealedSafe != width * height - mines) return;
    status = MinesweeperStatus.won;
    // Las minas que quedaban sin bandera se marcan solas: no hace falta
    // señalarlas a mano para terminar la partida.
    for (final row in cells) {
      for (final cell in row) {
        if (cell.mine && !cell.flagged) {
          cell.flagged = true;
          flagsPlaced++;
        }
      }
    }
  }
}
