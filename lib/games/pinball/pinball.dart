// Ibasho — el pinball del gacha: la mesa, su fisica y la partida.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../backend/gacha.dart';

/// Cuantas bolas caben en la cola de una partida.
const int pinballQueueMax = 5;

/// Segundos de salvabolas desde que la bola sale del carril de lanzamiento.
const double ballSaverSeconds = 10;

/// Golpes de bumper que encienden un kickback.
const int bumperHitsPerKickback = 15;

/// Dianas de cada categoria: tumbarlas todas abre su agujero.
const int targetsPerCategory = 3;

/// Si una bola no se puede perder: las UR, las ∞ y las dirigidas del
/// Catalogo tienen un Tama guardian en el desague.
bool isGuarded(GachaBall ball) => ball.isWish || ball.rarity.index >= Rarity.ur.index;

// --- La mesa ------------------------------------------------------------------

/// Una pared: un segmento con grosor. Si [oneWay] es verdad solo choca por el
/// lado de su normal (izquierda de `a → b`), como la compuerta del carril.
@immutable
class Wall {
  const Wall(this.a, this.b, {this.thickness = 2, this.oneWay = false, this.kick = 0});

  final Offset a;
  final Offset b;
  final double thickness;
  final bool oneWay;

  /// Empujon de los tirachinas y las paredes-muelle; 0 en una pared normal.
  /// En una pared de un solo sentido empuja siempre hacia su normal.
  final double kick;
}

/// Una diana de color. Las que tienen [rail] se deslizan de lado a lado.
@immutable
class TargetSpec {
  const TargetSpec(this.category, this.at, this.angle, {this.rail = 0, this.phase = 0});

  final GachaCategory category;
  final Offset at;

  /// Hacia donde mira la cara (radianes; 0 es hacia abajo).
  final double angle;

  /// Recorrido a cada lado del carril, o 0 si esta quieta.
  final double rail;
  final double phase;
}

/// Una corona de bumpers que giran despacio alrededor de [center].
@immutable
class BumperOrbit {
  const BumperOrbit(this.center, this.radius, this.count, {this.speed = .05, this.phase = 0});

  final Offset center;
  final double radius;
  final int count;

  /// Vueltas por segundo; el signo es el sentido.
  final double speed;
  final double phase;

  Offset bumperAt(int k, double t) {
    final a = t * speed * 2 * math.pi + phase + k * 2 * math.pi / count;
    return center + Offset(math.cos(a), math.sin(a)) * radius;
  }
}

/// Lo fijo de la mesa, en unidades de mundo (400 × 820, y hacia abajo): la
/// cupula, el carril de lanzamiento, y abajo tirachinas, calles de fuera con
/// kickback, flippers y desague. Lo de en medio (agujeros, bumpers, spinners,
/// postes, muelles y dianas) cambia en cada partida: es [PinballLayout].
///
/// No cabe entera en un movil: el canal ensena una ventana que sigue a la
/// bola.
abstract final class PinballTable {
  static const double width = 400;
  static const double height = 820;
  static const double ballRadius = 9;

  /// Lo alto que se ve de la mesa como minimo (el resto, con la camara).
  static const double viewHeight = 640;

  /// El borde derecho del campo; a su derecha va el carril de lanzamiento.
  static const double fieldRight = 360;
  static const double fieldLeft = 12;
  static const double centerX = 186;

  static const Offset plungerRest = Offset(376, 790);
  static const double laneFloor = 808;
  static const Offset guardianAt = Offset(centerX, 800);

  static const double flipperLength = 58;
  static const double flipperThickness = 7;
  static const Offset leftPivot = Offset(118, 728);
  static const Offset rightPivot = Offset(254, 728);

  /// Angulos de los flippers: en reposo caidos, arriba al pulsar.
  static const double flipperRest = .5;
  static const double flipperUp = -.45;

  /// La cupula: media elipse con este centro y estos radios.
  static const Offset domeCenter = Offset(202, 176);
  static const double domeRx = 190;
  static const double domeRy = 164;

  static const double bumperRadius = 17;
  static const double fixedBumperRadius = 13;
  static const double spinnerThickness = 4;
  static const double postRadius = 5;
  static const double holeRadius = 17;
  static const double targetHalf = 13;
  static const double targetThickness = 4.5;

  /// La compuerta de salida del carril: deja subir, no bajar.
  static const double gateY = 172;

  /// Calles de fuera: a la izquierda de [outlaneLeft] y a la derecha de
  /// [outlaneRight]; el kickback salta por debajo de [kickbackY].
  static const double outlaneLeft = 37;
  static const double outlaneRight = 335;
  static const double kickbackY = 750;

  /// Hasta donde llega lo que se genera: debajo queda libre la bajada a los
  /// flippers.
  static const double playBottom = 560;

  /// Los tirachinas, de arriba abajo; el lado largo (del primero al
  /// ultimo) es el que empuja.
  static const List<Offset> leftSling = <Offset>[Offset(72, 616), Offset(72, 674), Offset(104, 694)];
  static const List<Offset> rightSling = <Offset>[Offset(300, 616), Offset(300, 674), Offset(268, 694)];

  /// Los puntos de la cupula, de la pared izquierda a la del carril.
  static final List<Offset> dome = List<Offset>.unmodifiable(<Offset>[
    for (var i = 0; i <= 28; i++)
      Offset(domeCenter.dx - math.cos(i / 28 * math.pi) * domeRx, domeCenter.dy - math.sin(i / 28 * math.pi) * domeRy),
  ]);

  /// Las paredes que no cambian nunca.
  static final List<Wall> frame = List<Wall>.unmodifiable(_buildFrame());

  static List<Wall> _buildFrame() {
    final out = <Wall>[];
    void chain(List<Offset> pts) {
      for (var i = 0; i + 1 < pts.length; i++) {
        out.add(Wall(pts[i], pts[i + 1]));
      }
    }

    // La cupula de arriba, de la pared izquierda a la derecha del carril.
    chain(<Offset>[const Offset(fieldLeft, height + 40), Offset(fieldLeft, domeCenter.dy), ...dome, const Offset(392, height + 40)]);

    // El carril: pared interior, fondo y la compuerta de salida.
    chain(<Offset>[const Offset(fieldRight, height + 40), const Offset(fieldRight, gateY)]);
    out.add(const Wall(Offset(fieldRight, laneFloor), Offset(392, laneFloor)));
    out.add(const Wall(Offset(fieldRight, gateY), Offset(392, gateY - 20), oneWay: true));

    out.addAll(guides);

    // Tirachinas: el lado que mira al centro empuja.
    for (final s in <List<Offset>>[leftSling, rightSling]) {
      out
        ..add(Wall(s[0], s[1], thickness: 3))
        ..add(Wall(s[1], s[2], thickness: 3))
        ..add(Wall(s[2], s[0], thickness: 3, kick: 420));
    }
    return out;
  }

