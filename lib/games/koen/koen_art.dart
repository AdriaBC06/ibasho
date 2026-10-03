// Ibasho — Tama Kōen: el icono y el parque pintado.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../backend/koen.dart';
import '../../ui/widgets/channel_art.dart';

/// Dónde está cada zona, en fracciones de la escena: el punto del suelo
/// donde se ponen los Tamas que juegan allí.
const Map<KoenZone, Offset> koenZoneAt = {
  KoenZone.tree: Offset(.14, .55),
  KoenZone.swings: Offset(.39, .52),
  KoenZone.slide: Offset(.66, .50),
  KoenZone.pond: Offset(.84, .74),
  KoenZone.sandbox: Offset(.22, .84),
  KoenZone.picnic: Offset(.56, .86),
};

/// Altura del horizonte, en fracción de la escena.
const double koenHorizon = .33;

/// Dónde están las dos farolas (el pie), en fracciones de la escena.
const List<Offset> koenLamps = [Offset(.50, .66), Offset(.95, .50)];

/// Las capas del parque. El suelo va al fondo y el aire (lo que cae y las
/// luciérnagas) encima de todo; las demás son las cosas altas, que se ordenan
/// con los Tamas por la «y» de su base ([koenLayerBase]) para que pasen por
/// delante o por detrás.
enum KoenLayer { ground, tree, swings, slide, lampNear, lampFar, air }

/// La «y» del pie de cada cosa alta, en fracción de la escena.
final Map<KoenLayer, double> koenLayerBase = {
  KoenLayer.tree: koenZoneAt[KoenZone.tree]!.dy,
  KoenLayer.swings: koenZoneAt[KoenZone.swings]!.dy,
  KoenLayer.slide: koenZoneAt[KoenZone.slide]!.dy,
  KoenLayer.lampNear: koenLamps[0].dy,
  KoenLayer.lampFar: koenLamps[1].dy,
};

/// Lo que encoge un Tama al fondo: de .8 cerca del horizonte a 1.08 abajo
/// del todo.
double koenDepthScale(double y) => .8 + ((y - .45) / .5).clamp(0.0, 1.0) * .28;

/// Si [p] (en fracciones) cae dentro del estanque, donde no se pasea.
bool koenInPond(Offset p, Size size) {
  final u = math.min(size.width, size.height * 1.6) / 100;
  final c = koenZoneAt[KoenZone.pond]!;
  final cx = c.dx * size.width;
  final cy = c.dy * size.height - u * 2;
  final dx = (p.dx * size.width - cx) / (u * 17);
  final dy = (p.dy * size.height - cy) / (u * 7.5);
  return dx * dx + dy * dy <= 1;
}

/// El icono del canal: un cerezo en flor, un banco y un Tama en la hierba.
void paintKoen(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(50, 90), 82);
  // La hierba, una loma de plástico.
  final hill = Path()
    ..moveTo(8, 88)
    ..cubicTo(14, 66, 86, 66, 92, 88)
    ..close();
  paintPlastic(canvas, hill, const Color(0xFF9EDB8F), edge: 2);
  // El tronco y la copa del cerezo.
  final trunk = Path()
    ..moveTo(31, 80)
    ..lineTo(33, 52)
    ..lineTo(38, 52)
    ..lineTo(39, 80)
    ..close();
  paintPlastic(canvas, trunk, Art.wood, edge: 1.6, shine: .4);
  // Una sola silueta: la unión de las bolas, para que el borde no se vea
  // por dentro de la copa.
  Path ball(Offset c, double r) => Path()..addOval(Rect.fromCircle(center: c, radius: r));
  final crown = [
    ball(const Offset(26, 40), 15),
    ball(const Offset(44, 34), 17),
    ball(const Offset(38, 52), 12),
    ball(const Offset(34, 42), 12),
  ].reduce((a, b) => Path.combine(PathOperation.union, a, b));
  paintPlastic(canvas, crown, Art.sakura, edge: 2);
  for (final p in const [Offset(22, 36), Offset(40, 28), Offset(50, 40), Offset(34, 48)]) {
    canvas.drawCircle(p, 2.6, Paint()..color = const Color(0xFFFFF3F7));
  }
  // El Tama: una gota celeste, contenta.
  const c = Offset(68, 72);
  final body = Path()..addOval(Rect.fromCenter(center: c, width: 30, height: 26));
  paintPlastic(canvas, body, const Color(0xFF9FD4FF), edge: 1.8);
  final ink = Paint()..color = Art.deep(const Color(0xFF9FD4FF), .7);
  canvas.drawCircle(c + const Offset(-6, -2), 2.2, ink);
  canvas.drawCircle(c + const Offset(6, -2), 2.2, ink);
  canvas.drawArc(
    Rect.fromCenter(center: c + const Offset(0, 3), width: 7, height: 5),
    .2,
    math.pi - .4,
    false,
    Paint()
      ..color = ink.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round,
  );
  // Un pétalo cayendo.
  canvas.drawOval(Rect.fromCenter(center: const Offset(62, 46), width: 6, height: 4), Paint()..color = Art.sakura);
}

