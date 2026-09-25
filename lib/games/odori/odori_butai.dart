// Ibasho — Odori: Butai (舞台), el escenario. Las notas vuelan hacia dianas
// repartidas por un escenario azul noche, y cada una se toca con su tecla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../theme/type.dart';
import 'odori_board.dart';
import 'odori_chart.dart';
import 'odori_engine.dart';
import 'odori_store.dart';

/// Butai se juega siempre con cuatro teclas.
const int butaiKeys = 4;

/// Color de cada tecla: rosa, azul, verde y ambar. En Butai no hay carriles
/// que digan que tecla es, asi que cada una lleva su color y su flecha.
const List<Color> butaiColors = [
  Color(0xFFFF6FA8),
  Color(0xFF4FA8FF),
  Color(0xFF4CD08A),
  odoriAmber,
];

/// Flecha de cada tecla, en radianes: ← ↓ ↑ →.
const List<double> butaiAngles = [math.pi, math.pi / 2, -math.pi / 2, 0];

/// Azul noche del escenario: el del tema, teñido con su acento. Nunca negro.
(Color, Color) butaiNight(Color accent) => (
      Color.lerp(const Color(0xFF22346E), accent, .16)!,
      Color.lerp(const Color(0xFF111D45), accent, .08)!,
    );

/// Donde cae una nota y por donde llega, en coordenadas del escenario (de 0
/// a 1 en cada eje).
@immutable
class ButaiSpot {
  const ButaiSpot({required this.at, required this.from, required this.bend});

  /// La diana.
  final Offset at;

  /// De donde sale la nota que vuela.
  final Offset from;

  /// Punto de control de la curva que hace al volar.
  final Offset bend;

  /// Donde va la nota con [p] de 0 (sale) a 1 (llega).
  Offset fly(double p) {
    final q = 1 - p;
    return from * (q * q) + bend * (2 * q * p) + at * (p * p);
  }
}

/// Margen del escenario que las dianas no pisan. El escenario ya deja fuera
/// lo que va encima (marcador, letra, botones), asi que el margen es poco.
const double _left = .06, _right = .94, _top = .08, _bottom = .92;

/// Distancia minima entre dianas que se ven a la vez.
const double _apart = .2;

/// Reparte las dianas: un camino que da vueltas por el escenario, con pasos
/// mas largos cuanto mas separadas estan las notas y rebotando en los bordes.
/// Los acordes se ponen en fila, de traves al camino. Sale siempre igual.
List<ButaiSpot> butaiLayout(OdoriChart chart, {required String seed}) {
  final rnd = math.Random(odoriSeed('butai/$seed/${chart.difficulty.index}'));
  final notes = chart.notes;
  final spots = List<ButaiSpot?>.filled(notes.length, null);
  var pos = const Offset(.28, .5);
  var heading = -.4;
  var side = 1.0;
  var i = 0;
  while (i < notes.length) {
    // Las notas de un mismo golpe.
    var j = i + 1;
    while (j < notes.length && (notes[j].time - notes[i].time).abs() < .01) {
      j++;
    }
    final chord = j - i;
    final gap = i == 0 ? 1.0 : notes[i].time - notes[i - 1].time;
    final step = (.2 + gap * .22).clamp(.22, .38);
    heading += (rnd.nextDouble() - .5) * 1.1;

    Offset? centre;
    for (var tries = 0; tries < 12; tries++) {
      final dir = Offset(math.cos(heading), math.sin(heading));
      var c = pos + dir * step;
      final half = (chord - 1) * _apart / 2;
      final perp = Offset(-dir.dy, dir.dx);
      // Rebote: si se sale, se da la vuelta.
      final ex = half * perp.dx.abs(), ey = half * perp.dy.abs();
      if (c.dx - ex < _left || c.dx + ex > _right) {
        heading = math.pi - heading;
        continue;
      }
      if (c.dy - ey < _top || c.dy + ey > _bottom) {
        heading = -heading;
        continue;
      }
      // Que no pise una diana que aun se ve.
      final crowded = _crowded(notes, spots, i, c);
      if (crowded && tries < 11) {
        heading += 1.1;
        continue;
      }
      c = Offset(c.dx.clamp(_left, _right), c.dy.clamp(_top, _bottom));
      centre = c;
      break;
    }

    final dir = Offset(math.cos(heading), math.sin(heading));
    // Si no ha encontrado sitio, el paso tal cual, dentro del escenario.
    final c = pos + dir * step;
    centre ??= Offset(c.dx.clamp(_left, _right), c.dy.clamp(_top, _bottom));
    final perp = Offset(-dir.dy, dir.dx);
    for (var k = 0; k < chord; k++) {
      final at = centre + perp * ((k - (chord - 1) / 2) * _apart);
      final spot = Offset(at.dx.clamp(_left, _right), at.dy.clamp(_top, _bottom));
      // Llega desde detras del camino, con un giro hacia un lado u otro.
      side = -side;
      final back = heading + math.pi + side * (.5 + rnd.nextDouble() * .5);
      final from = spot + Offset(math.cos(back), math.sin(back)) * .7;
      final mid = (from + spot) / 2;
      final swing = Offset(-(spot - from).dy, (spot - from).dx) * (.22 * side);
      spots[i + k] = ButaiSpot(at: spot, from: from, bend: mid + swing);
    }
    pos = centre;
    i = j;
  }
  return [for (final s in spots) s!];
}