  /// Las guias sueltas del campo (las que se pintan como rieles): las de las
  /// calles de dentro hasta los flippers y las orejas de las de fuera, para
  /// que la bola no caiga en linea recta. Las orejas solo chocan desde
  /// arriba: la bola que sube con el kickback pasa.
  static const List<Wall> guides = <Wall>[
    Wall(Offset(outlaneLeft, 592), Offset(outlaneLeft, 690), thickness: 3),
    Wall(Offset(outlaneLeft, 690), leftPivot, thickness: 3),
    Wall(Offset(outlaneRight, 592), Offset(outlaneRight, 690), thickness: 3),
    Wall(Offset(outlaneRight, 690), rightPivot, thickness: 3),
    Wall(Offset(fieldLeft, 550), Offset(27, 570), thickness: 3, oneWay: true),
    Wall(Offset(345, 570), Offset(fieldRight, 550), thickness: 3, oneWay: true),
  ];

  /// La punta de un flipper con el angulo [angle].
  static Offset flipperTip({required bool left, required double angle}) {
    final pivot = left ? leftPivot : rightPivot;
    final dir = left ? Offset(math.cos(angle), math.sin(angle)) : Offset(-math.cos(angle), math.sin(angle));
    return pivot + dir * flipperLength;
  }
}

/// Lo que cambia de una partida a otra: donde van los cuatro agujeros y
/// cuantos bumpers, spinners, postes, muelles y dianas hay y donde. Sale
/// entero de [seed], asi que una partida guardada vuelve con la misma mesa.
///
/// Entre dos piezas cualesquiera (y entre una pieza y las paredes) queda
/// siempre hueco de sobra para la bola, para que no se pueda quedar encajada.
class PinballLayout {
  PinballLayout._({
    required this.seed,
    required this.holes,
    required this.orbits,
    required this.fixedBumpers,
    required this.spinners,
    required this.posts,
    required this.springs,
    required this.targets,
  })  : walls = List<Wall>.unmodifiable(<Wall>[...PinballTable.frame, ...springs]),
        _rotating = <(int, int)>[
          for (var o = 0; o < orbits.length; o++)
            for (var k = 0; k < orbits[o].count; k++) (o, k),
        ];

  /// La mesa de la semilla [seed]: siempre la misma para la misma semilla.
  factory PinballLayout.generate(int seed) => _LayoutBuilder(seed).build();

  final int seed;
  final Map<GachaCategory, Offset> holes;
  final List<BumperOrbit> orbits;
  final List<Offset> fixedBumpers;

  /// Los spinners: paletas que giran solas y aceleran con cada golpe.
  final List<(Offset, double)> spinners;
  final List<Offset> posts;

  /// Las paredes-muelle, pegadas a las laterales: solo chocan desde el campo
  /// y devuelven la bola hacia el centro.
  final List<Wall> springs;
  final List<TargetSpec> targets;

  /// Todas las paredes: las fijas y los muelles.
  final List<Wall> walls;

  /// Los bumpers que giran, como (corona, puesto en la corona).
  final List<(int, int)> _rotating;

  /// Cuantos bumpers hay: los que giran y detras los fijos.
  int get bumperCount => _rotating.length + fixedBumpers.length;

  bool isFixedBumper(int i) => i >= _rotating.length;

  Offset bumperAt(int i, double t) {
    if (isFixedBumper(i)) return fixedBumpers[i - _rotating.length];
    final (o, k) = _rotating[i];
    return orbits[o].bumperAt(k, t);
  }

  double bumperRadiusOf(int i) => isFixedBumper(i) ? PinballTable.fixedBumperRadius : PinballTable.bumperRadius;

  /// El centro de la diana [i] en el instante [t].
  Offset targetAt(int i, double t) {
    final spec = targets[i];
    if (spec.rail == 0) return spec.at;
    return spec.at.translate(math.sin(t * 1.1 + spec.phase) * spec.rail, 0);
  }

  /// Los extremos de la diana [i]: su cara es perpendicular a [TargetSpec.angle].
  (Offset, Offset) targetEnds(int i, double t) {
    final c = targetAt(i, t);
    final a = targets[i].angle;
    final along = Offset(math.cos(a), math.sin(a)) * PinballTable.targetHalf;
    return (c - along, c + along);
  }

  /// Los extremos del spinner [i] con el angulo [angle].
  (Offset, Offset) spinnerEnds(int i, double angle) {
    final (c, half) = spinners[i];
    final along = Offset(math.cos(angle), math.sin(angle)) * half;
    return (c - along, c + along);
  }

  /// Una semilla nueva al azar.
  static int randomSeed([math.Random? random]) => (random ?? math.Random()).nextInt(1 << 30);
}

/// Una pieza vista como capsula (un circulo si `a == b`), para medir huecos.
typedef _Shape = ({Offset a, Offset b, double r});

/// Monta una [PinballLayout] al azar: pone las piezas una a una donde quepan,
/// dejando siempre [_gap] libre alrededor.
class _LayoutBuilder {
  _LayoutBuilder(this.seed) : _r = math.Random(seed);

  final int seed;
  final math.Random _r;

  /// Hueco minimo entre piezas: la bola (18) y aire de sobra.
  static const double _gap = 28;

  /// Entre dos cosas pegadas a la misma pared basta con que no se toquen.
  static const double _wallGap = 8;

  /// Hueco minimo entre dos agujeros.
  static const double _holeGap = 56;

  final List<_Shape> _placed = <_Shape>[];
  final List<_Shape> _onWall = <_Shape>[];
  final List<_Shape> _holes = <_Shape>[];

  static final List<_Shape> _frame = <_Shape>[
    for (final w in PinballTable.frame) (a: w.a, b: w.b, r: w.thickness),
  ];

  PinballLayout build() {
    // Casi siempre sale a la primera; si una mesa no cabe, se prueba otra
    // con el mismo azar, asi que la semilla sigue dando siempre la misma.
    while (true) {
      final layout = _attempt();
      if (layout != null) return layout;
    }
  }

