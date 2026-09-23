// Ibasho — el pinball: lanzar, agujeros, dianas, salvabolas, kickbacks, el
// guardian y la partida guardada.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/gacha.dart';
import 'package:ibasho/games/pinball/pinball.dart';

PinballGame _game([List<GachaBall> queue = const [GachaBall(Rarity.sr)]]) =>
    PinballGame(queue: queue, random: math.Random(1), seed: 1);

/// Deja la bola rodando en [at] con [velocity], como si ya hubiera salido
/// del carril hace [since] segundos.
PinballGame _rolling(PinballGame g, Offset at, {Offset velocity = Offset.zero, double since = 0}) {
  g
    ..launch()
    ..ball = at
    ..velocity = velocity
    ..launchedAt = g.time - since;
  return g;
}

List<PinballEvent> _run(PinballGame g, double seconds) {
  final out = <PinballEvent>[];
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    out.addAll(g.tick(1 / 60));
  }
  return out;
}

void main() {
  test('la bola lanzada sale del carril y empieza el salvabolas', () {
    final g = _game()..launch(.6);
    _run(g, 1.5);
    expect(g.phase, PinballPhase.rolling);
    expect(g.ball.dx, lessThan(PinballTable.fieldRight));
    expect(g.saverLeft, inExclusiveRange(0, ballSaverSeconds));
  });

  test('un agujero tapado no se traga la bola', () {
    final g = _game();
    _rolling(g, g.layout.holes[GachaCategory.hats]!);
    _run(g, 1 / 30);
    expect(g.phase, PinballPhase.rolling);
  });

  test('en un agujero abierto cae y da su categoria con la rareza de la bola', () {
    final g = _game();
    _rolling(g, g.layout.holes[GachaCategory.music]!.translate(4, 0));
    g
      ..open.add(GachaCategory.music)
      ..knocked.addAll(<int>[0, 1]);
    final events = _run(g, .2);
    expect(g.phase, PinballPhase.captured);
    expect(events.any((e) => e.kind == PinballEventKind.captured), isTrue);
    final won = g.outcomes.single;
    expect(won.category, GachaCategory.music);
    expect(won.ball.rarity, Rarity.sr);
    // Tras cada bola que entra se tapa todo.
    expect(g.open, isEmpty);
    expect(g.knocked, isEmpty);
  });

  test('la bola dirigida da su categoria caiga donde caiga', () {
    final g = _game(const [GachaBall(Rarity.ssr, category: GachaCategory.backdrops)]);
    _rolling(g, g.layout.holes[GachaCategory.hats]!);
    g.open.add(GachaCategory.hats);
    _run(g, .2);
    expect(g.outcomes.single.category, GachaCategory.backdrops);
  });

  test('tumbar las tres dianas de una categoria abre su agujero', () {
    final g = _game();
    final mine = <int>[
      for (var i = 0; i < g.layout.targets.length; i++)
        if (g.layout.targets[i].category == GachaCategory.accessories) i,
    ];
    expect(mine, hasLength(targetsPerCategory));
    // La bola llega de frente a la cara de la ultima.
    final last = mine.last;
    final a = g.layout.targets[last].angle;
    final face = Offset(-math.sin(a), math.cos(a));
    final target = g.layout.targetAt(last, 0);
    _rolling(g, target + face * (PinballTable.targetThickness + PinballTable.ballRadius + 1), velocity: face * -400);
    g.knocked.addAll(mine.take(2));
    final events = _run(g, .1);
    expect(g.knocked, contains(last));
    expect(g.open, contains(GachaCategory.accessories));
    expect(events.any((e) => e.kind == PinballEventKind.holeOpen && e.category == GachaCategory.accessories), isTrue);
  });

  test('con el salvabolas, la bola que cae vuelve al lanzador', () {
    final g = _rolling(_game(), const Offset(PinballTable.centerX, 815), velocity: const Offset(0, 600));
    final events = _run(g, .2);
    expect(events.any((e) => e.kind == PinballEventKind.saved), isTrue);
    // El Tama la tiene un momento en brazos y luego va al lanzador.
    expect(g.rescueUntil, isNotNull);
    _run(g, PinballGame.rescueHold);
    expect(g.phase, PinballPhase.ready);
    expect(g.outcomes, isEmpty);
  });

  test('sin salvabolas se pierde, y con ella lo tumbado', () {
    final g = _rolling(_game(), const Offset(PinballTable.centerX, 815), velocity: const Offset(0, 600), since: ballSaverSeconds + 1);
    g.knocked.addAll(<int>[0, 4]);
    final events = _run(g, .2);
    expect(events.any((e) => e.kind == PinballEventKind.lost), isTrue);
    expect(g.phase, PinballPhase.lost);
    expect(g.outcomes.single.won, isFalse);
    expect(g.knocked, isEmpty);
  });

  test('las UR, las ∞ y las dirigidas no se pierden: las devuelve el guardian', () {
    for (final ball in const [
      GachaBall(Rarity.ur),
      GachaBall(Rarity.mu),
      GachaBall(Rarity.n, category: GachaCategory.hats),
    ]) {
      final g = _rolling(_game([ball]), const Offset(PinballTable.centerX, 815),
          velocity: const Offset(0, 600), since: ballSaverSeconds + 1);
      final events = _run(g, .2);
      expect(events.any((e) => e.kind == PinballEventKind.guarded), isTrue, reason: ball.rarity.name);
      expect(g.phase, PinballPhase.rolling);
      expect(g.outcomes, isEmpty);
      final thrown = _run(g, PinballGame.rescueHold);
      expect(thrown.any((e) => e.kind == PinballEventKind.thrown), isTrue);
      expect(g.velocity.dy, lessThan(0));
    }
  });

  test('cada 15 golpes de bumper se enciende un kickback, y salta una vez', () {
    final g = _game();
    _rolling(g, Offset.zero);
    g.bumperHits = bumperHitsPerKickback - 1;
    final c = g.layout.bumperAt(0, g.time);
    g
      ..ball = c.translate(0, -PinballTable.bumperRadius - PinballTable.ballRadius + 1)
      ..velocity = const Offset(0, 200);
    final lit = _run(g, 1 / 60);
    expect(lit.any((e) => e.kind == PinballEventKind.kickbackLit), isTrue);
    expect(g.kickbackLeft, isTrue);

    g
      ..ball = const Offset(28, PinballTable.kickbackY + 5)
      ..velocity = const Offset(0, 300);
    final kicked = _run(g, 1 / 60);
    expect(kicked.any((e) => e.kind == PinballEventKind.kickback), isTrue);
    expect(g.velocity.dy, lessThan(0));
    expect(g.kickbackLeft, isFalse);
  });

  test('la partida sigue bola a bola y acaba con la ultima', () {
    final g = _game(const [GachaBall(Rarity.n), GachaBall(Rarity.r)]);
    _rolling(g, const Offset(PinballTable.centerX, 815), velocity: const Offset(0, 600), since: ballSaverSeconds + 1);
    _run(g, .2);
    g.nextBall();
    expect(g.phase, PinballPhase.ready);
    expect(g.current!.rarity, Rarity.r);
    _rolling(g, const Offset(PinballTable.centerX, 815), velocity: const Offset(0, 600), since: ballSaverSeconds + 1);
    _run(g, .2);
    g.nextBall();
    expect(g.isOver, isTrue);
    expect(g.outcomes.length, 2);
  });

  test('la partida guardada vuelve con la cola, lo ganado y lo tumbado', () {
    final g = _game(const [GachaBall(Rarity.n), GachaBall(Rarity.ssr, category: GachaCategory.music), GachaBall(Rarity.ur)]);
    g
      ..outcomes.add(const PinballOutcome(GachaBall(Rarity.n), GachaCategory.hats))
      ..score = 12345
      ..knocked.addAll(<int>[2, 7])
      ..open.add(GachaCategory.backdrops)
      ..kickbackRight = true
      ..bumperHits = 9;
    final back = PinballGame.fromJson(g.toJson())!;
    expect(back.queue.length, 3);
    expect(back.queue[1].category, GachaCategory.music);
    expect(back.outcomes.single.category, GachaCategory.hats);
    expect(back.score, 12345);
    expect(back.knocked, <int>{2, 7});
    expect(back.open, <GachaCategory>{GachaCategory.backdrops});
    expect(back.kickbackRight, isTrue);
    expect(back.bumperHits, 9);
    expect(back.phase, PinballPhase.ready);
    expect(back.current!.rarity, Rarity.ssr);
    // Con la misma mesa.
    expect(back.layout.seed, g.layout.seed);
    expect(back.layout.holes, g.layout.holes);
  });

  test('una partida guardada sin semilla sale con mesa nueva y sin lo tumbado', () {
    final json = _game().toJson()
      ..remove('seed')
      ..['knocked'] = <int>[1, 2];
    final back = PinballGame.fromJson(json)!;
    expect(back.knocked, isEmpty);
  });

  test('cada semilla da su mesa, siempre la misma', () {
    final a = PinballLayout.generate(7), b = PinballLayout.generate(7), c = PinballLayout.generate(8);
    expect(a.holes, b.holes);
    expect(a.posts, b.posts);
    expect(a.targets.map((t) => t.at), b.targets.map((t) => t.at));
    expect(a.holes, isNot(c.holes));
  });

  test('en las mesas generadas nada deja a la bola sin hueco', () {
    const ball = PinballTable.ballRadius * 2;
    for (var seed = 0; seed < 300; seed++) {
      final l = PinballLayout.generate(seed);
      expect(l.holes.length, GachaCategory.values.length);
      expect(l.targets.length, GachaCategory.values.length * targetsPerCategory);
      for (final cat in GachaCategory.values) {
        expect(l.targets.where((t) => t.category == cat), hasLength(targetsPerCategory));
      }
      expect(l.orbits, isNotEmpty);
      expect(l.spinners, isNotEmpty);
      expect(l.springs, isNotEmpty);
      // Los discos (postes, bumpers fijos, coronas y spinners) guardan
      // entre si mas que una bola de hueco.
      final discs = <(Offset, double)>[
        for (final p in l.posts) (p, PinballTable.postRadius),
        for (final b in l.fixedBumpers) (b, PinballTable.fixedBumperRadius),
        for (final o in l.orbits) (o.center, o.radius + PinballTable.bumperRadius),
        for (final (c, half) in l.spinners) (c, half + PinballTable.spinnerThickness),
      ];
      for (var i = 0; i < discs.length; i++) {
        final (p, r) = discs[i];
        expect(p.dx - r, greaterThan(PinballTable.fieldLeft + ball), reason: 'seed $seed');
        // Por encima de la compuerta el campo se abre hasta la cupula.
        if (p.dy - r > PinballTable.gateY) {
          expect(p.dx + r, lessThan(PinballTable.fieldRight - ball), reason: 'seed $seed');
        }
        expect(p.dy + r, lessThanOrEqualTo(PinballTable.playBottom), reason: 'seed $seed');
        for (var j = i + 1; j < discs.length; j++) {
          final (q, s) = discs[j];
          expect((p - q).distance - r - s, greaterThan(ball), reason: 'seed $seed');
        }
      }
      final holes = l.holes.values.toList();
      for (var i = 0; i < holes.length; i++) {
        for (var j = i + 1; j < holes.length; j++) {
          expect((holes[i] - holes[j]).distance, greaterThan(PinballTable.holeRadius * 4), reason: 'seed $seed');
        }
      }
    }
  });

  test('se cancela solo mientras la bola de turno no ha salido', () {
    final g = _game(const [GachaBall(Rarity.n), GachaBall(Rarity.sr), GachaBall(Rarity.ur)]);
    expect(g.canCancel, isTrue);
    expect(g.unplayed.length, 3);
    _rolling(g, const Offset(PinballTable.centerX, 815), velocity: const Offset(0, 600), since: ballSaverSeconds + 1);
    _run(g, .2);
    g.nextBall();
    expect(g.canCancel, isTrue);
    expect(g.unplayed.map((b) => b.rarity), <Rarity>[Rarity.sr, Rarity.ur]);
    g.launch();
    expect(g.canCancel, isFalse);
    // Ni aunque el salvabolas la devuelva al lanzador, ni pausando.
    final back = PinballGame.fromJson(g.toJson())!;
    expect(back.phase, PinballPhase.ready);
    expect(back.canCancel, isFalse);
  });

  test('una bola parada recibe un meneo', () {
    // En equilibrio encima de un poste.
    final g = _game();
    _rolling(g, g.layout.posts.first.translate(0, -PinballTable.postRadius - PinballTable.ballRadius), since: 20);
    final events = _run(g, 3);
    expect(events.any((e) => e.kind == PinballEventKind.nudge), isTrue);
  });

  test('los golpes aceleran el spinner', () {
    final g = _game();
    _rolling(g, g.layout.spinners.first.$1.translate(20, 40), velocity: const Offset(0, -900));
    final events = _run(g, .15);
    expect(events.any((e) => e.kind == PinballEventKind.spinner), isTrue);
  });

  test('una partida guardada rota no se carga', () {
    expect(PinballGame.fromJson(null), isNull);
    expect(PinballGame.fromJson(<String, Object?>{'queue': <Object?>[]}), isNull);
    expect(PinballGame.fromJson(<String, Object?>{'queue': <Object?>[<String, Object?>{'rarity': 'zz'}]}), isNull);
  });

  test('jugando con cuidado, la mayoria de bolas acaban en un agujero', () {
    // Un jugador sencillo: da al flipper del lado de la bola cuando baja
    // cerca. No es la dificultad real, pero avisa si un cambio de la mesa la
    // vuelve imposible o si las bolas dejan de poder entrar.
    var won = 0;
    const games = 30;
    for (var seed = 0; seed < games; seed++) {
      final r = math.Random(seed);
      final g = PinballGame(queue: const [GachaBall(Rarity.n)], random: r, seed: seed)..launch(.3 + r.nextDouble() * .7);
      var t = 0.0, hold = 0.0, cool = 0.0;
      var left = true;
      while (g.phase == PinballPhase.rolling || g.phase == PinballPhase.ready) {
        if (g.phase == PinballPhase.ready) g.launch(.5);
        final b = g.ball;
        if (cool <= 0 && b.dy > 685 && b.dy < 760 && g.velocity.dy > -50) {
          hold = .2;
          cool = .5;
          left = b.dx < PinballTable.centerX;
        }
        hold -= 1 / 60;
        cool -= 1 / 60;
        g
          ..setFlipper(left: true, held: hold > 0 && left)
          ..setFlipper(left: false, held: hold > 0 && !left);
        g.tick(1 / 60);
        t += 1 / 60;
        if (t > 180) break;
      }
      if (g.phase == PinballPhase.captured) won++;
    }
    expect(won / games, greaterThan(.7));
  });
}