/// Lo que se mueve en el escenario al tocarlo. Lo cambia el canal; el
/// pintor solo lo lee.
class KoenSceneFx {
  /// Ángulo y velocidad de los dos asientos del columpio.
  final List<double> swing = [0, 0];
  final List<double> swingVel = [0, 0];

  /// El pato del estanque, de 0 a 1 a lo ancho del agua, y adónde va.
  double duck = .3;
  double duckTo = .3;
  bool duckLeft = false;

  /// Hasta cuándo se mueve el árbol (en segundos del reloj de la escena).
  double treeShakeUntil = -1;

  /// El castillo de arena: de 0 (nada) a 3 (con bandera).
  int castle = 0;

  /// Hasta cuándo salta el onigiri del picnic.
  double onigiriUntil = -1;

  /// Hasta cuándo parpadean las farolas al tocarlas.
  double lampUntil = -1;

  /// Avanza [dt] segundos.
  void step(double dt) {
    for (var i = 0; i < 2; i++) {
      swingVel[i] += (-swing[i] * 9 - swingVel[i] * .5) * dt;
      swing[i] += swingVel[i] * dt;
    }
    final d = duckTo - duck;
    if (d.abs() > .002) {
      duckLeft = d < 0;
      duck += d.sign * math.min(d.abs(), dt * .12);
    }
  }

  bool get busy => swing.any((a) => a.abs() > .004) || swingVel.any((v) => v.abs() > .004) || (duckTo - duck).abs() > .002;
}

/// Una capa del parque ([layer]): el suelo con el cielo, las lomas y lo que
/// está a ras de suelo; una de las cosas altas, o el aire, con lo que cae del
/// cielo según la estación. Los Tamas van entre medias, como widgets.
class KoenScenePainter extends CustomPainter {
  KoenScenePainter({
    required this.layer,
    required this.season,
    required this.daylight,
    required this.time,
    required this.fx,
    required this.reducedMotion,
    super.repaint,
  });

  final KoenLayer layer;
  final KoenSeason season;

  /// De 0 (noche) a 1 (día).
  final double daylight;

  /// Segundos del reloj de la escena, para lo que se mueve solo.
  final ValueNotifier<double> time;
  final KoenSceneFx fx;
  final bool reducedMotion;

  double get _t => reducedMotion ? 0 : time.value;
  double get _night => 1 - daylight;

  /// Oscurece un color según la hora: de noche todo tira a azul.
  Color _shade(Color c) => Color.lerp(c, const Color(0xFF1C2350), _night * .55)!;

  static const _grass = {
    KoenSeason.spring: Color(0xFFA6DE92),
    KoenSeason.summer: Color(0xFF7CCB72),
    KoenSeason.autumn: Color(0xFFC9C77A),
    KoenSeason.winter: Color(0xFFEAF1F7),
  };