  double _in(double a, double b) => a + _r.nextDouble() * (b - a);
  int _count(int min, int max) => min + _r.nextInt(max - min + 1);

  PinballLayout? _attempt() {
    _placed.clear();
    _onWall.clear();
    _holes.clear();

    final cats = List<GachaCategory>.of(GachaCategory.values)..shuffle(_r);
    final holes = <GachaCategory, Offset>{};
    for (final cat in cats) {
      final at = _place(200, () {
        final c = Offset(_in(40, 330), _in(64, 250));
        return <_Shape>[(a: c, b: c, r: PinballTable.holeRadius)];
      }, hole: true);
      if (at == null) return null;
      holes[cat] = at.first.a;
    }

    final orbits = <BumperOrbit>[];
    final orbitCount = _r.nextDouble() < .35 ? 2 : 1;
    for (var o = 0; o < orbitCount; o++) {
      final count = _count(2, 3);
      final radius = count == 2 ? _in(32, 42) : _in(40, 50);
      final at = _place(200, () {
        final c = Offset(_in(60, 300), _in(230, 470));
        return <_Shape>[(a: c, b: c, r: radius + PinballTable.bumperRadius)];
      });
      if (at == null) {
        if (orbits.isEmpty) return null;
        break;
      }
      orbits.add(BumperOrbit(
        at.first.a,
        radius,
        count,
        speed: (_r.nextBool() ? 1 : -1) * _in(.04, .07),
        phase: _in(0, 2 * math.pi),
      ));
    }

    final targets = _targets();
    if (targets == null) return null;

    final spinners = <(Offset, double)>[];
    for (var i = _count(1, 2); i > 0; i--) {
      final half = _in(24, 32);
      final at = _place(200, () {
        final c = Offset(_in(50, 320), _in(130, 480));
        return <_Shape>[(a: c, b: c, r: half + PinballTable.spinnerThickness)];
      });
      if (at != null) spinners.add((at.first.a, half));
    }
    if (spinners.isEmpty) return null;

    final fixed = <Offset>[];
    for (var i = _count(1, 3); i > 0; i--) {
      final at = _place(200, () {
        final c = Offset(_in(40, 330), _in(110, 500));
        return <_Shape>[(a: c, b: c, r: PinballTable.fixedBumperRadius)];
      });
      if (at != null) fixed.add(at.first.a);
    }
    if (fixed.isEmpty) return null;

    final springs = <Wall>[];
    for (var i = _count(1, 3); i > 0; i--) {
      final left = _r.nextBool();
      final length = _in(90, 150);
      final at = _place(100, () {
        final top = _in(200, PinballTable.playBottom - 20 - length);
        final x = left ? PinballTable.fieldLeft + 2 : PinballTable.fieldRight - 2;
        return <_Shape>[(a: Offset(x, top), b: Offset(x, top + length), r: 2)];
      }, onWall: true);
      if (at == null) continue;
      final s = at.first;
      // La normal de un muelle (izquierda de a → b) mira al campo.
      springs.add(left ? Wall(s.a, s.b, oneWay: true, kick: 300) : Wall(s.b, s.a, oneWay: true, kick: 300));
    }
    if (springs.isEmpty) return null;

    // Los postes, en grupitos: muchos salen al lado de otro poste.
    final posts = <Offset>[];
    for (var i = _count(5, 12); i > 0; i--) {
      final at = _place(200, () {
        Offset c;
        if (posts.isNotEmpty && _r.nextDouble() < .65) {
          final near = posts[_r.nextInt(posts.length)];
          final a = _in(0, 2 * math.pi);
          c = near + Offset(math.cos(a), math.sin(a)) * _in(38, 48);
        } else {
          c = Offset(_in(40, 330), _in(100, 520));
        }
        return <_Shape>[(a: c, b: c, r: PinballTable.postRadius)];
      }, gap: 28);
      if (at != null) posts.add(at.first.a);
    }
    if (posts.length < 4) return null;

    return PinballLayout._(
      seed: seed,
      holes: Map<GachaCategory, Offset>.unmodifiable(holes),
      orbits: List<BumperOrbit>.unmodifiable(orbits),
      fixedBumpers: List<Offset>.unmodifiable(fixed),
      spinners: List<(Offset, double)>.unmodifiable(spinners),
      posts: List<Offset>.unmodifiable(posts),
      springs: List<Wall>.unmodifiable(springs),
      targets: List<TargetSpec>.unmodifiable(targets),
    );
  }

  /// Las doce dianas, tres de cada color en orden al azar: unas pegadas a
  /// las paredes, otras en carriles y el resto sueltas y un poco giradas.
  List<TargetSpec>? _targets() {
    final cats = <GachaCategory>[
      for (final c in GachaCategory.values)
        for (var i = 0; i < targetsPerCategory; i++) c,
    ]..shuffle(_r);
    final out = <TargetSpec>[];
    var onWall = 0, onRail = 0;
    for (final cat in cats) {
      final roll = _r.nextDouble();
      TargetSpec? spec;
      if (roll < .25 && onWall < 4) {
        spec = _wallTarget(cat);
        if (spec != null) onWall++;
      } else if (roll < .5 && onRail < 4) {
        spec = _railTarget(cat);
        if (spec != null) onRail++;
      }
      spec ??= _freeTarget(cat);
      if (spec == null) return null;
      out.add(spec);
    }
    return out;
  }

  static const double _t = PinballTable.targetThickness;
  static const double _h = PinballTable.targetHalf;

  TargetSpec? _wallTarget(GachaCategory cat) {
    TargetSpec? spec;
    final at = _place(100, () {
      final left = _r.nextBool();
      final c = Offset(left ? PinballTable.fieldLeft + 12 : PinballTable.fieldRight - 12, _in(210, 520));
      spec = TargetSpec(cat, c, left ? -math.pi / 2 : math.pi / 2);
      return <_Shape>[(a: c.translate(0, -_h), b: c.translate(0, _h), r: _t)];
    }, onWall: true);
    return at == null ? null : spec;
  }

  TargetSpec? _railTarget(GachaCategory cat) {
    TargetSpec? spec;
    final at = _place(100, () {
      final rail = _in(16, 36);
      final c = Offset(_in(50 + rail, 320 - rail), _in(200, 540));
      spec = TargetSpec(cat, c, 0, rail: rail, phase: _in(0, 2 * math.pi));
      return <_Shape>[(a: c.translate(-rail - _h, 0), b: c.translate(rail + _h, 0), r: _t)];
    });
    return at == null ? null : spec;
  }

