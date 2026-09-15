// Ibasho — iconografia del entorno, dibujada a mano.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Los iconos del entorno.
///
/// Se dibujan con `Path` sobre una caja de 24x24 en lugar de tirar de una
/// fuente de iconos: asi el trazo es el mismo redondeado que la tipografia y
/// no entra ni un asset de Material por la puerta de atras.
enum Glyph {
  gear,
  person,
  keycard,
  slot,
  arrowLeft,
  arrowRight,
  magnify,
  check,
  cross,
  copy,
  refresh,
  power,
  note,
  speaker,
  dice,
  info,
  bug,
  play,
  globe,
  plus,
  lock,
  eye,
  eyeOff,
  cake,
  clock,
  chevronDown,
  tama,
}

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    required this.color,
    this.strokeWidth = 1.9,
  });

  final Glyph glyph;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _GlyphPainter(glyph, color, strokeWidth),
        ),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color, this.strokeWidth);

  final Glyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.save();
    canvas.scale(scale);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final fill = Paint()..color = color;

    switch (glyph) {
      case Glyph.gear:
        _gear(canvas, stroke, fill);
      case Glyph.person:
        canvas.drawCircle(const Offset(12, 8.4), 4.1, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(4.6, 20)
            ..cubicTo(4.6, 15.6, 8, 14, 12, 14)
            ..cubicTo(16, 14, 19.4, 15.6, 19.4, 20),
          stroke,
        );
      case Glyph.keycard:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(3, 5.5, 18, 13), const Radius.circular(3.2)),
          stroke,
        );
        canvas.drawCircle(const Offset(8.6, 12), 2.3, stroke);
        canvas.drawLine(const Offset(13.2, 10.4), const Offset(18.2, 10.4), stroke);
        canvas.drawLine(const Offset(13.2, 13.6), const Offset(16.4, 13.6), stroke);
      case Glyph.slot:
        final dashed = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = color;
        _dashedRRect(
          canvas,
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(3.5, 5, 17, 14), const Radius.circular(3.6)),
          dashed,
        );
      case Glyph.arrowLeft:
        canvas.drawPath(
          Path()
            ..moveTo(14.6, 5.5)
            ..lineTo(8.4, 12)
            ..lineTo(14.6, 18.5),
          stroke..strokeWidth = strokeWidth * 1.25,
        );
      case Glyph.arrowRight:
        canvas.drawPath(
          Path()
            ..moveTo(9.4, 5.5)
            ..lineTo(15.6, 12)
            ..lineTo(9.4, 18.5),
          stroke..strokeWidth = strokeWidth * 1.25,
        );
      case Glyph.chevronDown:
        canvas.drawPath(
          Path()
            ..moveTo(6, 9.6)
            ..lineTo(12, 15.2)
            ..lineTo(18, 9.6),
          stroke,
        );
      case Glyph.magnify:
        // Dos flechas opuestas en diagonal: ampliar y reducir.
        canvas.drawLine(const Offset(4.6, 4.6), const Offset(10.2, 10.2), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(4.4, 9.6)
            ..lineTo(4.4, 4.4)
            ..lineTo(9.6, 4.4),
          stroke,
        );
        canvas.drawLine(const Offset(19.4, 19.4), const Offset(13.8, 13.8), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(19.6, 14.4)
            ..lineTo(19.6, 19.6)
            ..lineTo(14.4, 19.6),
          stroke,
        );
      case Glyph.check:
        canvas.drawPath(
          Path()
            ..moveTo(5.2, 12.6)
            ..lineTo(10, 17.2)
            ..lineTo(18.8, 7.2),
          stroke..strokeWidth = strokeWidth * 1.2,
        );
      case Glyph.cross:
        canvas.drawLine(const Offset(6.5, 6.5), const Offset(17.5, 17.5), stroke);
        canvas.drawLine(const Offset(17.5, 6.5), const Offset(6.5, 17.5), stroke);
      case Glyph.copy:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(8, 3.6, 12.4, 14), const Radius.circular(3)),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(15.6, 20.4)
            ..lineTo(6.6, 20.4)
            ..cubicTo(4.9, 20.4, 3.6, 19.1, 3.6, 17.4)
            ..lineTo(3.6, 7.6),
          stroke,
        );
      case Glyph.refresh:
        _circularArrow(canvas, stroke);
      case Glyph.dice:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(4, 4, 16, 16), const Radius.circular(4.2)),
          stroke,
        );
        for (final pip in const [
          Offset(8.6, 8.6),
          Offset(15.4, 8.6),
          Offset(12, 12),
          Offset(8.6, 15.4),
          Offset(15.4, 15.4),
        ]) {
          canvas.drawCircle(pip, 1.35, fill);
        }
      case Glyph.info:
        canvas.drawCircle(const Offset(12, 12), 8.6, stroke);
        canvas.drawLine(const Offset(12, 10.8), const Offset(12, 16.6), stroke);
        canvas.drawCircle(const Offset(12, 7.6), 1.25, fill);
      case Glyph.bug:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(7.4, 8.2, 9.2, 12), const Radius.circular(4.6)),
          stroke,
        );
        canvas.drawLine(const Offset(12, 11), const Offset(12, 20), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(9, 8.6)
            ..quadraticBezierTo(9, 4.6, 12, 4.6)
            ..quadraticBezierTo(15, 4.6, 15, 8.6),
          stroke,
        );
        for (final y in const [11.4, 15.2, 18.6]) {
          canvas.drawLine(Offset(7.4, y), Offset(4.2, y - 1.4), stroke);
          canvas.drawLine(Offset(16.6, y), Offset(19.8, y - 1.4), stroke);
        }
      case Glyph.power:
        canvas.drawArc(
          const Rect.fromLTWH(4.6, 4.6, 14.8, 14.8),
          -math.pi * .36,
          math.pi * 1.72,
          false,
          stroke,
        );
        canvas.drawLine(const Offset(12, 3.2), const Offset(12, 11), stroke);
      case Glyph.note:
        canvas.drawCircle(const Offset(8, 17.4), 3.1, stroke);
        canvas.drawCircle(const Offset(18.2, 15.2), 2.6, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(11.1, 17.4)
            ..lineTo(11.1, 6.6)
            ..lineTo(20.8, 4.6)
            ..lineTo(20.8, 15.2),
          stroke,
        );
      case Glyph.speaker:
        canvas.drawPath(
          Path()
            ..moveTo(3.8, 9.2)
            ..lineTo(7.6, 9.2)
            ..lineTo(12.4, 5)
            ..lineTo(12.4, 19)
            ..lineTo(7.6, 14.8)
            ..lineTo(3.8, 14.8)
            ..close(),
          stroke,
        );
        canvas.drawArc(const Rect.fromLTWH(11, 8.2, 6.4, 7.6), -math.pi * .36,
            math.pi * .72, false, stroke);
        canvas.drawArc(const Rect.fromLTWH(11, 4.8, 10.4, 14.4), -math.pi * .36,
            math.pi * .72, false, stroke);
      case Glyph.play:
        canvas.drawPath(
          Path()
            ..moveTo(8.4, 5.6)
            ..lineTo(18.6, 12)
            ..lineTo(8.4, 18.4)
            ..close(),
          stroke,
        );
      case Glyph.globe:
        canvas.drawCircle(const Offset(12, 12), 8.4, stroke);
        canvas.drawLine(const Offset(3.6, 12), const Offset(20.4, 12), stroke);
        canvas.drawOval(const Rect.fromLTWH(7.4, 3.6, 9.2, 16.8), stroke);
      case Glyph.plus:
        canvas.drawLine(const Offset(12, 5.6), const Offset(12, 18.4), stroke);
        canvas.drawLine(const Offset(5.6, 12), const Offset(18.4, 12), stroke);
      case Glyph.lock:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(4.8, 10.4, 14.4, 9.6), const Radius.circular(3)),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(8.2, 10.4)
            ..lineTo(8.2, 7.8)
            ..cubicTo(8.2, 5.7, 9.9, 4, 12, 4)
            ..cubicTo(14.1, 4, 15.8, 5.7, 15.8, 7.8)
            ..lineTo(15.8, 10.4),
          stroke,
        );
      case Glyph.eye:
        canvas.drawPath(
          Path()
            ..moveTo(2.6, 12)
            ..cubicTo(5.6, 6.8, 8.8, 5.2, 12, 5.2)
            ..cubicTo(15.2, 5.2, 18.4, 6.8, 21.4, 12)
            ..cubicTo(18.4, 17.2, 15.2, 18.8, 12, 18.8)
            ..cubicTo(8.8, 18.8, 5.6, 17.2, 2.6, 12)
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 12), 2.9, stroke);
      case Glyph.eyeOff:
        canvas.drawPath(
          Path()
            ..moveTo(2.6, 12)
            ..cubicTo(5.6, 6.8, 8.8, 5.2, 12, 5.2)
            ..cubicTo(15.2, 5.2, 18.4, 6.8, 21.4, 12)
            ..cubicTo(18.4, 17.2, 15.2, 18.8, 12, 18.8)
            ..cubicTo(8.8, 18.8, 5.6, 17.2, 2.6, 12)
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 12), 2.9, stroke);
        canvas.drawLine(const Offset(4.4, 20.4), const Offset(19.6, 3.6), stroke);
      case Glyph.cake:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(3.6, 11.4, 16.8, 8.6), const Radius.circular(2.8)),
          stroke,
        );
        canvas.drawLine(const Offset(12, 5.4), const Offset(12, 11.4), stroke);
        canvas.drawCircle(const Offset(12, 4.2), 1.3, fill);
        canvas.drawLine(const Offset(7.4, 8.4), const Offset(7.4, 11.4), stroke);
        canvas.drawLine(const Offset(16.6, 8.4), const Offset(16.6, 11.4), stroke);
      case Glyph.clock:
        canvas.drawCircle(const Offset(12, 12), 8.4, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(12, 7.2)
            ..lineTo(12, 12.4)
            ..lineTo(15.6, 14.6),
          stroke,
        );
      case Glyph.tama:
        // Silueta reservada para el CP2: una cabeza redonda con dos antenas.
        canvas.drawCircle(const Offset(12, 13.4), 6.4, stroke);
        canvas.drawLine(const Offset(8.4, 7.8), const Offset(6.6, 4.2), stroke);
        canvas.drawLine(const Offset(15.6, 7.8), const Offset(17.4, 4.2), stroke);
        canvas.drawCircle(const Offset(6.4, 3.4), 1.2, fill);
        canvas.drawCircle(const Offset(17.6, 3.4), 1.2, fill);
    }

    canvas.restore();
  }

  /// Flecha circular. La punta sale de la tangente real del final del arco,
  /// asi que siempre queda alineada con el trazo.
  void _circularArrow(Canvas canvas, Paint stroke) {
    const centre = Offset(12, 12);
    const radius = 7.6;
    const start = -math.pi * .30;
    const sweep = math.pi * 1.62;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      start,
      sweep,
      false,
      stroke,
    );
    final end = start + sweep;
    final tip = centre + Offset(math.cos(end), math.sin(end)) * radius;
    // Direccion de avance del arco en sentido horario.
    final forward = Offset(-math.sin(end), math.cos(end));
    final normal = Offset(math.cos(end), math.sin(end));
    const length = 4.4;
    final back = tip - forward * length;
    canvas.drawPath(
      Path()
        ..moveTo(back.dx + normal.dx * 3.2, back.dy + normal.dy * 3.2)
        ..lineTo(tip.dx + forward.dx * .6, tip.dy + forward.dy * .6)
        ..lineTo(back.dx - normal.dx * 3.2, back.dy - normal.dy * 3.2),
      stroke,
    );
  }

  void _gear(Canvas canvas, Paint stroke, Paint fill) {
    const teeth = 8;
    final path = Path();
    for (var i = 0; i < teeth; i++) {
      final angle = i * 2 * math.pi / teeth;
      final outer = Offset(12 + 9.4 * math.cos(angle), 12 + 9.4 * math.sin(angle));
      final inner = Offset(12 + 6.9 * math.cos(angle), 12 + 6.9 * math.sin(angle));
      path.moveTo(inner.dx, inner.dy);
      path.lineTo(outer.dx, outer.dy);
    }
    canvas.drawPath(path, stroke..strokeWidth = strokeWidth * 1.45);
    canvas.drawCircle(const Offset(12, 12), 7, stroke..strokeWidth = strokeWidth);
    canvas.drawCircle(const Offset(12, 12), 2.8, stroke);
  }

  void _dashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 3.2, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 3.0;
      }
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.strokeWidth != strokeWidth;
}