  static const _hills = {
    KoenSeason.spring: Color(0xFF8CCB84),
    KoenSeason.summer: Color(0xFF5DAF63),
    KoenSeason.autumn: Color(0xFFD69A5A),
    KoenSeason.winter: Color(0xFFD6E1EC),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final u = math.min(w, h * 1.6) / 100;
    Offset at(KoenZone z) => Offset(koenZoneAt[z]!.dx * w, koenZoneAt[z]!.dy * h);
    Offset lamp(int i) => Offset(koenLamps[i].dx * w, koenLamps[i].dy * h);
    switch (layer) {
      case KoenLayer.ground:
        break;
      case KoenLayer.tree:
        return _tree(canvas, at(KoenZone.tree), u);
      case KoenLayer.swings:
        return _swings(canvas, at(KoenZone.swings), u);
      case KoenLayer.slide:
        return _slide(canvas, at(KoenZone.slide), u);
      case KoenLayer.lampNear:
        return _lamp(canvas, lamp(0), u);
      case KoenLayer.lampFar:
        return _lamp(canvas, lamp(1), u);
      case KoenLayer.air:
        _falling(canvas, size, u);
        if (_night > .3) _fireflies(canvas, size, u);
        return;
    }
    _sky(canvas, size);
    _hillsLayer(canvas, size);
    // El suelo.
    final groundTop = h * koenHorizon;
    final ground = Rect.fromLTRB(0, groundTop, w, h);
    canvas.drawRect(
      ground,
      Paint()
        ..shader = ui.Gradient.linear(ground.topCenter, ground.bottomCenter, [
          _shade(Color.lerp(_grass[season]!, const Color(0xFFFFFFFF), .12)!),
          _shade(_grass[season]!),
        ]),
    );
    _path(canvas, size);
    _pond(canvas, at(KoenZone.pond), u);
    _sandbox(canvas, at(KoenZone.sandbox), u);
    _picnic(canvas, at(KoenZone.picnic), u);
  }