bool _crowded(List<ChartNote> notes, List<ButaiSpot?> spots, int i, Offset c) {
  final t = notes[i].time;
  for (var k = i - 1; k >= 0; k--) {
    final n = notes[k];
    // Las que ya se han ido no molestan; una larga sigue ahi hasta su final.
    if (t - n.end > .5) {
      if (t - n.time > 4) break;
      continue;
    }
    if ((spots[k]!.at - c).distance < _apart) return true;
  }
  return false;
}

/// Radio de las dianas en un escenario de [area].
double butaiRadius(Rect area) => (math.min(area.width, area.height) * .075).clamp(26.0, 44.0);

/// La tecla que toca un dedo puesto en [point]: la de la nota mas proxima
/// en el tiempo cuya diana esta cerca del dedo. En tactil no hace falta
/// saber que boton es cada figura; se toca la diana y ya.
int? butaiPick(OdoriEngine engine, List<ButaiSpot> spots, Offset point, Rect area, double now, double approach) {
  final notes = engine.chart.notes;
  final reach = butaiRadius(area) * 2;
  int? best;
  var bestScore = double.infinity;
  for (var i = 0; i < notes.length; i++) {
    final n = notes[i];
    if (n.time - approach > now) break;
    if (engine.state[i] != NoteState.pending) continue;
    if (n.time < now - windowVale) continue;
    final at = spots[i].at;
    final c = Offset(area.left + at.dx * area.width, area.top + at.dy * area.height);
    final d = (c - point).distance;
    if (d > reach) continue;
    // Manda el tiempo; la distancia solo desempata.
    final score = (n.time - now).abs() + d / reach * .05;
    if (score < bestScore) {
      bestScore = score;
      best = n.lane;
    }
  }
  return best;
}

/// El escenario con las dianas y las notas volando.
class ButaiStage extends StatelessWidget {
  const ButaiStage({
    super.key,
    required this.engine,
    required this.spots,
    required this.time,
    required this.fx,
    required this.accent,
    this.approach = 1.2,
    this.mark = ButaiMark.arrows,
    this.caps = const [],
    this.labels = const [],
    this.inset = EdgeInsets.zero,
    this.radius = 22,
  });

  final OdoriEngine engine;
  final List<ButaiSpot> spots;
  final ValueNotifier<double> time;
  final TakiFx fx;
  final Color accent;

  /// Segundos que tarda una nota en llegar a su diana.
  final double approach;

  /// Lo que llevan las burbujas, y las teclas si son las teclas.
  final ButaiMark mark;
  final List<String> caps;