  TargetSpec? _freeTarget(GachaCategory cat) {
    TargetSpec? spec;
    final at = _place(300, () {
      final c = Offset(_in(40, 330), _in(160, 545));
      final angle = _in(-.7, .7);
      spec = TargetSpec(cat, c, angle);
      final along = Offset(math.cos(angle), math.sin(angle)) * _h;
      return <_Shape>[(a: c - along, b: c + along, r: _t)];
    });
    return at == null ? null : spec;
  }

  /// Prueba [tries] veces una pieza de [make] y la deja puesta en la primera
  /// que quepa; `null` si no cabe en ninguna.
  List<_Shape>? _place(
    int tries,
    List<_Shape> Function() make, {
    bool onWall = false,
    bool hole = false,
    double gap = _gap,
  }) {
    for (var i = 0; i < tries; i++) {
      final shapes = make();
      if (!shapes.every((s) => _fits(s, onWall: onWall, hole: hole, gap: gap))) continue;
      (hole ? _holes : onWall ? _onWall : _placed).addAll(shapes);
      return shapes;
    }
    return null;
  }

  bool _fits(_Shape s, {required bool onWall, required bool hole, required double gap}) {
    for (final p in <Offset>[s.a, s.b]) {
      if (!_inside(p)) return false;
      if (p.dy + s.r > PinballTable.playBottom) return false;
    }
    if (!onWall) {
      for (final f in _frame) {
        if (_gapBetween(s, f) < gap) return false;
      }
    }
    for (final p in _placed) {
      if (_gapBetween(s, p) < gap) return false;
    }
    for (final p in _onWall) {
      if (_gapBetween(s, p) < (onWall ? _wallGap : gap)) return false;
    }
    for (final p in _holes) {
      if (_gapBetween(s, p) < (hole ? _holeGap : gap)) return false;
    }
    return true;
  }

  static bool _inside(Offset p) {
    if (p.dx < PinballTable.fieldLeft || p.dx > PinballTable.fieldRight) return false;
    const c = PinballTable.domeCenter;
    if (p.dy >= c.dy) return true;
    final x = (p.dx - c.dx) / PinballTable.domeRx;
    final y = (p.dy - c.dy) / PinballTable.domeRy;
    return x * x + y * y < 1;
  }

  static double _gapBetween(_Shape s, _Shape t) => _segmentDistance(s.a, s.b, t.a, t.b) - s.r - t.r;

  static double _segmentDistance(Offset a, Offset b, Offset c, Offset d) {
    if (_crosses(a, b, c, d)) return 0;
    return math.min(
      math.min(_pointDistance(a, c, d), _pointDistance(b, c, d)),
      math.min(_pointDistance(c, a, b), _pointDistance(d, a, b)),
    );
  }

  static double _pointDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    final u = len2 == 0 ? 0.0 : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * u)).distance;
  }

  static bool _crosses(Offset a, Offset b, Offset c, Offset d) {
    double cross(Offset o, Offset p, Offset q) => (p.dx - o.dx) * (q.dy - o.dy) - (p.dy - o.dy) * (q.dx - o.dx);
    final d1 = cross(c, d, a), d2 = cross(c, d, b), d3 = cross(a, b, c), d4 = cross(a, b, d);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }
}


// --- La partida ----------------------------------------------------------------

enum PinballPhase {
  /// La bola espera en el lanzador.
  ready,

  /// La bola esta en juego.
  rolling,

  /// La bola ha entrado en un agujero: se ensena el premio.
  captured,

  /// La bola se ha perdido por el desague.
  lost,

  /// No quedan bolas.
  over,
}

enum PinballEventKind {
  launch,
  flipper,
  bumper,
  sling,
  spring,
  post,
  spinner,
  target,
  holeOpen,
  captured,
  kickbackLit,
  kickback,

  /// El Tama coge la bola en el desague: con el salvabolas o porque la
  /// bola va guardada.
  saved,
  guarded,

  /// El Tama devuelve la bola guardada al campo.
  thrown,

  /// La mesa da un meneo a una bola que se ha quedado parada.
  nudge,
  lost,
  wall,
}

@immutable
class PinballEvent {
  const PinballEvent(this.kind, this.at, {this.category, this.index});

  final PinballEventKind kind;
  final Offset at;
  final GachaCategory? category;

  /// Que bumper o que diana ha sido.
  final int? index;
}

/// Lo que dio cada bola: [category] es nula si se perdio. [prize] es la
/// clave del premio que ha tocado (nula si se perdio o si la categoria aun
/// no tiene premios) y [saved], si la jugada ya esta guardada en el
/// servidor.
@immutable
class PinballOutcome {
  const PinballOutcome(this.ball, this.category, {this.prize, this.saved = false});

  final GachaBall ball;
  final GachaCategory? category;
  final String? prize;
  final bool saved;

  bool get won => category != null;

  PinballOutcome withPrize(String? prize) => PinballOutcome(ball, category, prize: prize, saved: saved);

  PinballOutcome get asSaved => PinballOutcome(ball, category, prize: prize, saved: true);

  Map<String, Object?> toJson() => <String, Object?>{
        ..._ballJson(ball),
        if (category != null) 'won': category!.name,
        'prize': ?prize,
        'saved': saved,
      };

  static PinballOutcome? fromJson(Object? raw) {
    final ball = _ballFromJson(raw);
    if (ball == null || raw is! Map) return null;
    return PinballOutcome(
      ball,
      GachaCategory.byName(raw['won']),
      prize: raw['prize'] is String ? raw['prize'] as String : null,
      // Las partidas de antes de la coleccion no tenian nada que guardar.
      saved: raw['saved'] != false,
    );
  }
}

Map<String, Object?> _ballJson(GachaBall b) => <String, Object?>{
      'rarity': b.rarity.name,
      if (b.category != null) 'category': b.category!.name,
    };

GachaBall? _ballFromJson(Object? raw) {
  if (raw is! Map) return null;
  final rarity = Rarity.byName(raw['rarity']);
  if (rarity == null) return null;
  return GachaBall(rarity, category: GachaCategory.byName(raw['category']));
}