  void _sky(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height * koenHorizon + 2);
    final dusk = 1 - (daylight * 2 - 1).abs();
    final top = Color.lerp(const Color(0xFF1B2452), const Color(0xFF8ECFFF), daylight)!;
    var low = Color.lerp(const Color(0xFF39407A), const Color(0xFFE2F4FF), daylight)!;
    low = Color.lerp(low, const Color(0xFFFFB38A), dusk * .75)!;
    canvas.drawRect(rect, Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [top, low]));
    // Las estrellas, siempre en el mismo sitio.
    if (_night > .05) {
      final star = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: _night * .85);
      for (var i = 0; i < 26; i++) {
        final x = (koenHash('star$i') % 1000) / 1000 * size.width;
        final y = (koenHash('sky$i') % 1000) / 1000 * rect.height * .85;
        final twinkle = .6 + .4 * math.sin(_t * 1.7 + i);
        canvas.drawCircle(Offset(x, y), (1 + i % 3 * .5) * twinkle, star);
      }
    }
    // El sol de día y la luna de noche, en lo alto a la derecha.
    final r = rect.height * .17;
    final c = Offset(size.width * .8, rect.height * .38);
    if (daylight > .5) {
      canvas.drawCircle(c, r * 1.8, Paint()..color = const Color(0x55FFF1B0));
      canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFE27A));
    } else {
      // Media luna recortada de verdad (no tapada con un círculo del color
      // del cielo, que no coincide con el degradado), con un halo suave.
      canvas.drawCircle(c, r * 1.7, Paint()..color = const Color(0x22F4F1DC));
      final moon = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: c, radius: r)),
        Path()..addOval(Rect.fromCircle(center: c + Offset(r * .5, -r * .22), radius: r * .88)),
      );
      canvas.drawPath(moon, Paint()..color = const Color(0xFFF4F1DC));
    }
  }

  void _hillsLayer(Canvas canvas, Size size) {
    final w = size.width;
    final y = size.height * koenHorizon;
    final far = Path()
      ..moveTo(0, y)
      ..cubicTo(w * .15, y - size.height * .12, w * .35, y - size.height * .02, w * .5, y - size.height * .08)
      ..cubicTo(w * .7, y - size.height * .16, w * .85, y - size.height * .03, w, y - size.height * .07)
      ..lineTo(w, y + 2)
      ..lineTo(0, y + 2)
      ..close();
    canvas.drawPath(far, Paint()..color = _shade(Color.lerp(_hills[season]!, const Color(0xFFB8D4F0), .45)!));
    final near = Path()
      ..moveTo(0, y + 2)
      ..cubicTo(w * .2, y - size.height * .06, w * .45, y + size.height * .01, w * .62, y - size.height * .04)
      ..cubicTo(w * .8, y - size.height * .08, w * .92, y - size.height * .01, w, y - size.height * .02)
      ..lineTo(w, y + 4)
      ..lineTo(0, y + 4)
      ..close();
    canvas.drawPath(near, Paint()..color = _shade(_hills[season]!));
  }

  void _path(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * .30, h)
      ..cubicTo(w * .36, h * .78, w * .30, h * .62, w * .46, h * .52)
      ..cubicTo(w * .58, h * .44, w * .70, h * .44, w * .78, h * .36);
    final colour = season == KoenSeason.winter ? const Color(0xFFD7DEE6) : const Color(0xFFEBD9B4);
    canvas.drawPath(
      path,
      Paint()
        ..color = _shade(colour)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.min(w, h) * .07
        ..strokeCap = StrokeCap.round,
    );
  }

  Paint _fill(Color c) => Paint()..color = _shade(c);

  Paint _line(Color c, double width) => Paint()
    ..color = _shade(c)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  void _tree(Canvas canvas, Offset base, double u) {
    final shake = _t < fx.treeShakeUntil ? math.sin(_t * 40) * u * .8 * (fx.treeShakeUntil - _t) : 0.0;
    final trunk = Path()
      ..moveTo(base.dx - u * 2.6, base.dy)
      ..lineTo(base.dx - u * 1.6, base.dy - u * 22)
      ..lineTo(base.dx + u * 1.6, base.dy - u * 22)
      ..lineTo(base.dx + u * 2.6, base.dy)
      ..close();
    canvas.drawPath(trunk, _fill(const Color(0xFF9A6A3E)));
    final top = base + Offset(shake, -u * 30);
    if (season == KoenSeason.winter) {
      // Ramas peladas con nieve encima.
      final branch = _line(const Color(0xFF8A5E36), u * 1.2);
      canvas.drawLine(base + Offset(0, -u * 18), top + Offset(-u * 9, u * 2), branch);
      canvas.drawLine(base + Offset(0, -u * 20), top + Offset(u * 10, 0), branch);
      canvas.drawLine(base + Offset(0, -u * 22), top + Offset(0, -u * 6), branch);
      final snow = _fill(const Color(0xFFFFFFFF));
      for (final o in [Offset(-u * 9, u * 1), Offset(u * 10, -u * 1), Offset(0, -u * 7)]) {
        canvas.drawOval(Rect.fromCenter(center: top + o, width: u * 4, height: u * 1.6), snow);
      }
      return;
    }
    final leaf = switch (season) {
      KoenSeason.spring => const Color(0xFFFFB9CF),
      KoenSeason.summer => const Color(0xFF58B25E),
      KoenSeason.autumn => const Color(0xFFE88A3C),
      KoenSeason.winter => const Color(0xFFFFFFFF),
    };
    for (final (o, r) in [
      (Offset(-u * 8, u * 2), u * 9.0),
      (Offset(u * 8, u * 1), u * 10.0),
      (Offset(0, -u * 6), u * 11.0),
      (Offset(-u * 2, u * 6), u * 8.0),
    ]) {
      canvas.drawCircle(top + o, r, _fill(leaf));
    }
    final light = _fill(Color.lerp(leaf, const Color(0xFFFFFFFF), .45)!);
    for (final o in [Offset(-u * 9, -u * 2), Offset(u * 4, -u * 9), Offset(u * 11, u * 2)]) {
      canvas.drawCircle(top + o, u * 2, light);
    }
  }

  void _swings(Canvas canvas, Offset base, double u) {
    final frame = _line(const Color(0xFFE2565E), u * 1.3);
    final topY = base.dy - u * 20;
    final left = base.dx - u * 11;
    final right = base.dx + u * 11;
    canvas.drawLine(Offset(left - u * 3, base.dy), Offset(left, topY), frame);
    canvas.drawLine(Offset(left + u * 3, base.dy), Offset(left, topY), frame);
    canvas.drawLine(Offset(right - u * 3, base.dy), Offset(right, topY), frame);
    canvas.drawLine(Offset(right + u * 3, base.dy), Offset(right, topY), frame);
    canvas.drawLine(Offset(left, topY), Offset(right, topY), frame);
    final rope = _line(const Color(0xFF6B5A4A), u * .45);
    for (var i = 0; i < 2; i++) {
      final hx = base.dx + (i == 0 ? -u * 5 : u * 5);
      final a = fx.swing[i];
      final len = u * 14;
      final seat = Offset(hx + math.sin(a) * len, topY + math.cos(a) * len);
      canvas.drawLine(Offset(hx - u * 1.6, topY), seat + Offset(-u * 1.6, 0), rope);
      canvas.drawLine(Offset(hx + u * 1.6, topY), seat + Offset(u * 1.6, 0), rope);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: seat, width: u * 5, height: u * 1.2), Radius.circular(u * .6)),
        _fill(const Color(0xFFFFD166)),
      );
    }
  }

  void _slide(Canvas canvas, Offset base, double u) {
    final ladder = _line(const Color(0xFF7A8CA0), u * .9);
    final x0 = base.dx - u * 9;
    canvas.drawLine(Offset(x0, base.dy), Offset(x0, base.dy - u * 16), ladder);
    canvas.drawLine(Offset(x0 + u * 3.4, base.dy), Offset(x0 + u * 3.4, base.dy - u * 16), ladder);
    for (var i = 1; i < 5; i++) {
      final y = base.dy - u * 3.2 * i;
      canvas.drawLine(Offset(x0, y), Offset(x0 + u * 3.4, y), ladder);
    }
    final chute = Path()
      ..moveTo(x0 + u * 3.4, base.dy - u * 16)
      ..cubicTo(base.dx + u * 2, base.dy - u * 14, base.dx + u * 3, base.dy - u * 1, base.dx + u * 11, base.dy - u * .5);
    canvas.drawPath(chute, _line(const Color(0xFF4BB3E8), u * 2.6));
    canvas.drawPath(chute, _line(const Color(0xFFA9E1FF), u * .7));
    canvas.drawRect(Rect.fromLTWH(x0 - u * .5, base.dy - u * 17, u * 4.4, u * 1.4), _fill(const Color(0xFFE2565E)));
  }

  void _sandbox(Canvas canvas, Offset c, double u) {
    final rect = Rect.fromCenter(center: c + Offset(0, -u * 1), width: u * 22, height: u * 8);
    canvas.drawRRect(RRect.fromRectAndRadius(rect.inflate(u * 1.2), Radius.circular(u * 1.5)), _fill(const Color(0xFFC98B4F)));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(u)),
      _fill(season == KoenSeason.winter ? const Color(0xFFF2F5F8) : const Color(0xFFF3D9A0)),
    );
    // El cubo y la pala.
    canvas.drawRect(Rect.fromLTWH(rect.right - u * 5, rect.top + u * 1, u * 2.6, u * 2.8), _fill(const Color(0xFFFF7A59)));
    if (fx.castle <= 0) return;
    final sand = _fill(const Color(0xFFE2BE7A));
    final cx = rect.left + u * 6;
    final by = rect.center.dy + u * 1.5;
    canvas.drawRect(Rect.fromLTWH(cx - u * 3, by - u * 3, u * 6, u * 3), sand);
    if (fx.castle >= 2) {
      canvas.drawRect(Rect.fromLTWH(cx - u * 4, by - u * 5, u * 2, u * 5), sand);
      canvas.drawRect(Rect.fromLTWH(cx + u * 2, by - u * 5, u * 2, u * 5), sand);
    }
    if (fx.castle >= 3) {
      canvas.drawLine(Offset(cx, by - u * 3), Offset(cx, by - u * 8), _line(const Color(0xFF6B5A4A), u * .4));
      canvas.drawPath(
        Path()
          ..moveTo(cx, by - u * 8)
          ..lineTo(cx + u * 2.6, by - u * 7.2)
          ..lineTo(cx, by - u * 6.4)
          ..close(),
        _fill(const Color(0xFFE2565E)),
      );
    }
  }

  void _pond(Canvas canvas, Offset c, double u) {
    final rect = Rect.fromCenter(center: c + Offset(0, -u * 2), width: u * 30, height: u * 11);
    final frozen = season == KoenSeason.winter;
    canvas.drawOval(rect.inflate(u * 1.2), _fill(const Color(0xFFB9A88F)));
    canvas.drawOval(rect, _fill(frozen ? const Color(0xFFCFE6F5) : const Color(0xFF6CC3E8)));
    final shine = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: .35 + .1 * math.sin(_t * 1.3))
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * .5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(u * 2), math.pi * 1.1, .7, false, shine);
    if (!frozen) {
      for (final o in [Offset(-u * 9, u * 2), Offset(u * 6, u * 3)]) {
        canvas.drawOval(Rect.fromCenter(center: rect.center + o, width: u * 3.6, height: u * 1.6), _fill(const Color(0xFF5DAF63)));
      }
    }
    // El pato: de día nada; de noche duerme con el ojo cerrado.
    final dx = rect.left + u * 4 + (rect.width - u * 8) * fx.duck;
    final bob = math.sin(_t * 2) * u * .3;
    final duck = Offset(dx, rect.center.dy - u * .8 + bob);
    final dir = fx.duckLeft ? -1.0 : 1.0;
    const white = Color(0xFFFFFFFF);
    const wingInk = Color(0xFFD5DEE6);
    // La cola, en pico hacia atrás y arriba.
    canvas.drawPath(
      Path()
        ..moveTo(duck.dx - dir * u * 1.6, duck.dy - u * .6)
        ..lineTo(duck.dx - dir * u * 3.2, duck.dy - u * 1.5)
        ..lineTo(duck.dx - dir * u * 2.2, duck.dy + u * .4)
        ..close(),
      _fill(white),
    );
    canvas.drawOval(Rect.fromCenter(center: duck, width: u * 5, height: u * 2.8), _fill(white));
    // El ala.
    canvas.drawArc(
      Rect.fromCenter(center: duck + Offset(-dir * u * .3, -u * .1), width: u * 2.8, height: u * 1.5),
      dir > 0 ? .2 : math.pi - 1.6 - .2,
      1.6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * .35
        ..strokeCap = StrokeCap.round
        ..color = wingInk,
    );
    if (daylight <= .3) {
      // Dormido: la cabeza delante y más baja que de día, el ojo cerrado.
      final head = duck + Offset(dir * u * 1.7, -u * 1.3);
      canvas.drawCircle(head, u * 1.25, _fill(white));
      canvas.drawArc(
        Rect.fromCircle(center: head + Offset(dir * u * .35, -u * .25), radius: u * .32),
        .25,
        math.pi - .5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * .22
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2E3943),
      );
      canvas.drawPath(
        Path()
          ..moveTo(head.dx + dir * u * 1.05, head.dy)
          ..lineTo(head.dx + dir * u * 2.2, head.dy + u * .45)
          ..lineTo(head.dx + dir * u * 1.05, head.dy + u * .8)
          ..close(),
        _fill(const Color(0xFFFFA43B)),
      );
    }
    if (daylight > .3) {
      final head = duck + Offset(dir * u * 2, -u * 2);
      canvas.drawCircle(head, u * 1.4, _fill(const Color(0xFFFFFFFF)));
      canvas.drawCircle(head + Offset(dir * u * .4, -u * .3), u * .3, _fill(const Color(0xFF2E3943)));
      canvas.drawPath(
        Path()
          ..moveTo(head.dx + dir * u * 1.2, head.dy - u * .2)
          ..lineTo(head.dx + dir * u * 2.6, head.dy + u * .2)
          ..lineTo(head.dx + dir * u * 1.2, head.dy + u * .6)
          ..close(),
        _fill(const Color(0xFFFFA43B)),
      );
    }
  }

  void _picnic(Canvas canvas, Offset c, double u) {
    final blanket = Rect.fromCenter(center: c + Offset(0, -u * 1), width: u * 18, height: u * 7);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(blanket, Radius.circular(u)));
    canvas.drawRect(blanket, _fill(const Color(0xFFFFF7EC)));
    final check = _fill(const Color(0xFFF2636E));
    final step = u * 3;
    for (var i = 0; i * step < blanket.width; i++) {
      for (var j = 0; j * step < blanket.height; j++) {
        if ((i + j).isEven) {
          canvas.drawRect(Rect.fromLTWH(blanket.left + i * step, blanket.top + j * step, step, step), check);
        }
      }
    }
    canvas.restore();
    // La cesta y un onigiri, que salta al tocarlo.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(blanket.right - u * 6, blanket.top - u * 2, u * 5, u * 4), Radius.circular(u)),
      _fill(const Color(0xFFD99A5B)),
    );
    final hop = _t < fx.onigiriUntil ? -math.sin((fx.onigiriUntil - _t) * math.pi * 2).abs() * u * 3 : 0.0;
    final o = Offset(blanket.left + u * 5, blanket.center.dy + hop);
    canvas.drawPath(
      Path()
        ..moveTo(o.dx, o.dy - u * 2.2)
        ..lineTo(o.dx + u * 2.2, o.dy + u * 1.4)
        ..lineTo(o.dx - u * 2.2, o.dy + u * 1.4)
        ..close(),
      _fill(const Color(0xFFFFFFFF)),
    );
    canvas.drawRect(Rect.fromLTWH(o.dx - u * 1.1, o.dy + u * .2, u * 2.2, u * 1.2), _fill(const Color(0xFF2E3943)));
  }

  void _lamp(Canvas canvas, Offset base, double u) {
    canvas.drawLine(base, base + Offset(0, -u * 17), _line(const Color(0xFF3A4750), u * .9));
    final head = base + Offset(0, -u * 18);
    final flicker = _t < fx.lampUntil ? (math.sin(_t * 30) > 0 ? 1.0 : .3) : 1.0;
    final on = _night * flicker;
    if (on > .05) {
      canvas.drawCircle(head, u * 7, Paint()..color = const Color(0xFFFFD27A).withValues(alpha: .28 * on));
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: head, width: u * 3, height: u * 3.6), Radius.circular(u * .8)),
      Paint()..color = Color.lerp(_shade(const Color(0xFFF4EAD0)), const Color(0xFFFFE6A0), on)!,
    );
  }

  /// Lo que cae del cielo: pétalos en primavera, hojas en otoño y nieve en
  /// invierno. En verano, nada.
  void _falling(Canvas canvas, Size size, double u) {
    if (season == KoenSeason.summer) return;
    final colour = switch (season) {
      KoenSeason.spring => const Color(0xFFFFC7D8),
      KoenSeason.autumn => const Color(0xFFE88A3C),
      _ => const Color(0xFFFFFFFF),
    };
    final paint = Paint()..color = colour.withValues(alpha: .9);
    final count = season == KoenSeason.winter ? 28 : 14;
    for (var i = 0; i < count; i++) {
      final seed = koenHash('fall$i');
      final speed = .04 + (seed % 100) / 2500;
      final y = ((_t * speed + (seed % 997) / 997) % 1) * size.height;
      final x = ((seed >> 10) % 1000) / 1000 * size.width + math.sin(_t * .8 + i) * u * 3;
      final p = Offset(x, y);
      if (season == KoenSeason.winter) {
        canvas.drawCircle(p, u * (.5 + (seed % 3) * .25), paint);
      } else {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(_t * 1.5 + i);
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: u * 1.8, height: u * 1.1), paint);
        canvas.restore();
      }
    }
  }

  void _fireflies(Canvas canvas, Size size, double u) {
    if (season == KoenSeason.winter) return;
    for (var i = 0; i < 10; i++) {
      final seed = koenHash('fly$i');
      final x = ((seed % 1000) / 1000 + math.sin(_t * .3 + i) * .03) * size.width;
      final y = (koenHorizon + .1 + ((seed >> 10) % 1000) / 1000 * .5 + math.cos(_t * .4 + i * 2) * .02) * size.height;
      final glow = (.5 + .5 * math.sin(_t * 2.2 + i * 1.7)) * (_night - .3) / .7;
      canvas.drawCircle(Offset(x, y), u * 1.6, Paint()..color = const Color(0xFFE8FF8A).withValues(alpha: .25 * glow));
      canvas.drawCircle(Offset(x, y), u * .45, Paint()..color = const Color(0xFFF4FFC0).withValues(alpha: glow));
    }
  }

  @override
  bool shouldRepaint(KoenScenePainter old) =>
      old.layer != layer || old.season != season || old.daylight != daylight || old.reducedMotion != reducedMotion;
}

