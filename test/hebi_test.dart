// Ibasho — la logica de Hebi: giros, comer, crecer, chocar y monedas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/games/hebi/hebi.dart';
import 'package:ibasho/games/hebi/hebi_store.dart';

void main() {
  test('empieza con tres casillas mirando a la derecha y la comida libre', () {
    final g = HebiGame(seed: 1);
    expect(g.length, HebiGame.startLength);
    expect(g.dir, HebiDir.right);
    expect(g.body.contains(g.food), isFalse);
    expect(g.tick(1), isNull, reason: 'sin empezar no se mueve');
  });

  test('avanza una casilla por intervalo y gira', () {
    final g = HebiGame(seed: 1)..start();
    final (x, y) = g.head;
    g.tick(g.interval + .001);
    expect(g.head, (x + 1, y));
    expect(g.turn(HebiDir.down), isTrue);
    g.step();
    expect(g.head, (x + 1, y + 1));
    expect(g.length, HebiGame.startLength);
  });

  test('no se puede dar media vuelta, pero dos giros seguidos si', () {
    final g = HebiGame(seed: 1)..start();
    expect(g.turn(HebiDir.left), isFalse, reason: 'va a la derecha');
    expect(g.turn(HebiDir.right), isFalse, reason: 'ya va a la derecha');
    expect(g.turn(HebiDir.up), isTrue);
    expect(g.turn(HebiDir.left), isTrue, reason: 'arriba y luego izquierda: media vuelta en dos pasos');
    expect(g.turn(HebiDir.down), isFalse, reason: 'como mucho dos en cola');
    final (x, y) = g.head;
    g
      ..step()
      ..step();
    expect(g.head, (x - 1, y - 1));
    expect(g.isOver, isFalse);
  });

  test('comer crece, sube la cuenta y pone otra comida', () {
    final g = HebiGame(seed: 2)..start();
    final (x, y) = g.head;
    g.food = (x + 1, y);
    final step = g.step();
    expect(step.ate, isNotNull);
    expect(g.length, HebiGame.startLength + 1);
    expect(g.eaten, 1);
    expect(g.food, isNot((x + 1, y)));
    expect(g.body.contains(g.food), isFalse);
  });

  test('cada cinco comidas va mas rapida', () {
    final g = HebiGame(seed: 2)..start();
    final slow = g.interval;
    var sped = false;
    for (var i = 0; i < HebiGame.foodsPerSpeed; i++) {
      final (x, y) = g.head;
      g.food = (x + 1, y);
      sped = g.step().speedUp;
    }
    expect(sped, isTrue);
    expect(g.speed, 2);
    expect(g.interval, lessThan(slow));
    g.boost = true;
    expect(g.interval, closeTo(slow * .92 * .5, 1e-9));
  });

  test('chocar con la pared acaba la partida', () {
    final g = HebiGame(seed: 3)..start();
    g.food = (0, 0);
    var steps = 0;
    while (!g.isOver && steps < 50) {
      g.step();
      steps++;
    }
    expect(g.isOver, isTrue);
    expect(g.head.$1, HebiGame.width - 1, reason: 'se queda en la ultima casilla');
  });

  test('chocar con la cola acaba la partida, pero seguir a la cola no', () {
    final g = HebiGame(seed: 4)..start();
    // Cinco de largo para poder morderse en un cuadrado de 2x2.
    for (var i = 0; i < 2; i++) {
      final (x, y) = g.head;
      g.food = (x + 1, y);
      g.step();
    }
    g.food = (0, 0);
    expect(g.length, 5);
    g.turn(HebiDir.down);
    g.step();
    g.turn(HebiDir.left);
    g.step();
    g.turn(HebiDir.up);
    final last = g.step();
    expect(last.over, isTrue);

    // Con cuatro de largo, la cabeza entra donde estaba la cola: se ha ido.
    final h = HebiGame(seed: 4)..start();
    final (x, y) = h.head;
    h.food = (x + 1, y);
    h.step();
    h.food = (0, 0);
    expect(h.length, 4);
    h.turn(HebiDir.down);
    h.step();
    h.turn(HebiDir.left);
    h.step();
    h.turn(HebiDir.up);
    expect(h.step().over, isFalse);
  });

  test('avisa del peligro cuando va directa a la pared', () {
    final g = HebiGame(seed: 5)..start();
    g.food = (0, 0);
    while (g.head.$1 < HebiGame.width - 1) {
      g.step();
    }
    expect(g.danger, isTrue);
    g.turn(HebiDir.up);
    expect(g.danger, isFalse);
  });

  test('un salto de tiempo grande no da mas de dos pasos', () {
    final g = HebiGame(seed: 6)..start();
    final (x, _) = g.head;
    g.tick(5);
    expect(g.head.$1, x + 2);
  });

  test('monedas por longitud: 15, 30 y 50', () {
    expect(hebiRewardFor(14), 0);
    expect(hebiRewardFor(15), 3);
    expect(hebiRewardFor(29), 3);
    expect(hebiRewardFor(30), 5);
    expect(hebiRewardFor(50), 8);
    expect(hebiRewardFor(225), 8);
  });

  test('los récords guardan la mejor longitud y no estrenan en la primera', () {
    const none = HebiRecords();
    final (first, r1) = none.record(length: 12, eaten: 9, speed: 2, seconds: 30, won: false);
    expect(r1.newRecord, isFalse);
    expect(first.bestLength, 12);
    final (second, r2) = first.record(length: 20, eaten: 17, speed: 4, seconds: 60, won: false);
    expect(r2.newRecord, isTrue);
    expect(second.bestLength, 20);
    expect(second.games, 2);
    expect(second.totalEaten, 26);
    expect(HebiRecords.fromJson(second.toJson()).bestLength, 20);
  });
}
