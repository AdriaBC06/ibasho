// Ibasho — el pachinko del gacha: el tablero de clavos, su fisica y la tanda.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../backend/gacha.dart';

/// Cuantas bolas caben en una tanda.
const int pachinkoMaxBalls = 50;

/// Las rarezas que entran: ∞ solo sale del gacha, y UR y las dirigidas ya
/// son imperdibles en el pinball.
const List<Rarity> pachinkoRarities = <Rarity>[Rarity.n, Rarity.r, Rarity.sr, Rarity.ssr];

/// Lo mas alto a lo que llega una bola: ∞ solo sale del gacha.
const Rarity pachinkoCeiling = Rarity.ur;

/// Donde acaba una bola.
enum PocketKind {
  /// Se va por abajo: la bola se pierde.
  out,

  /// Vuelve tal cual.
  same,

  /// Sube una rareza.
  up1,

  /// Sube dos.
  up2;

  static PocketKind? byName(Object? raw) {
    for (final k in values) {
      if (k.name == raw) return k;
    }
    return null;
  }
}

/// La rareza con la que sale una bola de [rarity] que cae en [kind], o
/// `null` si se pierde.
Rarity? pachinkoPrize(Rarity rarity, PocketKind kind) {
  final up = switch (kind) {
    PocketKind.out => null,
    PocketKind.same => 0,
    PocketKind.up1 => 1,
    PocketKind.up2 => 2,
  };
  if (up == null) return null;
  return Rarity.values[math.min(rarity.index + up, pachinkoCeiling.index)];
}

/// El radio de una bola. Las raras pesan mas y son un poco mas gordas: les
/// cuesta mas colarse por las bocas de los bolsillos, que es lo que hace que
/// jugarselas no compense.
double pachinkoBallRadius(Rarity rarity) => switch (rarity) {
      Rarity.n => 5.2,
      Rarity.r => 5.7,
      Rarity.sr => 6.2,
      _ => 6.8,
    };

/// Semilla fija para los tests y los recorridos; `null` es la del dia.
@visibleForTesting
int? debugPachinkoSeed;