/// Qué cosa del escenario hay en [p] (en fracciones de la escena), si hay
/// alguna que reaccione al tocarla.
enum KoenProp { swingLeft, swingRight, pond, tree, sandbox, picnic, lamp }

KoenProp? koenPropAt(Offset p, Size size) {
  final u = math.min(size.width, size.height * 1.6) / 100;
  final px = Offset(p.dx * size.width, p.dy * size.height);
  Offset at(KoenZone z) => Offset(koenZoneAt[z]!.dx * size.width, koenZoneAt[z]!.dy * size.height);
  bool near(Offset c, double rx, double ry) {
    final d = px - c;
    return (d.dx / rx) * (d.dx / rx) + (d.dy / ry) * (d.dy / ry) <= 1;
  }

  final swings = at(KoenZone.swings);
  if (near(swings + Offset(-u * 5, -u * 8), u * 4, u * 9)) return KoenProp.swingLeft;
  if (near(swings + Offset(u * 5, -u * 8), u * 4, u * 9)) return KoenProp.swingRight;
  if (near(at(KoenZone.pond) + Offset(0, -u * 2), u * 16, u * 7)) return KoenProp.pond;
  if (near(at(KoenZone.tree) + Offset(0, -u * 26), u * 18, u * 16)) return KoenProp.tree;
  if (near(at(KoenZone.sandbox) + Offset(0, -u * 1), u * 12, u * 5)) return KoenProp.sandbox;
  if (near(at(KoenZone.picnic) + Offset(0, -u * 1), u * 10, u * 5)) return KoenProp.picnic;
  for (final l in koenLamps) {
    final lamp = Offset(l.dx * size.width, l.dy * size.height);
    if (near(lamp + Offset(0, -u * 12), u * 3, u * 9)) return KoenProp.lamp;
  }
  return null;
}
