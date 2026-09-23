// Ibasho — el sorteo del gacha: tasas, garantia de la tirada de once y la
// bola dirigida del Catalogo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';

void main() {
  test('las tasas de cada ticket suman 10000 diezmilesimas', () {
    for (final kind in TicketKind.values) {
      final odds = gachaOdds[kind]!;
      expect(odds.values.fold(0, (a, b) => a + b), 10000, reason: kind.name);
    }
  });

  test('el ticket dorado nunca da bolas comunes', () {
    expect(gachaOdds[TicketKind.kinken]![Rarity.n], 0);
  });

  test('una tanda grande se reparte como dicen las tasas', () {
    final random = math.Random(7);
    final counts = <Rarity, int>{for (final r in Rarity.values) r: 0};
    const draws = 200000;
    for (var i = 0; i < draws; i++) {
      final ball = rollPull(kind: TicketKind.gachaken, balls: 1, random: random).single;
      counts[ball.rarity] = counts[ball.rarity]! + 1;
    }
    // Cada rareza, a menos de un 15 % relativo de lo que promete su tasa (las
    // muy raras se miran solo por encima, que con 200 000 tiradas bailan).
    for (final rarity in <Rarity>[Rarity.n, Rarity.r, Rarity.sr, Rarity.ssr]) {
      final expected = draws * gachaOdds[TicketKind.gachaken]![rarity]! / 10000;
      expect(counts[rarity]! / expected, closeTo(1, .15), reason: rarity.name);
    }
    expect(counts[Rarity.ur]! > 0, isTrue);
  });

  test('la tirada de once del ticket normal asegura un SSR en la ultima bola', () {
    // Una moneda pegada al 0 saca siempre la rareza mas comun.
    final random = _FixedRandom(0);
    final balls = rollPull(kind: TicketKind.gachaken, balls: multiPullBalls, random: random);
    expect(balls.length, 11);
    expect(balls.take(10).every((b) => b.rarity == Rarity.n), isTrue);
    expect(balls.last.rarity, Rarity.ssr);
  });

  test('la del dorado asegura un UR, y en la decima bola', () {
    final random = _FixedRandom(0);
    final balls = rollPull(kind: TicketKind.kinken, balls: multiPullBalls, random: random);
    expect(balls[9].rarity, Rarity.ur);
    expect(balls.where((b) => b.rarity == Rarity.ur).length, 1);
  });

  test('si ya ha salido algo mejor, la garantia no toca nada', () {
    // Un 9999 saca siempre la rareza mas rara.
    final random = _FixedRandom(9999);
    final balls = rollPull(kind: TicketKind.gachaken, balls: multiPullBalls, random: random);
    expect(balls.every((b) => b.rarity == Rarity.mu), isTrue);
  });

  test('tirar ya no da bolas dirigidas: llegan jugando al pinball', () {
    final balls = rollPull(kind: TicketKind.gachaken, balls: multiPullBalls, random: _FixedRandom(0));
    expect(balls.any((b) => b.isWish), isFalse);
  });

  test('el deseo del Catalogo llega hasta UR', () {
    expect(canWish(Rarity.ur), isTrue);
    expect(canWish(Rarity.ssr), isTrue);
    expect(canWish(Rarity.mu), isFalse);
  });

  test('la tirada de once cuesta diez tickets', () {
    expect(pullCost(multiPullBalls), 10);
    expect(pullCost(singlePullBalls), 1);
  });

  test('la semana UTC cambia los jueves a medianoche', () {
    final thursday = DateTime.utc(2026, 9, 24); // jueves
    expect(gachaWeek(thursday), gachaWeek(thursday.add(const Duration(days: 6))));
    expect(gachaWeek(thursday) + 1, gachaWeek(thursday.add(const Duration(days: 7))));
    expect(gachaWeekStart(gachaWeek(thursday)).weekday, DateTime.thursday);
  });
}

/// Un azar que siempre devuelve el mismo numero, para fijar lo que sale.
class _FixedRandom implements math.Random {
  const _FixedRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value % max;

  @override
  double nextDouble() => value / 10000;

  @override
  bool nextBool() => value.isEven;
}