  /// Lo que dice cada juicio, por [Judgment.index], para escribirlo sobre la
  /// diana. Sin ellos, solo los estallidos.
  final List<String> labels;

  /// Lo que tapan el marcador, la letra y los botones: el fondo llega hasta
  /// el borde, pero las dianas se quedan dentro.
  final EdgeInsets inset;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(size: Size.infinite, painter: _ButaiPainter(this)),
      ),
    );
  }
}

class _ButaiPainter extends CustomPainter {
  _ButaiPainter(this.stage) : super(repaint: stage.time);

  final ButaiStage stage;

  @override
  void paint(Canvas canvas, Size size) {
    final now = stage.time.value;
    _backdrop(canvas, size, now);

    final area = stage.inset.deflateRect(Offset.zero & size);
    final r = butaiRadius(area);
    Offset px(Offset o) => Offset(area.left + o.dx * area.width, area.top + o.dy * area.height);

    final notes = stage.engine.chart.notes;
    final state = stage.engine.state;
    final approach = stage.approach;

    // Primero los caminos, luego las dianas y al final las notas, para que
    // vuelen por encima de todo.
    final visible = <int>[];
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.time - approach > now) break;
      final st = state[i];
      if (st == NoteState.done) continue;
      if (st == NoteState.missed && now - (n.hold ? n.end : n.time) > .3) continue;
      visible.add(i);
    }
    for (final i in visible) {
      final n = notes[i];
      if (state[i] != NoteState.pending || now > n.time) continue;
      final p = (1 - (n.time - now) / approach).clamp(0.0, 1.0);
      _path(canvas, stage.spots[i], p, px, r, butaiColors[n.lane], now);
    }
    for (final i in visible) {
      _target(canvas, px(stage.spots[i].at), r, notes[i], state[i], now);
    }
    for (final i in visible.reversed) {
      final n = notes[i];
      final st = state[i];
      if (st == NoteState.holding || now > n.time + .3) continue;
      final p = (1 - (n.time - now) / approach).clamp(0.0, 1.0);
      final spot = stage.spots[i];
      // Estela: la nota un poco antes, cada vez mas tenue.
      for (var k = 5; k >= 1; k--) {
        final q = (p - k * .03).clamp(0.0, 1.0);
        canvas.drawCircle(
          px(spot.fly(q)),
          r * (.8 - k * .09),
          Paint()..color = butaiColors[n.lane].withValues(alpha: (st == NoteState.missed ? .05 : .18) * (6 - k) / 5),
        );
      }
      _bubble(canvas, px(spot.fly(p)), r * .88, n.lane, faded: st == NoteState.missed);
    }

    // Lo que ha pasado en cada diana: estallidos al acertar, una cruz al
    // fallar y el juicio escrito encima.
    var missFlash = 0.0;
    for (final (lane, at, j) in stage.fx.bursts) {
      final age = now - at;
      if (age < 0 || age > .6) continue;
      final spot = _burstSpot(lane, at, j);
      if (j == Judgment.miss && age < .3) missFlash = math.max(missFlash, 1 - age / .3);
      if (spot == null) continue;
      final centre = px(spot);
      if (j == Judgment.miss) {
        _missMark(canvas, centre, r, age);
      } else if (age < .4) {
        _burst(canvas, centre, r, lane, j, age / .4);
      }
      if (j.index < stage.labels.length) _judgeLabel(canvas, centre, r, j, age);
    }
    // Un fallo tiñe un poco los bordes de rojo.
    if (missFlash > 0) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(rect.center, rect.longestSide * .62, [
            const Color(0x00FF4D6A),
            const Color(0xFFFF4D6A).withValues(alpha: .22 * missFlash),
          ], [.62, 1]),
      );
    }
  }

  /// El camino que le queda a una nota hasta su diana: una linea tenue y
  /// unos puntos que se encienden a medida que la nota se acerca.
  void _path(Canvas canvas, ButaiSpot spot, double p, Offset Function(Offset) px, double r, Color color, double now) {
    const steps = 22;
    final path = Path();
    for (var k = 0; k <= steps; k++) {
      final o = px(spot.fly(p + (1 - p) * k / steps));
      if (k == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    final born = (p * 5).clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .16
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: .16 * born),
    );
    // Puntos fijos en el camino, que corren hacia la diana.
    final shift = (now * 2.2) % 1;
    for (var k = 0; k < 12; k++) {
      final q = (k + shift) / 12;
      if (q < p) continue;
      final near = (q - p) / math.max(.001, 1 - p);
      canvas.drawCircle(
        px(spot.fly(q)),
        r * (.1 + .05 * (1 - near)),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: (.2 + .45 * p) * born * (1 - near * .6)),
      );
    }
  }

  void _burst(Canvas canvas, Offset centre, double r, int lane, Judgment j, double k) {
    final brillo = j == Judgment.brillo;
    final col = brillo ? odoriAmber : butaiColors[lane];
    final strength = switch (j) {
      Judgment.brillo => 1.0,
      Judgment.bien => .8,
      _ => .5,
    };
    // Un destello que llena la diana.
    if (k < .5) {
      canvas.drawCircle(
        centre,
        r * (1 + k * .6),
        Paint()..color = Color.lerp(col, const Color(0xFFFFFFFF), .5)!.withValues(alpha: .45 * strength * (1 - k * 2)),
      );
    }
    canvas.drawCircle(
      centre,
      r * (1 + k * 1.3 * strength),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * strength * (1 - k)
        ..color = col.withValues(alpha: 1 - k),
    );
    if (brillo) {
      // El brillo: un segundo anillo dorado y rayos.
      canvas.drawCircle(
        centre,
        r * (1.2 + k * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - k)
          ..color = const Color(0xFFFFF1B8).withValues(alpha: .8 * (1 - k)),
      );
      for (var s = 0; s < 8; s++) {
        final a = s * math.pi / 4 + math.pi / 8;
        final dir = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(
          centre + dir * r * (1.1 + k * .8),
          centre + dir * r * (1.5 + k * 1.8),
          Paint()
            ..strokeWidth = 3 * (1 - k)
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFFFE08A).withValues(alpha: 1 - k),
        );
      }
    }
    final sparks = j == Judgment.vale ? 4 : 8;
    for (var s = 0; s < sparks; s++) {
      final a = s * math.pi * 2 / sparks + lane;
      canvas.drawCircle(
        centre + Offset(math.cos(a), math.sin(a)) * r * (1 + k * 1.6 * strength),
        3.5 * (1 - k),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 1 - k),
      );
    }
  }

  /// El fallo: una cruz roja que tiembla y se apaga sobre la diana.
  void _missMark(Canvas canvas, Offset centre, double r, double age) {
    if (age > .45) return;
    final k = age / .45;
    final shake = math.sin(age * 70) * r * .12 * (1 - k);
    final c = centre + Offset(shake, 0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * (1 - k * .5)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFF4D6A).withValues(alpha: 1 - k);
    canvas.drawCircle(c, r * (1 - k * .25), paint..strokeWidth = 3);
    final d = r * .45;
    paint.strokeWidth = 5 * (1 - k * .5);
    canvas
      ..drawLine(c + Offset(-d, -d), c + Offset(d, d), paint)
      ..drawLine(c + Offset(d, -d), c + Offset(-d, d), paint);
  }

  /// El juicio escrito sobre la diana, que sube y se desvanece.
  void _judgeLabel(Canvas canvas, Offset centre, double r, Judgment j, double age) {
    final k = age / .6;
    final color = switch (j) {
      Judgment.brillo => const Color(0xFFFFD66B),
      Judgment.bien => const Color(0xFFFFFFFF),
      Judgment.vale => const Color(0xFFC9D3F0),
      Judgment.miss => const Color(0xFFFF6B82),
    };
    final pop = age < .08 ? 1 + (.08 - age) * 3 : 1.0;
    // La opacidad va a saltos para que las letras maquetadas se reutilicen.
    final alpha = ((1 - k * k) * 10).round() / 10;
    if (alpha <= 0) return;
    _text(
      canvas,
      centre - Offset(0, r * 1.45 + 18 * k),
      stage.labels[j.index],
      (r * .62).clamp(15.0, 24.0).roundToDouble(),
      color.withValues(alpha: alpha),
      scale: pop,
    );
  }

  /// La diana de la nota juzgada en [lane] hacia [at]. Un fallo se juzga
  /// cuando la nota ya ha pasado, asi que se busca algo mas atras.
  Offset? _burstSpot(int lane, double at, Judgment j) {
    final notes = stage.engine.chart.notes;
    Offset? best;
    var d = .3;
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.time > at + .3) break;
      if (n.lane != lane) continue;
      if (j == Judgment.miss && stage.engine.state[i] != NoteState.missed) continue;
      final e = math.min((n.time - at).abs(), (n.end - at).abs());
      if (e < d) {
        d = e;
        best = stage.spots[i].at;
      }
    }
    return best;
  }

  void _backdrop(Canvas canvas, Size size, double now) {
    final rect = Offset.zero & size;
    final (top, bottom) = butaiNight(stage.accent);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [top, bottom]),
    );
    // El suelo del escenario, un poco mas claro.
    final floor = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 1.02),
      width: size.width * 1.3,
      height: size.height * .5,
    );
    canvas.drawOval(
      floor,
      Paint()
        ..shader = ui.Gradient.radial(floor.center, floor.width / 2, [
          Color.lerp(top, stage.accent, .35)!.withValues(alpha: .7),
          top.withValues(alpha: 0),
        ]),
    );
    // Focos que se mecen despacio desde arriba.
    for (var k = 0; k < 3; k++) {
      final x = size.width * (.2 + k * .3);
      final sway = math.sin(now * .6 + k * 2.1) * size.width * .12;
      final path = Path()
        ..moveTo(x - 8, 0)
        ..lineTo(x + 8, 0)
        ..lineTo(x + sway + size.width * .14, size.height)
        ..lineTo(x + sway - size.width * .14, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(Offset(x, 0), Offset(x, size.height), [
            const Color(0xFFFFFFFF).withValues(alpha: .10),
            const Color(0xFFFFFFFF).withValues(alpha: 0),
          ]),
      );
    }
    // Estrellitas que parpadean.
    final rnd = math.Random(7);
    for (var k = 0; k < 34; k++) {
      final p = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height * .7);
      final tw = .35 + .35 * math.sin(now * (1.2 + rnd.nextDouble() * 2) + k);
      canvas.drawCircle(p, .8 + rnd.nextDouble() * 1.2, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: tw));
    }
  }

  void _target(Canvas canvas, Offset c, double r, ChartNote n, NoteState st, double now) {
    final color = butaiColors[n.lane];
    final born = (now - (n.time - stage.approach)) / .15;
    final fade = st == NoteState.missed ? .3 : born.clamp(0.0, 1.0);
    final grow = .6 + .4 * Curves.easeOutBack.transform(born.clamp(0.0, 1.0));
    final rr = r * grow;
    canvas.drawCircle(c, rr, Paint()..color = const Color(0xFF0B1433).withValues(alpha: .35 * fade));
    canvas.drawCircle(
      c,
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color.withValues(alpha: .85 * fade),
    );
    if (n.hold) {
      canvas.drawCircle(
        c,
        rr + 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: .5 * fade),
      );
    }
    _mark(canvas, c, rr * .5, n.lane, color.withValues(alpha: .45 * fade), stage.mark, stage.caps);

    if (st == NoteState.holding) {
      // Mantenida: un arco que se llena hasta el final de la larga.
      final k = ((now - n.time) / math.max(.01, n.end - n.time)).clamp(0.0, 1.0);
      canvas.drawCircle(c, rr, Paint()..color = color.withValues(alpha: .35));
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: rr + 6),
        -math.pi / 2,
        math.pi * 2 * k,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFFFFFFF),
      );
      return;
    }
    // La aguja del reloj: da una vuelta mientras la nota vuela.
    final p = (1 - (n.time - now) / stage.approach).clamp(0.0, 1.0);
    final a = -math.pi / 2 + p * math.pi * 2;
    canvas.drawLine(
      c,
      c + Offset(math.cos(a), math.sin(a)) * rr * .92,
      Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFFFFF).withValues(alpha: .8 * fade),
    );
  }

  void _bubble(Canvas canvas, Offset c, double r, int lane, {bool faded = false}) {
    final color = butaiColors[lane];
    final alpha = faded ? .3 : 1.0;
    canvas.drawCircle(c + const Offset(0, 3), r, Paint()..color = const Color(0xFF050A1C).withValues(alpha: .35 * alpha));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c + Offset(-r * .3, -r * .4), r * 1.3, [
          Color.lerp(color, const Color(0xFFFFFFFF), .55)!.withValues(alpha: alpha),
          color.withValues(alpha: alpha),
        ]),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFFFFFFFF).withValues(alpha: .9 * alpha),
    );
    _mark(canvas, c, r * .55, lane, const Color(0xFFFFFFFF).withValues(alpha: alpha), stage.mark, stage.caps);
  }

  @override
  bool shouldRepaint(_ButaiPainter old) => old.stage != stage;
}

