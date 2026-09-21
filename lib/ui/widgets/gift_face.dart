// Ibasho — la cara de un regalo envuelto.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Un regalo envuelto que llena todo su espacio: un caramelo grande de papel
/// azul con lunares, las dos puntas retorcidas y una estrella dorada de
/// pegatina. Colores propios: un regalo se ve igual con cualquier acento.
class GiftFace extends StatelessWidget {
  const GiftFace({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(child: CustomPaint(painter: _GiftPainter()));
  }
}

class _GiftPainter extends CustomPainter {
  const _GiftPainter();

  static const Color _paperTop = Color(0xFF7FD6F7);
  static const Color _paperBottom = Color(0xFF3BA9E0);
  static const Color _twist = Color(0xFF2E8FC6);
  static const Color _edge = Color(0xFF1F6F9E);
  static const Color _dot = Color(0xB3FFFFFF);
  static const Color _star = Color(0xFFFFD25A);
  static const Color _starEdge = Color(0xFFE0A21F);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cy = h * .5;

    final edge = Paint()
      ..color = _edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .02
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Las puntas retorcidas: un abanico plegado a cada lado del cuerpo.
    void twist(double side) {
      final root = w * (side < 0 ? .27 : .73);
      final tip = w * (side < 0 ? .04 : .96);
      final mid = w * (side < 0 ? .11 : .89);
      final path = Path()
        ..moveTo(root, cy - h * .11)
        ..lineTo(tip, cy - h * .27)
        ..quadraticBezierTo(mid, cy, tip, cy + h * .27)
        ..lineTo(root, cy + h * .11)
        ..close();
      canvas.drawPath(path, Paint()..color = _twist);
      canvas.drawPath(path, edge);
      for (final k in [-.14, 0.0, .14]) {
        canvas.drawLine(
          Offset(root, cy + h * k * .5),
          Offset(mid, cy + h * k),
          edge..strokeWidth = w * .012,
        );
      }
      edge.strokeWidth = w * .02;
    }

    twist(-1);
    twist(1);

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * .24, h * .17, w * .52, h * .66),
      Radius.circular(w * .2),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_paperTop, _paperBottom],
        ).createShader(body.outerRect),
    );

    // Lunares, recortados por el cuerpo.
    canvas.save();
    canvas.clipRRect(body);
    final dots = Paint()..color = _dot;
    for (final d in const [
      Offset(.32, .28),
      Offset(.62, .25),
      Offset(.7, .5),
      Offset(.3, .62),
      Offset(.55, .76),
      Offset(.42, .44),
    ]) {
      canvas.drawCircle(Offset(w * d.dx, h * d.dy), w * .028, dots);
    }
    canvas.restore();
    canvas.drawRRect(body, edge);

    // Pegatina: una estrella de cinco puntas en el centro.
    final star = Path();
    final centre = Offset(w * .5, cy);
    final outer = w * .12;
    final inner = outer * .46;
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = centre + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    star.close();
    canvas.drawPath(star, Paint()..color = _star);
    canvas.drawPath(
      star,
      Paint()
        ..color = _starEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .016
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