/// Indicador de bateria al estilo de los de 3DS.
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({
    super.key,
    required this.level,
    required this.charging,
    required this.color,
    required this.accent,
    required this.warn,
    this.height = 15,
  });

  final int level;
  final bool charging;
  final Color color;
  final Color accent;
  final Color warn;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: height * 2.1,
        height: height,
        child: CustomPaint(
          painter: _BatteryPainter(level, charging, color, accent, warn),
        ),
      );
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.level, this.charging, this.color, this.accent, this.warn);

  final int level;
  final bool charging;
  final Color color;
  final Color accent;
  final Color warn;

  @override
  void paint(Canvas canvas, Size size) {
    final nubWidth = size.width * .09;
    final body = Rect.fromLTWH(0, 0, size.width - nubWidth - 1.5, size.height);
    final radius = Radius.circular(size.height * .32);

    canvas.drawRRect(
      RRect.fromRectAndRadius(body.deflate(.75), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = color,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.right + 1.5,
          size.height * .3,
          nubWidth,
          size.height * .4,
        ),
        Radius.circular(nubWidth * .5),
      ),
      Paint()..color = color,
    );

    final inner = body.deflate(3);
    final fraction = (level / 100).clamp(0.0, 1.0);
    if (fraction > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(inner.left, inner.top, inner.width * fraction, inner.height),
          Radius.circular(inner.height * .34),
        ),
        Paint()..color = level <= 15 && !charging ? warn : accent,
      );
    }

    if (charging) {
      final centre = body.center;
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx + 1.6, centre.dy - size.height * .34)
          ..lineTo(centre.dx - 2.2, centre.dy + size.height * .06)
          ..lineTo(centre.dx + .2, centre.dy + size.height * .06)
          ..lineTo(centre.dx - 1.4, centre.dy + size.height * .36)
          ..lineTo(centre.dx + 2.6, centre.dy - size.height * .08)
          ..lineTo(centre.dx + .2, centre.dy - size.height * .08)
          ..close(),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.level != level || old.charging != charging || old.color != color;
}

/// Tres arcos concentricos: la intensidad de la conexion.
class SignalArcs extends StatelessWidget {
  const SignalArcs({
    super.key,
    required this.bars,
    required this.color,
    required this.dim,
    this.size = 17,
  });

  /// 0 a 3.
  final int bars;
  final Color color;
  final Color dim;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SignalPainter(bars, color, dim)),
      );
}

class _SignalPainter extends CustomPainter {
  _SignalPainter(this.bars, this.color, this.dim);

  final int bars;
  final Color color;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * .5, size.height * .92);
    canvas.drawCircle(origin, size.width * .105, Paint()..color = bars > 0 ? color : dim);
    for (var i = 0; i < 3; i++) {
      final radius = size.width * (.26 + .21 * i);
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        -math.pi * .82,
        math.pi * .64,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7
          ..strokeCap = StrokeCap.round
          ..color = bars > i ? color : dim,
      );
    }
  }

  @override
  bool shouldRepaint(_SignalPainter old) => old.bars != bars || old.color != color;
}
