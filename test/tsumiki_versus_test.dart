// Ibasho — Tsumiki versus: filas grises, compensar, medidor y sabotajes.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/tsumiki/tsumiki.dart';
import 'package:ibasho/games/tsumiki/tsumiki_versus.dart';

const int w = TsumikiGame.width;

void fillRow(TsumikiGame g, int y, {int gap = -1}) {
  for (var x = 0; x < w; x++) {
    if (x != gap) g.cells[y * w + x] = TsumikiPiece.o;
  }
}

/// Deja una I tumbada justo encima del suelo y asienta: no borra nada.
LockEvent dropFlat(TsumikiGame g) {
  g.current = FallingPiece(TsumikiPiece.i, 0, 0, TsumikiGame.rows - 2 - 1);
  return g.hardDrop()!.$2;
}

void main() {
  test('la tabla de ataque: 2 → 1, 3 → 2, tsumiki → 4, seguidos +1', () {
    expect(tsumikiAttackFor(1), 0);
    expect(tsumikiAttackFor(2), 1);
    expect(tsumikiAttackFor(3), 2);
    expect(tsumikiAttackFor(4), 4);
    expect(tsumikiAttackFor(4, backToBack: true), 5);
    expect(tsumikiAttackFor(1, combo: 3), 1);
    expect(tsumikiAttackFor(2, combo: 13), 1 + 5);
    expect(tsumikiAttackFor(2, combo: 40), 1 + 5);
    expect(tsumikiAttackFor(0, combo: 5), 0);
  });

  test('las mismas piezas para los dos y huecos distintos', () {
    final a = TsumikiDuel(seed: 42, side: 0)..game.start();
    final b = TsumikiDuel(seed: 42, side: 1)..game.start();
    for (var i = 0; i < 20; i++) {
      expect(a.game.current!.type, b.game.current!.type);
      a.game.hardDrop();
      b.game.hardDrop();
      if (a.game.isOver || b.game.isOver) break;
    }
  });

  test('el tablero va y vuelve por la red', () {
    final g = TsumikiGame(seed: 1);
    fillRow(g, TsumikiGame.rows - 1, gap: 3);
    g.cells[(TsumikiGame.rows - 2) * w + 5] = TsumikiPiece.garbage;
    g.cells[(TsumikiGame.rows - 2) * w + 6] = TsumikiPiece.t;
    final code = g.encodeBoard();
    expect(code.length, w * TsumikiGame.visibleRows);
    final back = TsumikiGame.decodeBoard(code);
    for (var i = 0; i < back.length; i++) {
      expect(back[i], g.cells[i + TsumikiGame.hiddenRows * w], reason: '$i');
    }
    expect(TsumikiGame.decodeBoard('').every((c) => c == null), isTrue);
  });

  test('las filas grises suben al asentar sin borrar, con su hueco', () {
    final g = TsumikiGame(seed: 1)..start();
    g.queueGarbage(3, 7);
    expect(g.pendingGarbage, 3);
    final e = dropFlat(g);
    expect(e.garbageIn, 3);
    expect(g.pendingGarbage, 0);
    for (var y = TsumikiGame.rows - 3; y < TsumikiGame.rows; y++) {
      for (var x = 0; x < w; x++) {
        expect(g.at(x, y), x == 7 ? null : TsumikiPiece.garbage, reason: '$x,$y');
      }
    }
    // La I que habia en el suelo ha subido tres filas.
    expect(g.at(0, TsumikiGame.rows - 4), TsumikiPiece.i);
  });

  test('suben como mucho ocho por pieza; el resto espera', () {
    final g = TsumikiGame(seed: 1)..start();
    g.queueGarbage(6, 0);
    g.queueGarbage(5, 1);
    expect(dropFlat(g).garbageIn, 8);
    expect(g.pendingGarbage, 3);
  });

  test('si las grises sacan algo por arriba, se acaba', () {
    final g = TsumikiGame(seed: 1)..start();
    g.cells[3] = TsumikiPiece.o;
    g.queueGarbage(1, 0);
    final e = dropFlat(g);
    expect(e.gameOver, isTrue);
    expect(g.isOver, isTrue);
  });

  test('borrar filas compensa lo que espera y manda el resto', () {
    final d = TsumikiDuel(seed: 1, side: 0)..game.start();
    d.receive(const TsumikiAttack(3, 2));
    final g = d.game;
    for (var y = TsumikiGame.rows - 4; y < TsumikiGame.rows; y++) {
      fillRow(g, y, gap: 0);
    }
    g.current = FallingPiece(TsumikiPiece.i, 1, -2, 0);
    final e = g.hardDrop()!.$2;
    expect(e.rows.length, 4);
    final out = d.onLock(e);
    expect(g.pendingGarbage, 0);
    expect(out!.rows, 1);
    expect(out.hole, inInclusiveRange(0, w - 1));
    expect(d.sent, 1);
  });

  test('si lo compensa todo no manda nada', () {
    final d = TsumikiDuel(seed: 1, side: 0)..game.start();
    d.receive(const TsumikiAttack(5, 2));
    final g = d.game;
    for (var y = TsumikiGame.rows - 2; y < TsumikiGame.rows; y++) {
      fillRow(g, y, gap: 0);
    }
    g.current = FallingPiece(TsumikiPiece.i, 1, -2, TsumikiGame.rows - 4 - 2);
    final e = g.hardDrop()!.$2;
    expect(e.rows.length, 2);
    expect(d.onLock(e), isNull);
    expect(g.pendingGarbage, 4);
  });

  test('el medidor carga el doble al que va perdiendo', () {
    LockEvent clear(TsumikiDuel d) {
      fillRow(d.game, TsumikiGame.rows - 1, gap: 0);
      d.game.current = FallingPiece(TsumikiPiece.i, 1, -2, TsumikiGame.rows - 4);
      return d.game.hardDrop()!.$2;
    }

    final even = TsumikiDuel(seed: 1, side: 0)..game.start();
    even.opponentHeight = 5;
    even.onLock(clear(even));
    expect(even.meter, TsumikiDuel.chargePerLine);

    final behind = TsumikiDuel(seed: 1, side: 0)..game.start();
    for (var y = TsumikiGame.rows - 12; y < TsumikiGame.rows - 1; y++) {
      fillRow(behind.game, y, gap: 9);
    }
    behind.opponentHeight = 0;
    expect(behind.catchUp, 2);
    behind.onLock(clear(behind));
    expect(behind.meter, TsumikiDuel.chargePerLine * 2);
  });

  test('las filas recibidas tambien cargan el medidor', () {
    final d = TsumikiDuel(seed: 1, side: 0)..game.start();
    d.receive(const TsumikiAttack(2, 0));
    d.onLock(dropFlat(d.game));
    expect(d.received, 2);
    expect(d.meter, greaterThan(0));
  });

  test('con el medidor lleno se lanza un sabotaje y se vacia', () {
    final d = TsumikiDuel(seed: 1, side: 0)..game.start();
    expect(d.use(TsumikiSabotage.fog), isFalse);
    d.meter = TsumikiDuel.meterFull;
    expect(d.use(TsumikiSabotage.fog), isTrue);
    expect(d.meter, 0);
    expect(d.sabotagesUsed, 1);
  });

  test('los sabotajes recibidos duran lo suyo y se pasan', () {
    final d = TsumikiDuel(seed: 1, side: 0)..game.start();
    final normal = d.game.gravity;
    d.suffer(TsumikiSabotage.rush);
    d.suffer(TsumikiSabotage.lock);
    d.suffer(TsumikiSabotage.blind);
    d.suffer(TsumikiSabotage.fog);
    expect(d.game.gravity, closeTo(normal / TsumikiDuel.rushFactor, 1e-9));
    expect(d.game.hold(), isFalse);
    expect(d.previewHidden, isTrue);
    expect(d.foggy, isTrue);

    d.tick(8.5);
    expect(d.game.gravity, closeTo(normal, 1e-9));
    expect(d.foggy, isFalse);
    expect(d.previewHidden, isTrue);

    d.tick(2);
    expect(d.active, isEmpty);
    expect(d.game.hold(), isTrue);
  });

  test('repetir un sabotaje le vuelve a dar todo el tiempo', () {
    final d = TsumikiDuel(seed: 1, side: 0)..game.start();
    d.suffer(TsumikiSabotage.fog);
    d.tick(6);
    d.suffer(TsumikiSabotage.fog);
    d.tick(6);
    expect(d.foggy, isTrue);
  });
}
