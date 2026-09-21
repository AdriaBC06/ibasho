// Ibasho — la cara de un regalo envuelto.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

/// Un regalo envuelto que llena todo su espacio: caja dorada, cinta naranja
/// que la cruza y un lazo grande encima, como los regalos del HOME de la 3DS.
/// Colores propios: un regalo se ve igual con cualquier acento.
class GiftFace extends StatelessWidget {
  const GiftFace({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(child: CustomPaint(painter: _GiftPainter()));
  }
}

class _GiftPainter extends CustomPainter {
  const _GiftPainter();

  static const Color _boxTop = Color(0xFFFBD86E);
  static const Color _boxBottom = Color(0xFFF3B443);
  static const Color _ribbon = Color(0xFFEB7B47);
  static const Color _bow = Color(0xFFE5683A);
  static const Color _bowEdge = Color(0xFFC24F27);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final box = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * .1, h * .12, w * .8, h * .76),
      Radius.circular(w * .1),
    );
    canvas.drawRRect(
      box,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_boxTop, _boxBottom],
        ).createShader(box.outerRect),
    );

    // Cinta vertical, de canto a canto de la caja.
    final ribbonW = w * .17;
    canvas.save();
    canvas.clipRRect(box);
    canvas.drawRect(
      Rect.fromLTWH(cx - ribbonW / 2, h * .12, ribbonW, h * .76),
      Paint()..color = _ribbon,
    );
    canvas.restore();

    final fill = Paint()..color = _bow;
    final edge = Paint()
      ..color = _bowEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .022
      ..strokeJoin = StrokeJoin.round;
    final cy = h * .44;

    void loop(double side) {
      final path = Path()
        ..moveTo(cx, cy)
        ..quadraticBezierTo(
          cx + side * w * .3,
          cy - h * .3,
          cx + side * w * .37,
          cy - h * .05,
        )
        ..quadraticBezierTo(cx + side * w * .3, cy + h * .17, cx, cy)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }

    void tail(double side) {
      final path = Path()
        ..moveTo(cx, cy)
        ..lineTo(cx + side * w * .2, cy + h * .34)
        ..lineTo(cx + side * w * .06, cy + h * .27)
        ..lineTo(cx + side * w * .01, cy + h * .34)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, edge);
    }

    tail(-1);
    tail(1);
    loop(-1);
    loop(1);
    canvas.drawCircle(Offset(cx, cy), w * .075, fill);
    canvas.drawCircle(Offset(cx, cy), w * .075, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