/// Una partida de pinball: la cola de bolas, la mesa y la fisica de la bola
/// en juego. No sabe nada de widgets ni de red: el canal le pasa el tiempo y
/// los mandos y pinta lo que hay.
class PinballGame {
  /// Sin [seed], la mesa sale nueva al azar.
  PinballGame({required List<GachaBall> queue, math.Random? random, int? seed})
      : this._(queue, random ?? math.Random(), seed);

  PinballGame._(List<GachaBall> queue, math.Random random, int? seed)
      : queue = List<GachaBall>.unmodifiable(queue),
        _random = random,
        layout = PinballLayout.generate(seed ?? PinballLayout.randomSeed(random)) {
    assert(queue.isNotEmpty && queue.length <= pinballQueueMax);
    spinnerAngles = List<double>.generate(layout.spinners.length, (i) => i * 1.3);
    _spinnerOmegas = List<double>.generate(layout.spinners.length, (i) => i.isEven ? _spinnerIdle : -_spinnerIdle);
    _spinnerHitAt = List<double>.filled(layout.spinners.length, -9);
  }

  /// La mesa de esta partida.
  final PinballLayout layout;

  /// Todas las bolas de la partida, en el orden en que salen.
  final List<GachaBall> queue;
  final math.Random _random;

  final List<PinballOutcome> outcomes = <PinballOutcome>[];

  PinballPhase phase = PinballPhase.ready;
  int score = 0;

  /// El reloj de la mesa, que mueve bumpers y dianas.
  double time = 0;

  Offset ball = PinballTable.plungerRest;
  Offset velocity = Offset.zero;

  /// Cuanto ha girado la bola (radianes), para pintarla rodando.
  double spin = 0;
  double _spinRate = 0;

  /// Cuanto se ha tirado del lanzador (0 a 1).
  double pull = 0;

  bool leftHeld = false;
  bool rightHeld = false;
  double leftAngle = PinballTable.flipperRest;
  double rightAngle = PinballTable.flipperRest;
  double _leftOmega = 0;
  double _rightOmega = 0;

  /// El angulo de cada spinner de [layout].
  late final List<double> spinnerAngles;
  late final List<double> _spinnerOmegas;
  static const double _spinnerIdle = 2.4;

  /// Dianas tumbadas, por indice de [PinballLayout.targets].
  final Set<int> knocked = <int>{};

  /// Agujeros abiertos.
  final Set<GachaCategory> open = <GachaCategory>{};

  bool kickbackLeft = false;
  bool kickbackRight = false;
  int bumperHits = 0;

  /// Momento (en [time]) en que la bola salio del carril, o `null` si aun
  /// esta dentro. El salvabolas cuenta desde ahi.
  double? launchedAt;

  /// Si la bola en juego ya ha salido alguna vez del lanzador. Hasta
  /// entonces la partida se puede cancelar y devolver las bolas que quedan.
  bool launchedThis = false;

  /// El agujero donde acaba de entrar la bola.
  GachaCategory? capturedIn;

  /// Mientras el Tama tiene la bola cogida en el desague: hasta cuando, y si
  /// despues la devuelve al lanzador (salvabolas) o al campo (guardada).
  double? rescueUntil;
  bool _rescueToPlunger = false;

  /// Cuanto dura el Tama con la bola en brazos antes de soltarla.
  static const double rescueHold = .7;

  int get ballIndex => outcomes.length;
  GachaBall? get current => ballIndex < queue.length ? queue[ballIndex] : null;
  bool get guarded => current != null && isGuarded(current!);
  bool get isOver => phase == PinballPhase.over;

  /// Si queda alguna bola jugada sin guardar en el servidor.
  bool get hasUnsaved => outcomes.any((o) => !o.saved);

  /// Las bolas que aun no han salido, las que se devuelven al cancelar.
  List<GachaBall> get unplayed => queue.sublist(ballIndex);

  /// Se puede cancelar mientras la bola de turno no haya salido.
  bool get canCancel => phase == PinballPhase.ready && !launchedThis;

  /// Segundos de salvabolas que quedan; 0 si ya no hay o la bola esta
  /// guardada (no le hace falta).
  double get saverLeft {
    final at = launchedAt;
    if (guarded || phase != PinballPhase.rolling) return 0;
    if (at == null) return ballSaverSeconds;
    return math.max(0, ballSaverSeconds - (time - at));
  }

  int knockedOf(GachaCategory category) {
    var n = 0;
    for (final i in knocked) {
      if (layout.targets[i].category == category) n++;
    }
    return n;
  }

  // --- Mandos -----------------------------------------------------------------

  void setFlipper({required bool left, required bool held}) {
    if (left) {
      leftHeld = held;
    } else {
      rightHeld = held;
    }
  }

  /// Suelta el lanzador con la fuerza [pull] (0 a 1). La fuerza real baila
  /// un poco, para que dos tiros iguales no caigan en el mismo sitio.
  PinballEvent? launch([double? strength]) {
    if (phase != PinballPhase.ready) return null;
    final p = (strength ?? pull).clamp(.15, 1.0) * (1 + (_random.nextDouble() - .5) * .06);
    pull = 0;
    phase = PinballPhase.rolling;
    launchedThis = true;
    ball = PinballTable.plungerRest;
    velocity = Offset(0, -(1120 + 420 * p));
    _anchor = ball;
    _anchorAt = time;
    return PinballEvent(PinballEventKind.launch, ball);
  }

  /// Pasa a la siguiente bola despues de ensenar el premio o el consuelo.
  void nextBall() {
    if (phase != PinballPhase.captured && phase != PinballPhase.lost) return;
    capturedIn = null;
    launchedThis = false;
    if (current == null) {
      phase = PinballPhase.over;
      return;
    }
    _toPlunger();
  }

  void _toPlunger() {
    phase = PinballPhase.ready;
    ball = PinballTable.plungerRest;
    velocity = Offset.zero;
    pull = 0;
    launchedAt = null;
    rescueUntil = null;
    _spinRate = 0;
  }

  void _resetBoard() {
    knocked.clear();
    open.clear();
  }

  // --- Reloj ------------------------------------------------------------------

  static const double _step = 1 / 240;
  static const double _gravity = 700;
  static const double _maxSpeed = 1800;
  double _acc = 0;

  /// Para ver si la bola se ha quedado quieta: donde estaba y desde cuando.
  Offset _anchor = PinballTable.plungerRest;
  double _anchorAt = 0;