/// La semilla del tablero de hoy: cambia a las 00:00 UTC.
int pachinkoDailySeed([DateTime? at]) {
  final day = (at ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 86400000;
  // Mezcla el dia para que dos dias seguidos no den tableros parecidos.
  var h = day * 0x9E3779B1;
  h = (h ^ (h >> 15)) * 0x85EBCA77;
  return (h ^ (h >> 13)) & 0x3fffffff;
}

// --- El tablero ---------------------------------------------------------------

/// Una pared: un segmento con grosor.
@immutable
class PachinkoWall {
  const PachinkoWall(this.a, this.b, {this.thickness = 2});

  final Offset a;
  final Offset b;
  final double thickness;
}

/// Un bolsillo: una boca entre dos labios en [at] (el centro de la boca) y
/// un cubo debajo. [gap] es el hueco libre entre los labios.
@immutable
class Pocket {
  const Pocket(this.kind, this.at, this.gap, {this.tulip = false});

  final PocketKind kind;
  final Offset at;
  final double gap;

  /// El de +2 lleva tulipan: dos alas que se abren y se cierran.
  final bool tulip;

  /// La rareza mas alta que cabe por la boca.
  Rarity get fits {
    var best = Rarity.n;
    for (final e in PachinkoTable.mouths.entries) {
      if (e.value <= gap + .01 && e.key.index > best.index) best = e.key;
    }
    return best;
  }

  Offset get leftLip => at.translate(-gap / 2 - PachinkoTable.lipRadius, 0);
  Offset get rightLip => at.translate(gap / 2 + PachinkoTable.lipRadius, 0);

  /// Los brazos del embudo, de cada labio hacia arriba y hacia fuera (el
  /// del tulipan son sus alas).
  List<PachinkoWall> get arms => tulip
      ? const <PachinkoWall>[]
      : <PachinkoWall>[
          PachinkoWall(leftLip, leftLip.translate(-PachinkoTable.armLength, -PachinkoTable.armLength)),
          PachinkoWall(rightLip, rightLip.translate(PachinkoTable.armLength, -PachinkoTable.armLength)),
        ];

  /// El tejadillo que ve una bola que no cabe: de labio a labio con un pico
  /// en medio, para que resbale y no se quede posada.
  List<PachinkoWall> get roof => <PachinkoWall>[
        PachinkoWall(leftLip, at.translate(0, -3)),
        PachinkoWall(at.translate(0, -3), rightLip),
      ];

  /// Las paredes del cubo, de cada labio hacia abajo.
  List<PachinkoWall> get cup => <PachinkoWall>[
        PachinkoWall(leftLip, leftLip.translate(1.5, PachinkoTable.cupDepth)),
        PachinkoWall(rightLip, rightLip.translate(-1.5, PachinkoTable.cupDepth)),
        PachinkoWall(
          leftLip.translate(1.5, PachinkoTable.cupDepth),
          rightLip.translate(-1.5, PachinkoTable.cupDepth),
        ),
      ];
}

/// Un molinillo de cuatro aspas que gira con las bolas que lo golpean.
@immutable
class Windmill {
  const Windmill(this.center);

  final Offset center;
}

/// Lo fijo: el marco con las esquinas de arriba redondeadas, el riel por
/// donde se sueltan las bolas y la salida de abajo. En unidades de mundo
/// (360 × 600, y hacia abajo).
abstract final class PachinkoTable {
  static const double width = 360;
  static const double height = 600;

  static const double left = 8;
  static const double right = 352;
  static const double top = 8;
  static const double corner = 70;

  /// La altura a la que se sueltan las bolas y hasta donde se puede soltar.
  static const double dropY = 24;
  static const double dropMinX = 42;
  static const double dropMaxX = 318;

  /// Por debajo de aqui la bola se ha ido por la salida.
  static const double outY = 578;

  static const double pinRadius = 2.2;
  static const double lipRadius = 2.5;
  static const double cupDepth = 13;
  static const double bladeLength = 12;
  static const double bladeThickness = 1.8;
  static const double tulipWing = 13;
  static const double armLength = 6;

  /// Las bocas de los bolsillos, por la rareza mas alta que cabe: una bola
  /// mas gorda no pasa entre los labios. Justas para que quepa con poco
  /// margen (los diametros son 10,4 · 11,4 · 12,4 · 13,6).
  static const Map<Rarity, double> mouths = <Rarity, double>{
    Rarity.n: 11.0,
    Rarity.r: 12.0,
    Rarity.sr: 13.0,
    Rarity.ssr: 14.4,
  };

  static final List<PachinkoWall> frame = List<PachinkoWall>.unmodifiable(_buildFrame());

  static List<PachinkoWall> _buildFrame() {
    final walls = <PachinkoWall>[];
    final points = <Offset>[const Offset(left, height + 20), const Offset(left, top + corner)];
    for (var i = 1; i <= 12; i++) {
      final a = math.pi + i / 12 * math.pi / 2;
      points.add(Offset(left + corner + math.cos(a) * corner, top + corner + math.sin(a) * corner));
    }
    for (var i = 0; i <= 12; i++) {
      final a = 1.5 * math.pi + i / 12 * math.pi / 2;
      points.add(Offset(right - corner + math.cos(a) * corner, top + corner + math.sin(a) * corner));
    }
    points.add(const Offset(right, height + 20));
    for (var i = 0; i < points.length - 1; i++) {
      walls.add(PachinkoWall(points[i], points[i + 1], thickness: 3));
    }
    return walls;
  }

  /// Si [p] esta dentro del marco con [margin] de sobra.
  static bool inside(Offset p, double margin) {
    if (p.dx < left + margin || p.dx > right - margin || p.dy < top + margin) return false;
    for (final c in <Offset>[const Offset(left + corner, top + corner), const Offset(right - corner, top + corner)]) {
      final inCorner = (p.dx < c.dx && c.dx < width / 2 || p.dx > c.dx && c.dx > width / 2) && p.dy < c.dy;
      if (inCorner && (p - c).distance > corner - margin) return false;
    }
    return true;
  }
}

/// El tablero de un dia: clavos, bolsillos y molinillos, sacados de una
/// semilla. La misma semilla da siempre el mismo tablero.
@immutable
class PachinkoLayout {
  const PachinkoLayout._({
    required this.seed,
    required this.pins,
    required this.pockets,
    required this.windmills,
  });

  final int seed;
  final List<Offset> pins;
  final List<Pocket> pockets;
  final List<Windmill> windmills;

  /// Los bolsillos de cada tablero: de que tipo son y la rareza mas alta
  /// que cabe por su boca. Cuanto mas alta la bola, menos bolsillos le
  /// valen: asi pierde mas (una N se pierde 3 de cada 5 veces; una SSR, casi
  /// 9 de cada 10). El de +2 es el del tulipan.
  static const List<(PocketKind, Rarity)> pocketSpecs = <(PocketKind, Rarity)>[
    (PocketKind.same, Rarity.ssr),
    (PocketKind.same, Rarity.sr),
    (PocketKind.up1, Rarity.ssr),
    (PocketKind.up1, Rarity.sr),
    (PocketKind.up1, Rarity.r),
    (PocketKind.up1, Rarity.n),
  ];
  static const Rarity tulipFits = Rarity.n;

  factory PachinkoLayout.generate(int seed) {
    final random = math.Random(seed);
    while (true) {
      final layout = _attempt(seed, random);
      if (layout != null) return layout;
    }
  }

  static PachinkoLayout? _attempt(int seed, math.Random random) {
    double between(double a, double b) => a + random.nextDouble() * (b - a);

    // Los bolsillos, en la mitad de abajo y separados entre si. El de +2 va
    // cerca del centro, como el «start» de un pachinko de verdad.
    final pockets = <Pocket>[];
    final up2 = Pocket(
      PocketKind.up2,
      Offset(between(140, 220), between(450, 500)),
      PachinkoTable.mouths[tulipFits]!,
      tulip: true,
    );
    pockets.add(up2);
    final specs = List<(PocketKind, Rarity)>.of(pocketSpecs)..shuffle(random);
    for (final (kind, fits) in specs) {
      Pocket? placed;
      for (var tries = 0; tries < 300 && placed == null; tries++) {
        final p = Offset(between(54, 306), between(330, 540));
        if (pockets.every((q) => (q.at - p).distance > 52)) {
          placed = Pocket(kind, p, PachinkoTable.mouths[fits]!);
        }
      }
      if (placed == null) return null;
      pockets.add(placed);
    }

    // Dos molinillos, a los lados de la mitad de arriba.
    final windmills = <Windmill>[];
    for (final side in <bool>[true, false]) {
      final x = side ? between(80, 150) : between(210, 280);
      final c = Offset(x, between(140, 250));
      if (pockets.any((p) => (p.at - c).distance < 60)) return null;
      windmills.add(Windmill(c));
    }

    // Los clavos: una rejilla al tresbolillo con algun hueco, apartada del
    // marco, los bolsillos y los molinillos para que ninguna bola se atasque.
    final rowH = between(19, 22);
    final colW = between(23, 26);
    final shift = random.nextDouble() * colW;
    final holes = between(.05, .12);
    final pins = <Offset>[];
    var row = 0;
    for (var y = 62.0; y < 548; y += rowH, row++) {
      final offset = shift + (row.isOdd ? colW / 2 : 0);
      for (var x = offset; x < PachinkoTable.width; x += colW) {
        final p = Offset(x + between(-1.5, 1.5), y + between(-1, 1));
        if (!PachinkoTable.inside(p, 21)) continue;
        if (random.nextDouble() < holes) continue;
        if (windmills.any((w) => (w.center - p).distance < PachinkoTable.bladeLength + 20)) continue;
        if (pockets.any((q) => _nearPocket(q, p))) continue;
        pins.add(p);
      }
    }
    return PachinkoLayout._(
      seed: seed,
      pins: List<Offset>.unmodifiable(pins),
      pockets: List<Pocket>.unmodifiable(pockets),
      windmills: List<Windmill>.unmodifiable(windmills),
    );
  }

  /// Si un clavo en [p] estorbaria al bolsillo [q]: nada en la boca ni al
  /// lado del cubo, y encima solo lo bastante lejos para que pase una bola.
  static bool _nearPocket(Pocket q, Offset p) {
    final dx = (p.dx - q.at.dx).abs();
    final half = q.gap / 2 + PachinkoTable.lipRadius;
    final reach = (q.tulip ? PachinkoTable.tulipWing : PachinkoTable.armLength) + 20;
    if (p.dy > q.at.dy - reach && p.dy < q.at.dy + PachinkoTable.cupDepth + 20) return dx < half + (q.tulip ? 0 : PachinkoTable.armLength) + 20;
    return false;
  }
}

// --- La tanda -----------------------------------------------------------------

/// Una bola en el aire.
class PachinkoBall {
  PachinkoBall(this.rarity, this.pos, this.velocity, {this.spin = 0});

  final Rarity rarity;
  Offset pos;
  Offset velocity;
  double spin;
  double spinRate = 0;

  /// Para ver si se ha quedado quieta: donde estaba y desde cuando.
  Offset anchor = Offset.zero;
  double anchorAt = 0;

  /// Meneos seguidos en el mismo sitio: cada uno empuja mas fuerte.
  int nudges = 0;
  Offset nudgedAt = const Offset(-99, -99);

  double get radius => pachinkoBallRadius(rarity);

  Map<String, Object?> toJson() => <String, Object?>{
        'r': rarity.name,
        'x': pos.dx,
        'y': pos.dy,
        'vx': velocity.dx,
        'vy': velocity.dy,
      };

  static PachinkoBall? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rarity = Rarity.byName(raw['r']);
    double n(Object? v) => v is num ? v.toDouble() : 0;
    if (rarity == null) return null;
    return PachinkoBall(rarity, Offset(n(raw['x']), n(raw['y'])), Offset(n(raw['vx']), n(raw['vy'])));
  }
}

