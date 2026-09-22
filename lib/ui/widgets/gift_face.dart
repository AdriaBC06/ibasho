// Ibasho — la cara de un regalo envuelto, y como se abre.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'channel_art.dart';

/// Un regalo envuelto que llena todo su espacio, como los de la 3DS: una caja
/// de papel cielo con lunares, cinta rosa en cruz y un lazo grande encima.
///
/// [open] va de 0 (cerrado) a 1 (abierto del todo): el lazo se deshace, la
/// tapa salta girando, salen destellos de la boca de la caja y la caja se
/// desvanece para dejar ver lo que habia dentro. Colores propios: un regalo
/// se ve igual con cualquier acento.
class GiftFace extends StatelessWidget {
  const GiftFace({super.key, this.open = 0});

  final double open;

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: CustomPaint(painter: _GiftPainter(open)));
}

class _GiftPainter extends CustomPainter {
  const _GiftPainter(this.open);

  final double open;

  static const Color _paper = Color(0xFF7FD3F7);
  static const Color _ribbon = Color(0xFFF4739E);
  static const Color _dot = Color(0xCCFFFFFF);

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    // El regalo vive en un cuadrado centrado; en una baldosa apaisada se
    // queda en el centro con aire a los lados.
    final side = math.min(size.width, size.height * 1.08);
    final s = side / 100;
    canvas.save();
    canvas.translate((size.width - 100 * s) / 2, (size.height - 100 * s) / 2 + 2 * s);
    canvas.scale(s);

    final bowT = _seg(open, 0, .35);
    final lidT = Curves.easeOutCubic.transform(_seg(open, .18, .7));
    final boxT = _seg(open, .55, 1);
    final burstT = _seg(open, .3, 1);

    canvas.saveLayer(const Rect.fromLTWH(-40, -60, 180, 200),
        Paint()..color = Color.fromRGBO(0, 0, 0, 1 - boxT));

    paintGroundShadow(canvas, const Offset(50, 91), 72 * (1 - boxT * .3));

    // Caja: cara frontal.
    const body = Rect.fromLTWH(20, 42, 60, 46);
    final bodyPath = Path()..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(8)));
    paintPlastic(canvas, bodyPath, _paper, edge: 2.2, shine: .5);
    _dots(canvas, bodyPath, body);
    // Cinta vertical de la caja.
    final band = Path()..addRect(const Rect.fromLTWH(44, 42, 12, 46));
    canvas.save();
    canvas.clipPath(bodyPath);
    paintPlastic(canvas, band, _ribbon, edge: 1.4, shine: .7);
    canvas.restore();

    // Destellos saliendo de la caja abierta.
    if (burstT > 0 && burstT < 1) {
      final rnd = math.Random(3);
      for (var i = 0; i < 9; i++) {
        final a = -math.pi / 2 + (rnd.nextDouble() - .5) * 2.1;
        final d = 12 + 46 * Curves.easeOut.transform(burstT) * (.6 + rnd.nextDouble() * .5);
        final c = const Offset(50, 42) + Offset(math.cos(a), math.sin(a)) * d;
        final fade = 1 - burstT;
        paintTwinkle(canvas, c, (3 + rnd.nextDouble() * 4) * (.4 + fade),
            Art.capsules[i % Art.capsules.length].withValues(alpha: fade));
      }
    }

    // La tapa: salta hacia arriba y a la izquierda girando.
    canvas.save();
    const pivot = Offset(50, 38);
    canvas.translate(pivot.dx - lidT * 16, pivot.dy - lidT * 34);
    canvas.rotate(-lidT * .55);
    canvas.translate(-pivot.dx, -pivot.dy);
    if (lidT > 0) {
      canvas.saveLayer(const Rect.fromLTWH(-20, -40, 140, 120),
          Paint()..color = Color.fromRGBO(0, 0, 0, 1 - _seg(open, .5, .8)));
    }
    const lid = Rect.fromLTWH(15, 32, 70, 14);
    final lidPath = Path()..addRRect(RRect.fromRectAndRadius(lid, const Radius.circular(6)));
    paintPlastic(canvas, lidPath, _paper, edge: 2.2);
    _dots(canvas, lidPath, lid);
    canvas.save();
    canvas.clipPath(lidPath);
    paintPlastic(canvas, Path()..addRect(const Rect.fromLTWH(44, 32, 12, 14)), _ribbon, edge: 1.4, shine: .8);
    canvas.restore();
    _bow(canvas, const Offset(50, 31), 1 - bowT);
    if (lidT > 0) canvas.restore();
    canvas.restore();

    canvas.restore();
    canvas.restore();
  }

  void _dots(Canvas canvas, Path clip, Rect r) {
    canvas.save();
    canvas.clipPath(clip);
    final dot = Paint()..color = _dot;
    for (var y = r.top + 6; y < r.bottom; y += 11) {
      final row = ((y - r.top) / 11).round();
      for (var x = r.left + (row.isOdd ? 11.0 : 5.5); x < r.right; x += 11) {
        canvas.drawCircle(Offset(x, y), 1.9, dot);
      }
    }
    canvas.restore();
  }

  /// El lazo: dos lazadas, dos colas y el nudo. [tied] a 0 lo deshace: las
  /// lazadas encogen y las colas se abren.
  void _bow(Canvas canvas, Offset c, double tied) {
    if (tied <= 0) return;
    final spread = 1 - tied;
    for (final side in [-1.0, 1.0]) {
      // Cola.
      final tail = Path()
        ..moveTo(c.dx + side * 2, c.dy + 2)
        ..lineTo(c.dx + side * (9 + spread * 8), c.dy + 16 + spread * 6)
        ..lineTo(c.dx + side * (5 + spread * 8), c.dy + 18 + spread * 6)
        ..lineTo(c.dx + side * (1 + spread * 3), c.dy + 13)
        ..close();
      paintPlastic(canvas, tail, Art.deep(_ribbon, .08), edge: 1.3, shine: .3);
    }
    for (final side in [-1.0, 1.0]) {
      final w = 17 * tied;
      final loop = Path()
        ..moveTo(c.dx, c.dy)
        ..cubicTo(c.dx + side * w * .6, c.dy - 17 * tied, c.dx + side * w * 1.3, c.dy - 10 * tied,
            c.dx + side * w, c.dy + 1)
        ..cubicTo(c.dx + side * w * .8, c.dy + 6 * tied, c.dx + side * w * .3, c.dy + 4 * tied, c.dx, c.dy)
        ..close();
      paintPlastic(canvas, loop, _ribbon, edge: 1.5, shine: .8);
      // Pliegue interior.
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + side * 3, c.dy - 1)
          ..quadraticBezierTo(c.dx + side * w * .55, c.dy - 7 * tied, c.dx + side * w * .8, c.dy - 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = Art.deep(_ribbon, .3),
      );
    }
    paintPlastic(canvas, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 9 * tied + 2, height: 8 * tied + 2), const Radius.circular(3))),
        _ribbon, edge: 1.4);
  }

  @override
  bool shouldRepaint(_GiftPainter old) => old.open != open;
}
