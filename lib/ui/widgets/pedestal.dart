// Ibasho — la peana de cristal bajo un foco: lo que se exhibe flota encima.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import 'channel_art.dart';

/// La peana: un disco de cristal bajo un foco, con lo que se exhibe flotando
/// encima y balanceandose despacio. Se para con movimiento reducido.
class Pedestal extends StatefulWidget {
  const Pedestal({super.key, required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  State<Pedestal> createState() => _PedestalState();
}

class _PedestalState extends State<Pedestal> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((e) => _t.value = e.inMicroseconds / 1e6);
  final ValueNotifier<double> _t = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = IbashoSkin.of(context).reducedMotion;
    if (reduced && _ticker.isActive) _ticker.stop();
    if (!reduced && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final skin = IbashoSkin.of(context);
    return SizedBox(
      width: s * 1.25,
      height: s * 1.18,
      child: CustomPaint(
        painter: PedestalPainter(skin.accent),
        child: Align(
          alignment: const Alignment(0, -.35),
          child: AnimatedBuilder(
            animation: _t,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, math.sin(_t.value * 1.8) * s * .035),
              child: Transform.rotate(angle: math.sin(_t.value * .9) * .03, child: child),
            ),
            child: SizedBox(width: s * .82, height: s * .82, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class PedestalPainter extends CustomPainter {
  PedestalPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Foco: halo del acento y rayos.
    final glowC = Offset(w / 2, h * .45);
    canvas.drawCircle(
      glowC,
      w * .55,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: .28), accent.withValues(alpha: .06), accent.withValues(alpha: 0)],
          stops: const [0, .6, 1],
        ).createShader(Rect.fromCircle(center: glowC, radius: w * .55)),
    );
    final rays = Paint()..color = T.glintSoft;
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final r = w * .6;
      canvas.drawPath(
        Path()
          ..moveTo(glowC.dx, glowC.dy)
          ..lineTo(glowC.dx + math.cos(a - .06) * r, glowC.dy + math.sin(a - .06) * r)
          ..lineTo(glowC.dx + math.cos(a + .06) * r, glowC.dy + math.sin(a + .06) * r)
          ..close(),
        rays,
      );
    }
    // La peana: un disco de cristal con canto y reflejo.
    final top = Rect.fromCenter(center: Offset(w / 2, h * .86), width: w * .82, height: h * .16);
    final side = Rect.fromLTRB(top.left, top.center.dy, top.right, top.center.dy + h * .06);
    paintGroundShadow(canvas, Offset(w / 2, h * .95), w * .86, .16);
    canvas.drawRRect(
      RRect.fromRectAndCorners(side,
          bottomLeft: Radius.elliptical(top.width / 2, top.height / 2),
          bottomRight: Radius.elliptical(top.width / 2, top.height / 2)),
      Paint()..color = Color.lerp(accent, T.shellBottom, .55)!,
    );
    canvas.drawOval(top.shift(Offset(0, h * .06)), Paint()..color = Color.lerp(accent, T.dusk, .1)!.withValues(alpha: .55));
    canvas.drawOval(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.shellTop, Color.lerp(T.shellBottom, accent, .25)!],
        ).createShader(top),
    );
    canvas.drawOval(top.deflate(top.height * .18), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = T.glintStrong);
    canvas.drawOval(top, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Color.lerp(T.hairline, accent, .35)!);
  }

  @override
  bool shouldRepaint(PedestalPainter old) => old.accent != accent;
}