/// Como ha acabado una bola.
@immutable
class PachinkoResult {
  const PachinkoResult(this.rarity, this.kind);

  final Rarity rarity;
  final PocketKind kind;

  Rarity? get prize => pachinkoPrize(rarity, kind);

  Map<String, Object?> toJson() => <String, Object?>{'r': rarity.name, 'k': kind.name};

  static PachinkoResult? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rarity = Rarity.byName(raw['r']);
    final kind = PocketKind.byName(raw['k']);
    if (rarity == null || kind == null) return null;
    return PachinkoResult(rarity, kind);
  }
}

enum PachinkoEventKind { drop, pin, windmill, wall, ball, tulip, pocket, out, nudge }

@immutable
class PachinkoEvent {
  const PachinkoEvent(this.kind, this.at, {this.index, this.rarity, this.pocket});

  final PachinkoEventKind kind;
  final Offset at;
  final int? index;

  /// La rareza de la bola, en `pocket` y `out`.
  final Rarity? rarity;
  final PocketKind? pocket;
}

/// Una tanda: las bolas cargadas que quedan por soltar, las que caen y lo
/// que ha salido. Se suelta tocando arriba; la fisica decide el resto.
class PachinkoGame {
  PachinkoGame({
    required Map<Rarity, int> stock,
    int? seed,
    math.Random? random,
  })  : stock = <Rarity, int>{for (final r in pachinkoRarities) r: stock[r] ?? 0},
        loaded = <Rarity, int>{for (final r in pachinkoRarities) r: stock[r] ?? 0},
        layout = PachinkoLayout.generate(seed ?? debugPachinkoSeed ?? pachinkoDailySeed()),
        _random = random ?? math.Random() {
    windmillAngles = List<double>.generate(layout.windmills.length, (i) => i * .4);
    _windmillOmegas = List<double>.filled(layout.windmills.length, 0);
    _pinHitAt = List<double>.filled(layout.pins.length, -9);
    _buildGrid();
  }