/// El dibujo de una tecla dentro de su burbuja, de [r] de medio lado.
void _mark(Canvas canvas, Offset c, double r, int lane, Color color, ButaiMark mark, List<String> caps) {
  switch (mark) {
    case ButaiMark.arrows:
      _arrow(canvas, c, r, lane, Paint()..color = color);
    case ButaiMark.shapes:
      _shape(canvas, c, r, lane, color);
    case ButaiMark.keys:
      if (lane < caps.length) {
        _cap(canvas, c, r, caps[lane], color);
      } else {
        _arrow(canvas, c, r, lane, Paint()..color = color);
      }
  }
}

/// Las figuras de los mandos: □ ✕ △ ○, en el orden de las flechas.
void _shape(Canvas canvas, Offset c, double r, int lane, Color color) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(2, r * .26)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;
  final k = r * .78;
  switch (lane) {
    case 0:
      canvas.drawRect(Rect.fromCircle(center: c, radius: k * .9), paint);
    case 1:
      canvas
        ..drawLine(c + Offset(-k, -k), c + Offset(k, k), paint)
        ..drawLine(c + Offset(k, -k), c + Offset(-k, k), paint);
    case 2:
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - k * 1.05)
          ..lineTo(c.dx + k * 1.05, c.dy + k * .75)
          ..lineTo(c.dx - k * 1.05, c.dy + k * .75)
          ..close(),
        paint,
      );
    default:
      canvas.drawCircle(c, k, paint);
  }
}