  /// Segundos parada (en menos de [_stallRadius]) antes del meneo.
  static const double _stallTime = 1.4;
  static const double _stallRadius = 14;

  /// Avanza [dt] segundos y devuelve lo que ha pasado.
  List<PinballEvent> tick(double dt) {
    final events = <PinballEvent>[];
    _acc += math.min(dt, .05);
    while (_acc >= _step) {
      _acc -= _step;
      _substep(events);
    }
    return events;
  }

  void _substep(List<PinballEvent> events) {
    const h = _step;
    time += h;
    _moveFlippers(h, events);
    _moveSpinner(h);
    if (phase != PinballPhase.rolling) return;
    if (_rescue(events)) return;

    velocity = velocity.translate(0, _gravity * h);
    final speed = velocity.distance;
    if (speed > _maxSpeed) velocity = velocity * (_maxSpeed / speed);
    velocity = velocity * math.exp(-.04 * h);
    ball += velocity * h;
    _spinRate *= math.exp(-.4 * h);

    _collideWalls(events);
    _collideFlippers();
    _collideSpinners(events);
    _collidePosts(events);
    _collideBumpers(events);
    _collideTargets(events);
    spin += _spinRate * h;
    if (!_checkLane()) return;
    _checkHoles(events);
    _checkKickbacks(events);
    _checkDrain(events);
    _checkStall(events);
  }

  /// La bola en brazos del Tama: no se mueve hasta que la suelta.
  bool _rescue(List<PinballEvent> events) {
    final until = rescueUntil;
    if (until == null) return false;
    if (time < until) return true;
    rescueUntil = null;
    if (_rescueToPlunger) {
      _toPlunger();
    } else {
      velocity = Offset((_random.nextDouble() - .5) * 360, -1250 - _random.nextDouble() * 150);
      _spinRate = (_random.nextDouble() - .5) * 30;
      events.add(PinballEvent(PinballEventKind.thrown, ball));
    }
    return true;
  }

  void _moveFlippers(double h, List<PinballEvent> events) {
    const up = 26.0;
    const down = 13.0;
    double move(double angle, bool held, void Function(double) setOmega, bool left) {
      final target = held ? PinballTable.flipperUp : PinballTable.flipperRest;
      if (angle == target) {
        setOmega(0);
        return angle;
      }
      final rate = held ? -up : down;
      var next = angle + rate * h;
      if ((held && next <= target) || (!held && next >= target)) next = target;
      if (held && angle == PinballTable.flipperRest) {
        events.add(PinballEvent(PinballEventKind.flipper, left ? PinballTable.leftPivot : PinballTable.rightPivot));
      }
      setOmega((next - angle) / h);
      return next;
    }

    leftAngle = move(leftAngle, leftHeld, (w) => _leftOmega = w, true);
    rightAngle = move(rightAngle, rightHeld, (w) => _rightOmega = w, false);
  }

  void _moveSpinner(double h) {
    // Vuelve poco a poco a su giro de reposo, en el sentido que lleve.
    for (var i = 0; i < spinnerAngles.length; i++) {
      final omega = _spinnerOmegas[i];
      final idle = omega >= 0 ? _spinnerIdle : -_spinnerIdle;
      _spinnerOmegas[i] = omega + (idle - omega) * (1 - math.exp(-.9 * h));
      spinnerAngles[i] = (spinnerAngles[i] + _spinnerOmegas[i] * h) % (2 * math.pi);
    }
  }

  /// Apunta el giro de la bola al rozar una superficie de normal [n] con la
  /// velocidad relativa tangencial [tangent]: rueda sin deslizar.
  void _roll(Offset n, Offset tangent) {
    final rate = (n.dx * tangent.dy - n.dy * tangent.dx) / PinballTable.ballRadius;
    _spinRate += (rate - _spinRate) * .6;
  }