  final PachinkoLayout layout;
  final math.Random _random;

  /// Lo cargado al empezar, por rareza.
  final Map<Rarity, int> loaded;

  /// Lo que queda por soltar.
  final Map<Rarity, int> stock;

  final List<PachinkoBall> flying = <PachinkoBall>[];
  final List<PachinkoResult> results = <PachinkoResult>[];

  late final List<double> windmillAngles;
  late final List<double> _windmillOmegas;
  late final List<double> _pinHitAt;
  double time = 0;
  double _lastDrop = -9;

  int get total => loaded.values.fold(0, (a, b) => a + b);
  int get left => stock.values.fold(0, (a, b) => a + b);
  int stockOf(Rarity r) => stock[r] ?? 0;

  /// Se ha terminado antes de soltarlas todas: las que quedan vuelven
  /// tal cual.
  bool ended = false;

  /// No queda nada por soltar (o se ha terminado antes) ni cayendo.
  bool get isOver => (left == 0 || ended) && flying.isEmpty;

  /// Termina la tanda sin soltar las que quedan. Solo sin bolas cayendo.
  void end() {
    if (flying.isEmpty) ended = true;
  }

  /// Lo que vuelve al deposito: los premios y, si se acaba antes, las bolas
  /// sin soltar tal cual.
  Map<Rarity, int> get payout {
    final out = <Rarity, int>{};
    for (final r in results) {
      final prize = r.prize;
      if (prize != null) out[prize] = (out[prize] ?? 0) + 1;
    }
    for (final e in stock.entries) {
      if (e.value > 0) out[e.key] = (out[e.key] ?? 0) + e.value;
    }
    return out;
  }