/// Las letras ya maquetadas, por texto, tamaño y color: se pintan decenas
/// por fotograma y maquetar cada vez sale caro.
final Map<(String, int, int), TextPainter> _caps = <(String, int, int), TextPainter>{};

TextPainter _layout(String text, double size, Color color) {
  final key = (text, size.round(), color.toARGB32());
  var tp = _caps[key];
  if (tp == null) {
    if (_caps.length > 400) _caps.clear();
    tp = _caps[key] = TextPainter(
      text: TextSpan(
        text: text,
        style: Ty.lead.copyWith(
          fontSize: size.roundToDouble(),
          fontWeight: FontWeight.w800,
          color: color,
          height: 1,
          shadows: [Shadow(color: const Color(0xFF050A1C).withValues(alpha: color.a * .6), blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }
  return tp;
}

/// Escribe [text] centrado en [c], encogido a lo mas [scale].
void _text(Canvas canvas, Offset c, String text, double size, Color color, {double scale = 1}) {
  final tp = _layout(text, size, color);
  canvas
    ..save()
    ..translate(c.dx, c.dy)
    ..scale(scale);
  tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
  canvas.restore();
}

void _cap(Canvas canvas, Offset c, double r, String text, Color color) {
  final tp = _layout(text, r * 1.7, color);
  // Una tecla con nombre largo se encoge para caber en la burbuja.
  _text(canvas, c, text, r * 1.7, color, scale: math.min(1.0, r * 1.9 / math.max(1, tp.width)));
}

void _arrow(Canvas canvas, Offset c, double r, int lane, Paint paint) {
  final path = Path()
    ..moveTo(r, 0)
    ..lineTo(0, -r)
    ..lineTo(0, -r * .45)
    ..lineTo(-r, -r * .45)
    ..lineTo(-r, r * .45)
    ..lineTo(0, r * .45)
    ..lineTo(0, r)
    ..close();
  canvas
    ..save()
    ..translate(c.dx, c.dy)
    ..rotate(butaiAngles[lane]);
  canvas.drawPath(path, paint);
  canvas.restore();
}

/// El simbolo de una tecla de Butai: su burbuja de color con la flecha.
class ButaiSymbol extends StatelessWidget {
  const ButaiSymbol({
    super.key,
    required this.lane,
    this.size = 28,
    this.pressed = false,
    this.mark = ButaiMark.arrows,
    this.caps = const [],
  });

  final int lane;
  final double size;
  final bool pressed;
  final ButaiMark mark;
  final List<String> caps;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _SymbolPainter(lane, pressed, mark, caps));
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.lane, this.pressed, this.mark, this.caps);

  final int lane;
  final bool pressed;
  final ButaiMark mark;
  final List<String> caps;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final color = butaiColors[lane];
    canvas.drawCircle(c, r, Paint()..color = pressed ? color : Color.lerp(color, const Color(0xFFFFFFFF), .2)!);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF).withValues(alpha: .9),
    );
    _mark(canvas, c, r * .55, lane, const Color(0xFFFFFFFF), mark, caps);
  }

  @override
  bool shouldRepaint(_SymbolPainter old) =>
      old.lane != lane || old.pressed != pressed || old.mark != mark || !listEquals(old.caps, caps);
}

