// Ibasho — pruebas de las vueltas al azar de una ronda de musica.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/audio/audio_service.dart';

void main() {
  test('cada vuelta tiene todas una vez y nunca repite seguidas', () {
    final rng = math.Random(7);
    const items = ['a', 'b', 'c'];
    final orders = <String>{};
    String? last;
    final heard = <String>[];
    for (var i = 0; i < 2000; i++) {
      final round = shuffledRound(items, last, rng);
      expect(round.toSet(), items.toSet());
      expect(round.length, 3);
      orders.add(round.join());
      heard.addAll(round);
      last = round.last;
    }
    for (var i = 1; i < heard.length; i++) {
      expect(heard[i], isNot(heard[i - 1]));
    }
    // Salen órdenes distintos, no siempre el mismo.
    expect(orders.length, 6);
  });

  test('con una sola pista no se cuelga', () {
    expect(shuffledRound(['a'], 'a', math.Random(1)), ['a']);
  });
}