  /// Cuanto hay que esperar entre bola y bola.
  static const double dropInterval = .16;

  /// Si ahora se puede soltar una bola de [rarity].
  bool canDrop(Rarity rarity) => !ended && stockOf(rarity) > 0 && time - _lastDrop >= dropInterval;

  /// Suelta una bola de [rarity] en la x [x] (se ajusta al riel).
  PachinkoEvent? drop(double x, Rarity rarity) {
    if (!canDrop(rarity)) return null;
    final at = Offset(x.clamp(PachinkoTable.dropMinX, PachinkoTable.dropMaxX), PachinkoTable.dropY);
    // Una bola recien soltada ahi mismo: se espera a que baje.
    if (flying.any((b) => (b.pos - at).distance < b.radius * 2 + 2)) return null;
    stock[rarity] = stockOf(rarity) - 1;
    _lastDrop = time;
    final ball = PachinkoBall(rarity, at, Offset((_random.nextDouble() - .5) * 8, 30))
      ..anchor = at
      ..anchorAt = time;
    flying.add(ball);
    return PachinkoEvent(PachinkoEventKind.drop, at, rarity: rarity);
  }

  // --- Reloj ------------------------------------------------------------------

  static const double _step = 1 / 240;
  static const double _gravity = 520;
  static const double _maxSpeed = 900;
  double _acc = 0;

  /// Segundos parada (en menos de [_stallRadius]) antes del meneo.
  static const double _stallTime = 1.2;
  static const double _stallRadius = 6;

  /// Avanza [dt] segundos y devuelve lo que ha pasado.
  List<PachinkoEvent> tick(double dt) {
    final events = <PachinkoEvent>[];
    _acc += math.min(dt, .05);
    while (_acc >= _step) {
      _acc -= _step;
      _substep(events);
    }
    return events;
  }

  void _substep(List<PachinkoEvent> events) {
    const h = _step;
    time += h;
    _moveWindmills(h);
    for (final b in flying) {
      b.velocity = b.velocity.translate(0, _gravity * h);
      final speed = b.velocity.distance;
      if (speed > _maxSpeed) b.velocity = b.velocity * (_maxSpeed / speed);
      b.velocity = b.velocity * math.exp(-.08 * h);
      b.pos += b.velocity * h;
      b.spinRate *= math.exp(-.5 * h);
      b.spin += b.spinRate * h;
      _collideFrame(b, events);
      _collidePins(b, events);
      _collidePockets(b, events);
      _collideWindmills(b, events);
    }
    _collideBalls(events);
    for (var i = flying.length - 1; i >= 0; i--) {
      final b = flying[i];
      if (_checkPockets(b, events) || _checkOut(b, events) || _checkJammed(b, events)) {
        flying.removeAt(i);
      } else {
        _checkStall(b, events);
      }
    }
  }

  // --- Choques ----------------------------------------------------------------

  /// Rejilla de clavos por celdas, para no mirar los cuatrocientos en cada
  /// paso de cada bola.
  static const double _cell = 24;
  late final Map<int, List<int>> _grid;

  void _buildGrid() {
    _grid = <int, List<int>>{};
    for (var i = 0; i < layout.pins.length; i++) {
      final p = layout.pins[i];
      _grid.putIfAbsent(_key(p.dx ~/ _cell, p.dy ~/ _cell), () => <int>[]).add(i);
    }
  }

  static int _key(int cx, int cy) => cy * 64 + cx;

  void _roll(PachinkoBall b, Offset n, Offset tangent) {
    final rate = (n.dx * tangent.dy - n.dy * tangent.dx) / b.radius;
    b.spinRate += (rate - b.spinRate) * .6;
  }

