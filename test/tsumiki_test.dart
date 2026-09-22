// Ibasho — la logica de Tsumiki: giros, filas, puntos, reserva y final.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/tsumiki/tsumiki.dart';
import 'package:ibasho/games/tsumiki/tsumiki_store.dart';

void fillRow(TsumikiGame g, int y, {int gap = -1}) {
  for (var x = 0; x < TsumikiGame.width; x++) {
    if (x != gap) g.cells[y * TsumikiGame.width + x] = TsumikiPiece.o;
  }
}

void main() {
  test('cada pieza tiene cuatro casillas en sus cuatro giros', () {
    for (final p in TsumikiPiece.values) {
      for (var r = 0; r < 4; r++) {
        expect(shapeOf(p, r).toSet().length, 4, reason: '$p $r');
      }
    }
  });

  test('la bolsa saca las siete piezas antes de repetir', () {
    final g = TsumikiGame(seed: 3)..start();
    final seen = <TsumikiPiece>{g.current!.type, ...g.next.take(3)};
    for (var i = 0; i < 3; i++) {
      g.hardDrop();
      seen.add(g.next.last);
    }
    expect(seen.length, 7);
  });

  test('soltar de golpe puntua dos por fila y la pieza se asienta abajo', () {
    final g = TsumikiGame(seed: 1)..start();
    final res = g.hardDrop()!;
    expect(g.score, res.$1 * 2);
    expect(res.$2.cells.every((i) => i ~/ TsumikiGame.width >= TsumikiGame.rows - 2), isTrue);
  });

  test('cuatro filas son un tsumiki: 800 por nivel y combo', () {
    final g = TsumikiGame(seed: 1)..start();
    // Cuatro filas abajo con un hueco en la columna 0, y una I de pie.
    for (var y = TsumikiGame.rows - 4; y < TsumikiGame.rows; y++) {
      fillRow(g, y, gap: 0);
    }
    g.current = const FallingPiece(TsumikiPiece.i, 1, -2, 3);
    final before = g.score;
    final (_, e) = g.hardDrop()!;
    expect(e.rows.length, 4);
    expect(e.points, 800);
    expect(g.score - before, greaterThanOrEqualTo(800));
    expect(g.tsumikis, 1);
    // El destello termina y las filas desaparecen.
    g.tick(TsumikiGame.clearDelay + .01);
    expect(g.clearing, isEmpty);
    expect(g.lines, 4);
    expect(g.stackTop, TsumikiGame.visibleRows);
  });

  test('la gravedad baja la pieza y se asienta tras el retardo', () {
    final g = TsumikiGame(seed: 2)..start();
    final y0 = g.current!.y;
    g.tick(1.01);
    expect(g.current!.y, y0 + 1);
    for (var i = 0; i < 40; i++) {
      g.tick(1);
    }
    expect(g.cells.any((c) => c != null), isTrue);
  });

  test('guardar una vez por pieza', () {
    final g = TsumikiGame(seed: 4)..start();
    final first = g.current!.type;
    expect(g.hold(), isTrue);
    expect(g.held, first);
    expect(g.hold(), isFalse);
    g.hardDrop();
    expect(g.hold(), isTrue);
    expect(g.current!.type, first);
  });

  test('el giro empuja contra la pared', () {
    final g = TsumikiGame(seed: 5)..start();
    g.current = const FallingPiece(TsumikiPiece.t, 1, -1, 5);
    expect(g.rotate(), isTrue);
    expect(g.current!.cells.every((c) => c.$1 >= 0), isTrue);
  });

  test('se acaba si no cabe la nueva', () {
    final g = TsumikiGame(seed: 6)..start();
    for (var y = 0; y < TsumikiGame.rows; y++) {
      fillRow(g, y, gap: y.isEven ? 9 : 0);
    }
    g.current = const FallingPiece(TsumikiPiece.o, 0, 4, 0);
    g.cells.fillRange(0, 20, null);
    final (_, e) = g.hardDrop()!;
    expect(e.gameOver, isTrue);
    expect(g.isOver, isTrue);
  });

  test('monedas por filas', () {
    expect(tsumikiRewardFor(9), 0);
    expect(tsumikiRewardFor(10), 3);
    expect(tsumikiRewardFor(25), 5);
    expect(tsumikiRewardFor(80), 8);
  });

  test('récords: la primera partida no es récord, la segunda mejor si', () {
    final (r1, a) = const TsumikiRecords().record(score: 500, lines: 4, level: 1, tsumikis: 0, maxCombo: 1);
    expect(a.newRecord, isFalse);
    final (r2, b) = r1.record(score: 900, lines: 12, level: 2, tsumikis: 1, maxCombo: 2);
    expect(b.newRecord, isTrue);
    expect(b.newLines, isTrue);
    expect(TsumikiRecords.fromJson(r2.toJson()).bestScore, 900);
  });
}