/// Los cuatro botones para jugar con los dedos: dos a cada lado, para los
/// pulgares. Cada boton lleva la cuenta de sus dedos, asi que se pueden
/// pulsar varios a la vez.
class ButaiPad extends StatefulWidget {
  const ButaiPad({
    super.key,
    required this.onPress,
    required this.onRelease,
    this.height = 84,
    this.mark = ButaiMark.arrows,
    this.caps = const [],
  });

  final ValueChanged<int> onPress;
  final ValueChanged<int> onRelease;
  final double height;
  final ButaiMark mark;
  final List<String> caps;

  @override
  State<ButaiPad> createState() => _ButaiPadState();
}

class _ButaiPadState extends State<ButaiPad> {
  final Map<int, int> _pointers = <int, int>{};

  bool _down(int lane) => _pointers.values.contains(lane);

  void _start(int pointer, int lane) {
    final was = _down(lane);
    setState(() => _pointers[pointer] = lane);
    if (!was) widget.onPress(lane);
  }

  void _end(int pointer) {
    final lane = _pointers[pointer];
    if (lane == null) return;
    setState(() => _pointers.remove(pointer));
    if (!_down(lane)) widget.onRelease(lane);
  }

  Widget _button(int lane) => Expanded(
        child: Listener(
          key: ValueKey<String>('odori.pad.$lane'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _start(e.pointer, lane),
          onPointerUp: (e) => _end(e.pointer),
          onPointerCancel: (e) => _end(e.pointer),
          child: Center(
            child: ButaiSymbol(
              lane: lane,
              size: widget.height * .78,
              pressed: _down(lane),
              mark: widget.mark,
              caps: widget.caps,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: Row(
          children: [
            _button(0),
            _button(1),
            const Spacer(),
            _button(2),
            _button(3),
          ],
        ),
      );
}