  /// Gira [v] un angulo al azar de hasta [spread] radianes a cada lado.
  Offset _jitter(Offset v, double spread) {
    final a = (_random.nextDouble() - .5) * 2 * spread;
    final c = math.cos(a), s = math.sin(a);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  /// Choca [b] contra un circulo quieto. Devuelve la velocidad normal de
  /// entrada (negativa) o `null` si no ha tocado.
  double? _circle(PachinkoBall b, Offset c, double radius, {double restitution = .45}) {
    final d = b.pos - c;
    final dist = d.distance;
    final reach = b.radius + radius;
    if (dist >= reach || dist == 0) return null;
    final n = d / dist;
    b.pos = c + n * reach;
    final vn = b.velocity.dx * n.dx + b.velocity.dy * n.dy;
    if (vn >= 0) return 0;
    final tangent = b.velocity - n * vn;
    b.velocity = tangent * .97 - n * (vn * restitution);
    _roll(b, n, tangent);
    return vn;
  }

  /// Choca [b] contra la capsula `a–c` de grosor [t]; [surface] da la
  /// velocidad de la superficie en un punto (molinillos y tulipan).
  double? _capsule(
    PachinkoBall b,
    Offset a,
    Offset c,
    double t, {
    double restitution = .35,
    Offset Function(Offset p)? surface,
  }) {
    final ac = c - a;
    final len2 = ac.distanceSquared;
    final u = len2 == 0 ? 0.0 : (((b.pos - a).dx * ac.dx + (b.pos - a).dy * ac.dy) / len2).clamp(0.0, 1.0);
    final p = a + ac * u;
    final d = b.pos - p;
    final dist = d.distance;
    final reach = b.radius + t;
    if (dist >= reach || dist == 0) return null;
    final n = d / dist;
    b.pos = p + n * reach;
    final vs = surface?.call(p) ?? Offset.zero;
    final rel = b.velocity - vs;
    final vn = rel.dx * n.dx + rel.dy * n.dy;
    if (vn >= 0) return 0;
    final tangent = rel - n * vn;
    b.velocity = vs + tangent * .97 - n * (vn * restitution);
    _roll(b, n, tangent);
    return vn;
  }

  void _collideFrame(PachinkoBall b, List<PachinkoEvent> events) {
    // Solo cerca del borde merece la pena mirar el marco.
    if (PachinkoTable.inside(b.pos, b.radius + 6)) return;
    for (final w in PachinkoTable.frame) {
      final vn = _capsule(b, w.a, w.b, w.thickness);
      if (vn != null && vn < -140) events.add(PachinkoEvent(PachinkoEventKind.wall, b.pos));
    }
  }

  void _collidePins(PachinkoBall b, List<PachinkoEvent> events) {
    final cx = b.pos.dx ~/ _cell;
    final cy = b.pos.dy ~/ _cell;
    for (var y = cy - 1; y <= cy + 1; y++) {
      for (var x = cx - 1; x <= cx + 1; x++) {
        final cell = _grid[_key(x, y)];
        if (cell == null) continue;
        for (final i in cell) {
          final vn = _circle(b, layout.pins[i], PachinkoTable.pinRadius);
          if (vn == null) continue;
          if (vn < -30) b.velocity = _jitter(b.velocity, .18);
          if (vn < -60 && time - _pinHitAt[i] > .05) {
            _pinHitAt[i] = time;
            events.add(PachinkoEvent(PachinkoEventKind.pin, layout.pins[i], index: i));
          }
        }
      }
    }
  }

  /// Cuanto de abierto esta el tulipan (0 cerrado, 1 abierto): se abre
  /// un rato cada pocos segundos.
  double get tulipOpen {
    const period = 3.6;
    final t = time % period;
    if (t < 1.8) return 0;
    if (t < 2.0) return (t - 1.8) / .2;
    if (t < 3.4) return 1;
    return 1 - (t - 3.4) / .2;
  }

  /// Las alas del tulipan de [p]: de cada labio hacia arriba, cerradas casi
  /// de pie y abiertas hacia fuera.
  (Offset, Offset, Offset, Offset) tulipWings(Pocket p) {
    final a = .12 + tulipOpen * .6;
    const l = PachinkoTable.tulipWing;
    return (
      p.leftLip,
      p.leftLip + Offset(-math.sin(a), -math.cos(a)) * l,
      p.rightLip,
      p.rightLip + Offset(math.sin(a), -math.cos(a)) * l,
    );
  }

  double _lastTulip = -1;

  void _collidePockets(PachinkoBall b, List<PachinkoEvent> events) {
    for (var i = 0; i < layout.pockets.length; i++) {
      final p = layout.pockets[i];
      if ((b.pos - p.at).distanceSquared > 40 * 40) continue;
      _circle(b, p.leftLip, PachinkoTable.lipRadius, restitution: .4);
      _circle(b, p.rightLip, PachinkoTable.lipRadius, restitution: .4);
      for (final w in p.arms) {
        _capsule(b, w.a, w.b, w.thickness);
      }
      // Si no cabe, la boca esta cerrada para ella.
      if (b.radius * 2 > p.gap) {
        for (final w in p.roof) {
          _capsule(b, w.a, w.b, PachinkoTable.lipRadius);
        }
      }
      for (final w in p.cup) {
        _capsule(b, w.a, w.b, w.thickness);
      }
      if (p.tulip) {
        final (la, lb, ra, rb) = tulipWings(p);
        final l = _capsule(b, la, lb, 1.6);
        final r = _capsule(b, ra, rb, 1.6);
        // Una bola que no cabe no se mete entre las alas: rebota en ellas.
        if (b.radius * 2 > p.gap) {
          final peak = Offset((lb.dx + rb.dx) / 2, lb.dy - 3);
          _capsule(b, lb, peak, 1.6);
          _capsule(b, peak, rb, 1.6);
        }
        if (((l ?? 0) < -60 || (r ?? 0) < -60) && time - _lastTulip > .1) {
          _lastTulip = time;
          events.add(PachinkoEvent(PachinkoEventKind.tulip, b.pos, index: i));
        }
      }
    }
  }

  void _moveWindmills(double h) {
    for (var i = 0; i < windmillAngles.length; i++) {
      _windmillOmegas[i] *= math.exp(-.7 * h);
      windmillAngles[i] = (windmillAngles[i] + _windmillOmegas[i] * h) % (2 * math.pi);
    }
  }

  /// Las cuatro aspas del molinillo [i]: de su centro hacia fuera.
  List<Offset> windmillTips(int i) {
    final c = layout.windmills[i].center;
    return <Offset>[
      for (var k = 0; k < 4; k++)
        c + Offset(math.cos(windmillAngles[i] + k * math.pi / 2), math.sin(windmillAngles[i] + k * math.pi / 2)) *
            PachinkoTable.bladeLength,
    ];
  }

  void _collideWindmills(PachinkoBall b, List<PachinkoEvent> events) {
    for (var i = 0; i < layout.windmills.length; i++) {
      final c = layout.windmills[i].center;
      if ((b.pos - c).distance > PachinkoTable.bladeLength + b.radius + 3) continue;
      final omega = _windmillOmegas[i];
      for (final tip in windmillTips(i)) {
        final before = b.velocity;
        final vn = _capsule(
          b,
          c,
          tip,
          PachinkoTable.bladeThickness,
          restitution: .4,
          surface: (p) => Offset(-(p.dy - c.dy), p.dx - c.dx) * omega,
        );
        if (vn == null || vn > -20) continue;
        final dv = before - b.velocity;
        final r = b.pos - c;
        _windmillOmegas[i] = (omega + (r.dx * dv.dy - r.dy * dv.dx) * .004).clamp(-18.0, 18.0);
        events.add(PachinkoEvent(PachinkoEventKind.windmill, c, index: i));
      }
    }
  }

  void _collideBalls(List<PachinkoEvent> events) {
    for (var i = 0; i < flying.length; i++) {
      for (var j = i + 1; j < flying.length; j++) {
        final a = flying[i], b = flying[j];
        final d = b.pos - a.pos;
        final dist = d.distance;
        final reach = a.radius + b.radius;
        if (dist >= reach || dist == 0) continue;
        final n = d / dist;
        final ma = a.radius * a.radius, mb = b.radius * b.radius;
        final overlap = reach - dist;
        a.pos -= n * (overlap * mb / (ma + mb));
        b.pos += n * (overlap * ma / (ma + mb));
        final rel = b.velocity - a.velocity;
        final vn = rel.dx * n.dx + rel.dy * n.dy;
        if (vn >= 0) continue;
        final j0 = -(1 + .5) * vn / (1 / ma + 1 / mb);
        a.velocity -= n * (j0 / ma);
        b.velocity += n * (j0 / mb);
        if (vn < -80) events.add(PachinkoEvent(PachinkoEventKind.ball, a.pos + d / 2));
      }
    }
  }

  // --- Donde acaba --------------------------------------------------------------

  bool _checkPockets(PachinkoBall b, List<PachinkoEvent> events) {
    for (var i = 0; i < layout.pockets.length; i++) {
      final p = layout.pockets[i];
      if (b.pos.dy < p.at.dy + 3 || b.pos.dy > p.at.dy + PachinkoTable.cupDepth + 4) continue;
      if ((b.pos.dx - p.at.dx).abs() > p.gap / 2 + PachinkoTable.lipRadius) continue;
      if (b.radius * 2 > p.gap) continue;
      results.add(PachinkoResult(b.rarity, p.kind));
      events.add(PachinkoEvent(PachinkoEventKind.pocket, p.at, index: i, rarity: b.rarity, pocket: p.kind));
      return true;
    }
    return false;
  }

  bool _checkOut(PachinkoBall b, List<PachinkoEvent> events) {
    if (b.pos.dy < PachinkoTable.outY) return false;
    results.add(PachinkoResult(b.rarity, PocketKind.out));
    events.add(PachinkoEvent(PachinkoEventKind.out, b.pos, rarity: b.rarity, pocket: PocketKind.out));
    return true;
  }

  /// Una bola que ni con diez meneos sale de donde esta (no deberia pasar:
  /// el tablero deja sitio a la mas gorda) cuenta como perdida, para que la
  /// tanda nunca se quede sin acabar.
  bool _checkJammed(PachinkoBall b, List<PachinkoEvent> events) {
    if (b.nudges < 10) return false;
    results.add(PachinkoResult(b.rarity, PocketKind.out));
    events.add(PachinkoEvent(PachinkoEventKind.out, b.pos, rarity: b.rarity, pocket: PocketKind.out));
    return true;
  }

  /// Una bola que no se mueve (encajada entre un clavo y otra bola, o
  /// posada en un labio) recibe un meneo pequeño.
  void _checkStall(PachinkoBall b, List<PachinkoEvent> events) {
    if ((b.pos - b.anchor).distance > _stallRadius) {
      b
        ..anchor = b.pos
        ..anchorAt = time;
      return;
    }
    if (time - b.anchorAt < _stallTime) return;
    b.nudges = (b.pos - b.nudgedAt).distance < 30 ? b.nudges + 1 : 0;
    final push = 1.0 + b.nudges;
    b
      ..velocity = Offset(
        (_random.nextBool() ? 1 : -1) * (60 + _random.nextDouble() * 60) * math.min(push, 3),
        -60 * math.min(push, 5),
      )
      ..nudgedAt = b.pos
      ..anchor = b.pos
      ..anchorAt = time;
    events.add(PachinkoEvent(PachinkoEventKind.nudge, b.pos));
  }

  // --- Guardar ----------------------------------------------------------------

  /// Se guarda al pausar: la semilla, lo que queda, lo que ha salido y las
  /// bolas que estaban cayendo (siguen desde ahi).
  Map<String, Object?> toJson() => <String, Object?>{
        'seed': layout.seed,
        'loaded': {for (final e in loaded.entries) e.key.name: e.value},
        'stock': {for (final e in stock.entries) e.key.name: e.value},
        'results': [for (final r in results) r.toJson()],
        'flying': [for (final b in flying) b.toJson()],
        if (ended) 'ended': true,
      };

  static PachinkoGame? fromJson(Object? raw, {math.Random? random}) {
    if (raw is! Map) return null;
    final seed = raw['seed'];
    if (seed is! num) return null;
    Map<Rarity, int> counts(Object? m) => <Rarity, int>{
          if (m is Map)
            for (final e in m.entries)
              if (Rarity.byName(e.key) != null && e.value is num) Rarity.byName(e.key)!: (e.value as num).toInt(),
        };
    final game = PachinkoGame(stock: counts(raw['loaded']), seed: seed.toInt(), random: random);
    game.stock
      ..clear()
      ..addAll(<Rarity, int>{for (final r in pachinkoRarities) r: counts(raw['stock'])[r] ?? 0});
    final results = raw['results'];
    if (results is List) {
      for (final r in results) {
        final parsed = PachinkoResult.fromJson(r);
        if (parsed != null) game.results.add(parsed);
      }
    }
    game.ended = raw['ended'] == true;
    final flying = raw['flying'];
    if (flying is List) {
      for (final b in flying) {
        final parsed = PachinkoBall.fromJson(b);
        if (parsed != null) {
          game.flying.add(parsed
            ..anchor = parsed.pos
            ..anchorAt = 0);
        }
      }
    }
    // Lo guardado tiene que cuadrar con lo cargado; si no, no se fia.
    if (game.results.length + game.flying.length + game.left != game.total) return null;
    return game;
  }
}
