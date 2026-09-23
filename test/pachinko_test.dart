// Ibasho — tests del pachinko: el tablero del dia, la fisica y la tanda.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/games/pachinko/pachinko.dart';

/// Suelta todas las bolas de [game] en x al azar y deja que caigan.
void _playOut(PachinkoGame game, math.Random random, {double limit = 90}) {
  var t = 0.0;
  while (!game.isOver && t < limit) {
    for (final r in pachinkoRarities) {
      if (game.stockOf(r) > 0) {
        game.drop(PachinkoTable.dropMinX + random.nextDouble() * (PachinkoTable.dropMaxX - PachinkoTable.dropMinX), r);
        break;
      }
    }
    game.tick(1 / 60);
    t += 1 / 60;
  }
}

/// Avanza [seconds] en pasos de 1/60 (un `tick` no pasa de 0,05 s).
void _run(PachinkoGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    game.tick(1 / 60);
  }
}

void main() {
  test('una bola sube como mucho hasta UR y ∞ nunca sale', () {
    expect(pachinkoPrize(Rarity.n, PocketKind.up2), Rarity.sr);
    expect(pachinkoPrize(Rarity.r, PocketKind.up1), Rarity.sr);
    expect(pachinkoPrize(Rarity.ssr, PocketKind.up1), Rarity.ur);
    expect(pachinkoPrize(Rarity.ssr, PocketKind.up2), Rarity.ur);
    expect(pachinkoPrize(Rarity.sr, PocketKind.same), Rarity.sr);
    expect(pachinkoPrize(Rarity.sr, PocketKind.out), isNull);
  });

  test('el tablero es el mismo todo el dia y cambia al siguiente', () {
    final morning = pachinkoDailySeed(DateTime.utc(2026, 9, 23, 1));
    final night = pachinkoDailySeed(DateTime.utc(2026, 9, 23, 23, 59));
    final tomorrow = pachinkoDailySeed(DateTime.utc(2026, 9, 24, 0, 1));
    expect(morning, night);
    expect(morning, isNot(tomorrow));
    final a = PachinkoLayout.generate(morning);
    final b = PachinkoLayout.generate(night);
    expect(a.pins, b.pins);
    expect([for (final p in a.pockets) p.at], [for (final p in b.pockets) p.at]);
    final c = PachinkoLayout.generate(tomorrow);
    expect([for (final p in a.pockets) p.at], isNot([for (final p in c.pockets) p.at]));
  });

  test('cada tablero tiene sus bolsillos y deja pasar a la bola mas gorda', () {
    const ball = 2 * 6.8;
    for (var seed = 0; seed < 200; seed++) {
      final layout = PachinkoLayout.generate(seed);
      expect(layout.pockets.where((p) => p.tulip), hasLength(1), reason: 'seed $seed');
      expect(layout.pockets, hasLength(PachinkoLayout.pocketSpecs.length + 1));
      expect(layout.windmills, hasLength(2));
      // Entre dos clavos, o entre un clavo y el marco, cabe una SSR.
      for (final p in layout.pins) {
        expect(PachinkoTable.inside(p, PachinkoTable.pinRadius + ball), isTrue, reason: 'seed $seed $p');
      }
      // Ningun bolsillo pegado a la pared ni a otro.
      for (final p in layout.pockets) {
        expect(p.at.dx - PachinkoTable.left, greaterThan(40));
        expect(PachinkoTable.right - p.at.dx, greaterThan(40));
        for (final q in layout.pockets) {
          if (!identical(p, q)) expect((p.at - q.at).distance, greaterThan(50));
        }
      }
    }
  });

  test('las bocas: la SSR solo cabe en las grandes y el tulipan es de las N', () {
    for (final r in pachinkoRarities) {
      final d = 2 * pachinkoBallRadius(r);
      for (final e in PachinkoTable.mouths.entries) {
        expect(d <= e.value, e.key.index >= r.index, reason: '${r.name} en boca de ${e.key.name}');
      }
    }
    final tulip = PachinkoLayout.generate(1).pockets.firstWhere((p) => p.tulip);
    expect(tulip.fits, Rarity.n);
  });

  test('una bola que no cabe no entra aunque caiga justo encima', () {
    final game = PachinkoGame(stock: {Rarity.ssr: 1}, seed: 3, random: math.Random(1));
    final small = game.layout.pockets.firstWhere((p) => p.fits == Rarity.n && !p.tulip);
    game.flying.add(PachinkoBall(Rarity.ssr, small.at.translate(0, -14), const Offset(0, 40)));
    game.stock[Rarity.ssr] = 0;
    for (var i = 0; i < 60 * 20 && !game.isOver; i++) {
      game.tick(1 / 60);
    }
    expect(game.isOver, isTrue);
    expect(game.results.single.kind, isNot(PocketKind.up1));
  });

  test('una N que cae en su bolsillo entra', () {
    final game = PachinkoGame(stock: const {}, seed: 3, random: math.Random(1));
    final small = game.layout.pockets.firstWhere((p) => p.fits == Rarity.n && !p.tulip);
    game.flying.add(PachinkoBall(Rarity.n, small.at.translate(0, -3), const Offset(0, 40)));
    for (var i = 0; i < 60 && game.flying.isNotEmpty; i++) {
      game.tick(1 / 60);
    }
    expect(game.results.single.kind, small.kind);
  });

  test('entre bola y bola hay que esperar un poco', () {
    final game = PachinkoGame(stock: {Rarity.n: 3}, seed: 1);
    expect(game.drop(100, Rarity.n), isNotNull);
    expect(game.drop(200, Rarity.n), isNull);
    _run(game, PachinkoGame.dropInterval + .02);
    expect(game.drop(200, Rarity.n), isNotNull);
    expect(game.drop(200, Rarity.r), isNull, reason: 'no hay R cargadas');
    expect(game.stockOf(Rarity.n), 1);
  });

  test('terminar antes devuelve las que quedan tal cual', () {
    final game = PachinkoGame(stock: {Rarity.n: 3, Rarity.sr: 2}, seed: 1, random: math.Random(4));
    game.drop(180, Rarity.n);
    game.end();
    expect(game.ended, isFalse, reason: 'con una bola cayendo no se puede');
    for (var i = 0; i < 60 * 20 && game.flying.isNotEmpty; i++) {
      game.tick(1 / 60);
    }
    game.end();
    expect(game.isOver, isTrue);
    expect(game.drop(180, Rarity.n), isNull);
    final prize = game.results.single.prize;
    final payout = game.payout;
    expect(payout[Rarity.sr], 2 + (prize == Rarity.sr ? 1 : 0));
    expect(payout.values.fold(0, (a, b) => a + b), 4 + (prize == null ? 0 : 1));
  });

  test('la tanda guardada sigue donde estaba, con las bolas en el aire', () {
    final game = PachinkoGame(stock: {Rarity.n: 5, Rarity.ssr: 1}, seed: 9, random: math.Random(2));
    game.drop(120, Rarity.n);
    _run(game, .3);
    game.drop(220, Rarity.ssr);
    _run(game, .1);
    final saved = PachinkoGame.fromJson(game.toJson())!;
    expect(saved.layout.seed, 9);
    expect(saved.stockOf(Rarity.n), 4);
    expect(saved.stockOf(Rarity.ssr), 0);
    expect(saved.loaded, game.loaded);
    expect(saved.flying.length, game.flying.length);
    expect(saved.flying.first.pos, game.flying.first.pos);
    expect(saved.results.length, game.results.length);
  });

  test('una tanda guardada que no cuadra no se carga', () {
    final json = PachinkoGame(stock: {Rarity.n: 5}, seed: 9).toJson();
    json['stock'] = {'n': 6};
    expect(PachinkoGame.fromJson(json), isNull);
  });

  test('en una tanda de 50 todas acaban y lo que vuelve cuadra', () {
    final random = math.Random(11);
    final game = PachinkoGame(
      stock: {Rarity.n: 20, Rarity.r: 15, Rarity.sr: 10, Rarity.ssr: 5},
      seed: 5,
      random: random,
    );
    _playOut(game, random);
    expect(game.isOver, isTrue);
    expect(game.results, hasLength(50));
    final back = game.payout.values.fold(0, (a, b) => a + b);
    expect(back, game.results.where((r) => r.kind != PocketKind.out).length);
    expect(game.payout[Rarity.mu], isNull);
  });

  // La simulacion que afino las bocas: cuanto mas rara la bola, mas se
  // pierde, y la N se queda cerca del 60/10/24/6. Ninguna bola se atasca.
  test('simulacion: se pierde mas cuanto mas rara es la bola', () {
    final random = math.Random(7);
    final out = <Rarity, double>{};
    final byKind = <PocketKind, int>{};
    for (final r in pachinkoRarities) {
      var lost = 0, total = 0;
      for (var s = 0; s < 25; s++) {
        final game = PachinkoGame(stock: {r: 40}, seed: 500 + s, random: random);
        _playOut(game, random);
        expect(game.isOver, isTrue, reason: 'seed ${500 + s} ${r.name}: ${game.flying.map((b) => b.pos)}');
        for (final res in game.results) {
          if (res.kind == PocketKind.out) lost++;
          if (r == Rarity.n) byKind[res.kind] = (byKind[res.kind] ?? 0) + 1;
        }
        total += game.results.length;
      }
      out[r] = lost / total;
    }
    expect(out[Rarity.n], inInclusiveRange(.55, .67));
    expect(out[Rarity.r]!, greaterThan(out[Rarity.n]!));
    expect(out[Rarity.sr]!, greaterThan(out[Rarity.n]!));
    expect(out[Rarity.ssr]!, greaterThan(out[Rarity.sr]!));
    expect(out[Rarity.ssr], greaterThan(.78));
    final n = byKind.values.fold(0, (a, b) => a + b);
    expect(byKind[PocketKind.up2]! / n, inInclusiveRange(.02, .09));
    expect(byKind[PocketKind.up1]! / n, greaterThan(byKind[PocketKind.up2]! / n));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
