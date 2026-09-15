// Ibasho — el logotipo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

/// La marca: las dos pantallas del entorno, una sobre otra.
class IbashoMark extends StatelessWidget {
  const IbashoMark({super.key, this.size = 96, required this.accent});

  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MarkPainter(accent)),
      );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final deep = Color.lerp(accent, T.dusk, .34)!;

    void screen(Rect rect, double radius, {required bool filled}) {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
      canvas.drawRRect(
        rrect.shift(Offset(0, s * .018)),
        Paint()
          ..color = T.shadowDeep
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * .035),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: filled
                ? [Color.lerp(accent, T.shellTop, .26)!, deep]
                : const [T.shellTop, T.shellBottom],
          ).createShader(rect),
      );
      // Brillo especular, igual que en cualquier otra pieza del entorno.
      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [T.glintStrong, T.glintNone],
            stops: const [0, .52],
          ).createShader(rect),
      );
      canvas.restore();
      canvas.drawRRect(
        rrect.deflate(.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * .012
          ..color = filled ? deep : T.hairline,
      );
    }

    // Pantalla superior, algo mas estrecha.
    screen(
      Rect.fromLTWH(s * .17, s * .10, s * .66, s * .33),
      s * .09,
      filled: false,
    );
    // Pantalla inferior, la de los canales.
    screen(
      Rect.fromLTWH(s * .08, s * .50, s * .84, s * .40),
      s * .11,
      filled: true,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.accent != accent;
}