  /// Choca la bola contra la capsula `a–b` de grosor [t]. [surface] da la
  /// velocidad de la superficie en un punto (flippers, spinner y dianas que
  /// se mueven). Devuelve la velocidad normal de entrada (negativa) o `null`
  /// si no ha tocado.
  double? _capsule(
    Offset a,
    Offset b,
    double t, {
    bool oneWay = false,
    double restitution = .42,
    Offset Function(Offset p)? surface,
  }) {
    final ab = b - a;
    final len2 = ab.distanceSquared;
    final u = len2 == 0 ? 0.0 : (((ball - a).dx * ab.dx + (ball - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
    final p = a + ab * u;
    final d = ball - p;
    final dist = d.distance;
    final reach = PinballTable.ballRadius + t;
    if (dist >= reach || dist == 0) return null;
    final n = d / dist;
    if (oneWay) {
      // La normal de una pared de un solo sentido es la izquierda de a → b.
      final left = Offset(ab.dy, -ab.dx);
      if (n.dx * left.dx + n.dy * left.dy <= 0) return null;
    }
    ball = p + n * reach;
    final vs = surface?.call(p) ?? Offset.zero;
    final rel = velocity - vs;
    final vn = rel.dx * n.dx + rel.dy * n.dy;
    if (vn >= 0) return 0;
    final tangent = rel - n * vn;
    velocity = vs + tangent * .985 - n * (vn * restitution);
    _roll(n, tangent);
    return vn;
  }

  /// Choca la bola contra un circulo quieto. Devuelve la normal de salida y
  /// la velocidad normal de entrada, o `null` si no ha tocado.
  (Offset, double)? _circle(Offset c, double radius, {double restitution = .5}) {
    final d = ball - c;
    final dist = d.distance;
    final reach = PinballTable.ballRadius + radius;
    if (dist >= reach || dist == 0) return null;
    final n = d / dist;
    ball = c + n * reach;
    final vn = velocity.dx * n.dx + velocity.dy * n.dy;
    if (vn >= 0) return (n, 0);
    final tangent = velocity - n * vn;
    velocity = tangent * .985 - n * (vn * restitution);
    _roll(n, tangent);
    return (n, vn);
  }

  /// Gira [v] un angulo al azar de hasta [spread] radianes a cada lado.
  Offset _jitter(Offset v, double spread) {
    final a = (_random.nextDouble() - .5) * 2 * spread;
    final c = math.cos(a), s = math.sin(a);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  void _collideWalls(List<PinballEvent> events) {
    final walls = layout.walls;
    for (var i = 0; i < walls.length; i++) {
      final w = walls[i];
      final vn = _capsule(w.a, w.b, w.thickness, oneWay: w.oneWay);
      if (vn == null) continue;
      if (w.kick > 0 && vn < -60) {
        final ab = w.b - w.a;
        Offset n;
        if (w.oneWay) {
          n = Offset(ab.dy, -ab.dx) / ab.distance;
        } else {
          n = Offset(-ab.dy, ab.dx) / ab.distance;
          // El empujon va hacia donde este la bola.
          final side = (ball - w.a).dx * n.dx + (ball - w.a).dy * n.dy;
          if (side < 0) n = -n;
        }
        velocity += _jitter(n * w.kick, .12);
        score += w.oneWay ? 10 : 20;
        // Los muelles van detras de las paredes fijas.
        events.add(w.oneWay
            ? PinballEvent(PinballEventKind.spring, ball, index: i - PinballTable.frame.length)
            : PinballEvent(PinballEventKind.sling, ball));
      } else if (vn < -260) {
        events.add(PinballEvent(PinballEventKind.wall, ball));
      }
    }
  }

  void _collideFlippers() {
    for (final left in <bool>[true, false]) {
      final pivot = left ? PinballTable.leftPivot : PinballTable.rightPivot;
      final angle = left ? leftAngle : rightAngle;
      final tip = PinballTable.flipperTip(left: left, angle: angle);
      // Velocidad angular en pantalla: el derecho gira al reves.
      final omega = left ? _leftOmega : -_rightOmega;
      _capsule(
        pivot,
        tip,
        PinballTable.flipperThickness,
        restitution: .3,
        surface: (p) => Offset(-(p.dy - pivot.dy), p.dx - pivot.dx) * omega,
      );
    }
  }

  late final List<double> _spinnerHitAt;

  void _collideSpinners(List<PinballEvent> events) {
    for (var i = 0; i < spinnerAngles.length; i++) {
      _collideSpinner(i, events);
    }
  }

  void _collideSpinner(int i, List<PinballEvent> events) {
    final (a, b) = layout.spinnerEnds(i, spinnerAngles[i]);
    final before = velocity;
    final c = layout.spinners[i].$1;
    final omega = _spinnerOmegas[i];
    final vn = _capsule(
      a,
      b,
      PinballTable.spinnerThickness,
      restitution: .6,
      surface: (p) => Offset(-(p.dy - c.dy), p.dx - c.dx) * omega,
    );
    if (vn == null || vn > -40) return;
    // Lo que la bola pierde se lo lleva la paleta: gira mas, hacia donde la
    // empujo.
    final dv = before - velocity;
    final r = ball - c;
    _spinnerOmegas[i] = (omega + (r.dx * dv.dy - r.dy * dv.dx) * .0006).clamp(-22.0, 22.0);
    score += 50;
    if (time - _spinnerHitAt[i] > .08) {
      _spinnerHitAt[i] = time;
      events.add(PinballEvent(PinballEventKind.spinner, ball, index: i));
    }
  }

  void _collidePosts(List<PinballEvent> events) {
    for (var i = 0; i < layout.posts.length; i++) {
      final hit = _circle(layout.posts[i], PinballTable.postRadius, restitution: .72);
      if (hit == null) continue;
      final (_, vn) = hit;
      if (vn < -40) velocity = _jitter(velocity, .08);
      if (vn < -120) {
        score += 5;
        events.add(PinballEvent(PinballEventKind.post, layout.posts[i], index: i));
      }
    }
  }

  void _collideBumpers(List<PinballEvent> events) {
    for (var i = 0; i < layout.bumperCount; i++) {
      final c = layout.bumperAt(i, time);
      final d = ball - c;
      final dist = d.distance;
      final reach = PinballTable.ballRadius + layout.bumperRadiusOf(i);
      if (dist >= reach || dist == 0) continue;
      final n = d / dist;
      ball = c + n * reach;
      final vn = velocity.dx * n.dx + velocity.dy * n.dy;
      if (vn < 0) velocity -= n * (vn * 1.5);
      velocity += _jitter(n * (layout.isFixedBumper(i) ? 300 : 360), .15);
      _roll(n, velocity - n * (velocity.dx * n.dx + velocity.dy * n.dy));
      score += 100;
      bumperHits++;
      events.add(PinballEvent(PinballEventKind.bumper, c, index: i));
      if (bumperHits % bumperHitsPerKickback == 0) {
        if (!kickbackLeft) {
          kickbackLeft = true;
          events.add(const PinballEvent(PinballEventKind.kickbackLit, Offset(28, PinballTable.kickbackY)));
        } else if (!kickbackRight) {
          kickbackRight = true;
          events.add(const PinballEvent(PinballEventKind.kickbackLit, Offset(344, PinballTable.kickbackY)));
        }
      }
    }
  }

  void _collideTargets(List<PinballEvent> events) {
    for (var i = 0; i < layout.targets.length; i++) {
      if (knocked.contains(i)) continue;
      final spec = layout.targets[i];
      final (a, b) = layout.targetEnds(i, time);
      final railSpeed = spec.rail == 0 ? 0.0 : math.cos(time * 1.1 + spec.phase) * spec.rail * 1.1;
      final vn = _capsule(a, b, PinballTable.targetThickness, restitution: .5, surface: (_) => Offset(railSpeed, 0));
      if (vn == null || vn > -50) continue;
      knocked.add(i);
      score += 500;
      events.add(PinballEvent(PinballEventKind.target, layout.targetAt(i, time), category: spec.category, index: i));
      if (knockedOf(spec.category) >= targetsPerCategory && open.add(spec.category)) {
        score += 1000;
        events.add(PinballEvent(PinballEventKind.holeOpen, layout.holes[spec.category]!, category: spec.category));
      }
    }
  }

  /// Si la bola vuelve al fondo del carril sin fuerza, se queda en el
  /// lanzador otra vez. Al salir del carril empieza el salvabolas. Devuelve
  /// si la bola sigue en juego.
  bool _checkLane() {
    final inLane = ball.dx > PinballTable.fieldRight;
    if (launchedAt == null && !inLane) launchedAt = time;
    if (inLane && ball.dy > PinballTable.plungerRest.dy - 10 && velocity.distance < 30) {
      _toPlunger();
      return false;
    }
    return true;
  }

  void _checkHoles(List<PinballEvent> events) {
    for (final entry in layout.holes.entries) {
      if (!open.contains(entry.key)) continue;
      final d = entry.value - ball;
      final dist = d.distance;
      if (dist > PinballTable.holeRadius * 2) continue;
      // Un agujero abierto tira un poco de la bola, como el hundido de un
      // platillo; si pasa despacio y cerca, cae.
      velocity += d * (18 * _step * 60 / math.max(dist, 4));
      if (dist < PinballTable.holeRadius * .75 && velocity.distance < 950) {
        _capture(entry.key, events);
        return;
      }
    }
  }

  void _capture(GachaCategory hole, List<PinballEvent> events) {
    final b = current!;
    // La bola dirigida da su categoria, caiga en el agujero que caiga.
    final prize = b.category ?? hole;
    outcomes.add(PinballOutcome(b, prize));
    capturedIn = hole;
    score += 5000;
    ball = layout.holes[hole]!;
    velocity = Offset.zero;
    phase = PinballPhase.captured;
    _resetBoard();
    events.add(PinballEvent(PinballEventKind.captured, ball, category: prize));
  }

  void _checkKickbacks(List<PinballEvent> events) {
    if (ball.dy < PinballTable.kickbackY || velocity.dy < 0) return;
    final leftSide = ball.dx < PinballTable.outlaneLeft;
    final rightSide = ball.dx > PinballTable.outlaneRight && ball.dx < PinballTable.fieldRight;
    if (leftSide && kickbackLeft) {
      kickbackLeft = false;
    } else if (rightSide && kickbackRight) {
      kickbackRight = false;
    } else {
      return;
    }
    // Al centro de la calle, para que suba sin rozar las paredes.
    ball = Offset(leftSide ? (PinballTable.fieldLeft + PinballTable.outlaneLeft) / 2 : (PinballTable.outlaneRight + PinballTable.fieldRight) / 2, ball.dy);
    velocity = Offset(0, -1200);
    events.add(PinballEvent(PinballEventKind.kickback, ball));
  }

  void _checkDrain(List<PinballEvent> events) {
    if (ball.dy < PinballTable.height + PinballTable.ballRadius * 2) return;
    final saved = !guarded && saverLeft > 0;
    if (guarded || saved) {
      // El Tama coge la bola en el desague y, al rato, la suelta: al campo
      // si va guardada, al lanzador si era el salvabolas.
      ball = PinballTable.guardianAt;
      velocity = Offset.zero;
      rescueUntil = time + rescueHold;
      _rescueToPlunger = saved;
      events.add(PinballEvent(saved ? PinballEventKind.saved : PinballEventKind.guarded, ball));
      return;
    }
    outcomes.add(PinballOutcome(current!, null));
    phase = PinballPhase.lost;
    velocity = Offset.zero;
    // Perder la bola pierde tambien lo tumbado (los kickbacks encendidos se
    // quedan: se ganaron con los bumpers).
    _resetBoard();
    events.add(PinballEvent(PinballEventKind.lost, ball));
  }

  /// Una bola que se queda quieta (encima de una diana, en equilibrio en un
  /// poste…) recibe un meneo de la mesa. No cuenta la que se sujeta a
  /// proposito con un flipper levantado.
  void _checkStall(List<PinballEvent> events) {
    if (phase != PinballPhase.rolling) return;
    if ((ball - _anchor).distance > _stallRadius) {
      _anchor = ball;
      _anchorAt = time;
      return;
    }
    final cradled = ball.dy > PinballTable.leftPivot.dy - 40 && (leftHeld || rightHeld);
    final inLane = ball.dx > PinballTable.fieldRight;
    if (cradled || inLane) {
      _anchorAt = time;
      return;
    }
    if (time - _anchorAt < _stallTime) return;
    velocity = Offset((_random.nextDouble() - .5) * 320, -380 - _random.nextDouble() * 220);
    _anchorAt = time;
    events.add(PinballEvent(PinballEventKind.nudge, ball));
  }

  // --- Pausa --------------------------------------------------------------------

  /// La partida para guardarla en el dispositivo. La bola en juego vuelve al
  /// lanzador al retomarla; lo tumbado y los kickbacks se conservan, y si la
  /// bola ya habia salido, ya no se puede cancelar.
  Map<String, Object?> toJson() => <String, Object?>{
        'seed': layout.seed,
        'queue': <Object?>[for (final b in queue) _ballJson(b)],
        'outcomes': <Object?>[for (final o in outcomes) o.toJson()],
        'score': score,
        'knocked': knocked.toList()..sort(),
        'open': <String>[for (final c in open) c.name],
        'kickbacks': <bool>[kickbackLeft, kickbackRight],
        'bumperHits': bumperHits,
        if (launchedThis && phase != PinballPhase.captured && phase != PinballPhase.lost) 'launched': true,
      };

  static PinballGame? fromJson(Object? raw, {math.Random? random}) {
    if (raw is! Map) return null;
    final queueRaw = raw['queue'];
    if (queueRaw is! List) return null;
    final queue = <GachaBall>[
      for (final b in queueRaw) ?_ballFromJson(b),
    ];
    if (queue.isEmpty || queue.length != queueRaw.length || queue.length > pinballQueueMax) return null;
    // Sin semilla (una partida de antes de las mesas al azar) sale una mesa
    // nueva y lo tumbado ya no sirve.
    final seed = raw['seed'] is int ? raw['seed']! as int : null;
    final game = PinballGame(queue: queue, random: random, seed: seed);
    final outs = raw['outcomes'];
    if (outs is List) {
      for (final o in outs.take(queue.length)) {
        final out = PinballOutcome.fromJson(o);
        if (out != null) game.outcomes.add(out);
      }
    }
    game.score = raw['score'] is num ? (raw['score']! as num).toInt() : 0;
    final knocked = raw['knocked'];
    if (knocked is List && seed != null) {
      game.knocked.addAll(knocked.whereType<num>().map((n) => n.toInt()).where((i) => i >= 0 && i < game.layout.targets.length));
    }
    final open = raw['open'];
    if (open is List) {
      game.open.addAll(open.map(GachaCategory.byName).whereType<GachaCategory>());
    }
    final kick = raw['kickbacks'];
    if (kick is List && kick.length == 2) {
      game.kickbackLeft = kick[0] == true;
      game.kickbackRight = kick[1] == true;
    }
    game.bumperHits = raw['bumperHits'] is num ? (raw['bumperHits']! as num).toInt() : 0;
    game.launchedThis = raw['launched'] == true;
    if (game.current == null) game.phase = PinballPhase.over;
    return game;
  }
}
