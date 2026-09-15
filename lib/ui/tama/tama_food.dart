// Ibasho — la comida de los Tamas, dibujada en codigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/tama.dart';
import '../../theme/tokens.dart';

/// Pinta una comida centrada en `c`.
///
/// Toda comida cabe en un circulo de radio `s` alrededor de `c` (lo comprueba
/// `test/tama_food_test.dart`), asi nunca se sale de su boton. Formas grandes y
/// colores de pasteleria, con el brillo de la casa: se tienen que reconocer a
/// primera vista aunque caigan pequeñitas hacia la boca.
void paintFood(Canvas canvas, TamaFood food, Offset c, double s) {
  // Las formas llegan hasta ~1,06 s con el grosor del contorno: se dibujan al
  // 92 % para que todo quede dentro del circulo de radio s.
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.scale(.92);
  canvas.translate(-c.dx, -c.dy);
  _paintFood(canvas, food, c, s);
  canvas.restore();
}

void _paintFood(Canvas canvas, TamaFood food, Offset c, double s) {
  final line = math.max(.6, s * .08);
  Paint outline(Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = line
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..color = Color.lerp(color, T.dusk, .32)!;
  Paint glossy(Color color, Rect rect) => Paint()
    ..shader = RadialGradient(
      center: const Alignment(-.35, -.45),
      colors: [Color.lerp(color, T.shellTop, .38)!, color, Color.lerp(color, T.dusk, .14)!],
      stops: const [0, .6, 1],
    ).createShader(rect);
  void shine(Offset at, double w, double h) => canvas.drawOval(
        Rect.fromCenter(center: at, width: w, height: h),
        Paint()..color = T.glintStrong,
      );
  Offset p(double x, double y) => c + Offset(x * s, y * s);
  void sprinkles(List<(double, double, double)> spots) {
    final colors = [T.foodSprinkleBlue, T.foodSprinkleYellow, T.shellTop, T.foodCherry];
    for (final (i, (x, y, angle)) in spots.indexed) {
      final at = p(x, y);
      final d = Offset(math.cos(angle), math.sin(angle)) * s * .08;
      canvas.drawLine(
        at - d,
        at + d,
        Paint()
          ..strokeWidth = s * .07
          ..strokeCap = StrokeCap.round
          ..color = colors[i % colors.length],
      );
    }
  }

  switch (food) {
    case TamaFood.cookie:
      final rect = Rect.fromCircle(center: c, radius: s * .92);
      canvas.drawOval(rect, glossy(T.foodDough, rect));
      canvas.drawOval(rect, outline(T.foodDough));
      final chip = Paint()..color = T.foodChip;
      for (final (x, y, r) in const [
        (-.4, -.18, .15),
        (.28, -.42, .12),
        (.42, .2, .14),
        (-.1, .4, .13),
        (.02, -.02, .1),
      ]) {
        canvas.drawOval(Rect.fromCenter(center: p(x, y), width: r * s * 2.1, height: r * s * 1.6), chip);
      }
      shine(p(-.42, -.52), s * .42, s * .2);

    case TamaFood.candy:
      // Caramelo envuelto: el centro y dos lazos de papel que se tocan con el.
      final wrap = Color.lerp(T.foodCandy, T.shellTop, .55)!;
      for (final side in const [-1.0, 1.0]) {
        final bow = Path()
          ..moveTo(c.dx + side * s * .48, c.dy)
          ..lineTo(c.dx + side * s * .94, c.dy - s * .4)
          ..quadraticBezierTo(c.dx + side * s * .8, c.dy, c.dx + side * s * .94, c.dy + s * .4)
          ..close();
        canvas.drawPath(bow, Paint()..color = wrap);
        canvas.drawPath(bow, outline(T.foodCandy));
      }
      final body = Rect.fromCenter(center: c, width: s * 1.08, height: s * .92);
      canvas.drawOval(body, glossy(T.foodCandy, body));
      canvas.save();
      canvas.clipPath(Path()..addOval(body));
      final stripe = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .13
        ..color = T.glintPanel;
      for (var i = -2; i <= 2; i++) {
        canvas.drawLine(p(i * .36 - .5, .6), p(i * .36 + .5, -.6), stripe);
      }
      canvas.restore();
      canvas.drawOval(body, outline(T.foodCandy));
      shine(p(-.2, -.26), s * .3, s * .13);

    case TamaFood.cupcake:
      // Molde con pliegues y un glaseado en espiral de un solo contorno.
      final cup = Path()
        ..moveTo(c.dx - s * .72, c.dy + s * .08)
        ..lineTo(c.dx + s * .72, c.dy + s * .08)
        ..lineTo(c.dx + s * .5, c.dy + s * .86)
        ..quadraticBezierTo(c.dx + s * .48, c.dy + s * .92, c.dx + s * .4, c.dy + s * .92)
        ..lineTo(c.dx - s * .4, c.dy + s * .92)
        ..quadraticBezierTo(c.dx - s * .48, c.dy + s * .92, c.dx - s * .5, c.dy + s * .86)
        ..close();
      canvas.drawPath(cup, glossy(T.foodCup, cup.getBounds()));
      canvas.save();
      canvas.clipPath(cup);
      final pleat = Paint()
        ..strokeWidth = s * .06
        ..color = Color.lerp(T.foodCup, T.dusk, .22)!;
      for (var i = -2; i <= 2; i++) {
        canvas.drawLine(p(i * .28, .1), p(i * .2, .95), pleat);
      }
      canvas.restore();
      canvas.drawPath(cup, outline(T.foodCup));

      final frosting = Path()
        ..moveTo(c.dx - s * .82, c.dy + s * .12)
        ..cubicTo(c.dx - s * .9, c.dy - s * .18, c.dx - s * .6, c.dy - s * .3, c.dx - s * .4, c.dy - s * .3)
        ..cubicTo(c.dx - s * .6, c.dy - s * .55, c.dx - s * .3, c.dy - s * .72, c.dx - s * .02, c.dy - s * .66)
        ..cubicTo(c.dx + s * .1, c.dy - s * .9, c.dx + s * .4, c.dy - s * .78, c.dx + s * .32, c.dy - s * .56)
        ..cubicTo(c.dx + s * .62, c.dy - s * .5, c.dx + s * .66, c.dy - s * .34, c.dx + s * .44, c.dy - s * .28)
        ..cubicTo(c.dx + s * .72, c.dy - s * .28, c.dx + s * .92, c.dy - s * .12, c.dx + s * .82, c.dy + s * .12)
        ..quadraticBezierTo(c.dx, c.dy + s * .3, c.dx - s * .82, c.dy + s * .12)
        ..close();
      canvas.drawPath(frosting, glossy(T.foodFrosting, frosting.getBounds()));
      canvas.drawPath(frosting, outline(T.foodFrosting));
      // La vuelta de la espiral, dentro del glaseado.
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * .5, c.dy - s * .08)
          ..quadraticBezierTo(c.dx, c.dy + s * .05, c.dx + s * .5, c.dy - s * .08),
        outline(T.foodFrosting)..strokeWidth = line * .8,
      );
      sprinkles(const [(-.45, -.12, .6), (.12, -.4, -.4), (.42, -.08, 1.2), (-.14, -.5, 2.2)]);
      canvas.drawCircle(p(.02, -.78), s * .15, Paint()..color = T.foodCherry);
      shine(p(-.03, -.83), s * .08, s * .05);
      shine(p(-.42, -.2), s * .24, s * .1);

    case TamaFood.apple:
      final apple = Path()
        ..moveTo(c.dx, c.dy - s * .5)
        ..cubicTo(c.dx + s * .5, c.dy - s * .92, c.dx + s * 1.08, c.dy - s * .4, c.dx + s * .84, c.dy + s * .4)
        ..cubicTo(c.dx + s * .66, c.dy + s * .96, c.dx + s * .22, c.dy + s * .92, c.dx, c.dy + s * .8)
        ..cubicTo(c.dx - s * .22, c.dy + s * .92, c.dx - s * .66, c.dy + s * .96, c.dx - s * .84, c.dy + s * .4)
        ..cubicTo(c.dx - s * 1.08, c.dy - s * .4, c.dx - s * .5, c.dy - s * .92, c.dx, c.dy - s * .5)
        ..close();
      canvas.drawPath(apple, glossy(T.foodApple, apple.getBounds()));
      canvas.drawPath(apple, outline(T.foodApple));
      canvas.drawLine(
        p(0, -.46),
        p(.1, -.92),
        Paint()
          ..strokeWidth = s * .12
          ..strokeCap = StrokeCap.round
          ..color = T.foodStem,
      );
      shine(p(-.42, -.2), s * .26, s * .38);

    case TamaFood.dango:
      canvas.drawLine(
        p(.26, .94),
        p(-.22, -.94),
        Paint()
          ..strokeWidth = s * .12
          ..strokeCap = StrokeCap.round
          ..color = T.foodStick,
      );
      for (final (color, x, y) in [
        (T.foodDangoGreen, .15, .5),
        (T.foodDangoWhite, 0.0, 0.0),
        (T.foodDangoPink, -.15, -.5),
      ]) {
        final ball = Rect.fromCircle(center: p(x, y), radius: s * .36);
        canvas.drawOval(ball, glossy(color, ball));
        canvas.drawOval(ball, outline(color));
        shine(p(x - .13, y - .14), s * .17, s * .1);
      }

    case TamaFood.mochi:
      // Daifuku: una cupula blandita de base plana, espolvoreada.
      final mochi = Path()
        ..moveTo(c.dx - s * .78, c.dy + s * .56)
        ..cubicTo(c.dx - s * 1.0, c.dy + s * .2, c.dx - s * .72, c.dy - s * .62, c.dx, c.dy - s * .62)
        ..cubicTo(c.dx + s * .72, c.dy - s * .62, c.dx + s * 1.0, c.dy + s * .2, c.dx + s * .78, c.dy + s * .56)
        ..quadraticBezierTo(c.dx, c.dy + s * .7, c.dx - s * .78, c.dy + s * .56)
        ..close();
      canvas.drawPath(mochi, glossy(T.foodMochi, mochi.getBounds()));
      canvas.drawPath(mochi, outline(T.foodMochi));
      final flour = Paint()..color = T.shellTop;
      for (final (x, y) in const [(.3, -.2), (-.1, .18), (.5, .22), (-.45, .3), (.1, -.36)]) {
        canvas.drawCircle(p(x, y), s * .045, flour);
      }
      shine(p(-.36, -.28), s * .36, s * .18);

    case TamaFood.lollipop:
      canvas.drawLine(
        p(0, .3),
        p(0, .95),
        Paint()
          ..strokeWidth = s * .13
          ..strokeCap = StrokeCap.round
          ..color = T.shellBottom,
      );
      final disc = Rect.fromCircle(center: p(0, -.3), radius: s * .64);
      canvas.drawOval(disc, glossy(T.foodLolly, disc));
      canvas.save();
      canvas.clipPath(Path()..addOval(disc));
      final swirl = Path();
      for (var i = 0; i <= 60; i++) {
        final t = i / 60 * math.pi * 4;
        final r = s * (.04 + .6 * i / 60);
        final at = disc.center + Offset(math.cos(t), math.sin(t)) * r;
        i == 0 ? swirl.moveTo(at.dx, at.dy) : swirl.lineTo(at.dx, at.dy);
      }
      canvas.drawPath(
        swirl,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * .13
          ..strokeCap = StrokeCap.round
          ..color = T.glintPanel,
      );
      canvas.restore();
      canvas.drawOval(disc, outline(T.foodLolly));
      shine(p(-.26, -.58), s * .3, s * .14);

    case TamaFood.iceCream:
      final cone = Path()
        ..moveTo(c.dx - s * .5, c.dy + s * .02)
        ..lineTo(c.dx + s * .5, c.dy + s * .02)
        ..lineTo(c.dx + s * .04, c.dy + s * .94)
        ..quadraticBezierTo(c.dx, c.dy + s * .98, c.dx - s * .04, c.dy + s * .94)
        ..close();
      canvas.drawPath(cone, Paint()..color = T.foodCone);
      canvas.save();
      canvas.clipPath(cone);
      final waffle = Paint()
        ..strokeWidth = s * .05
        ..color = T.foodConeDark;
      for (var i = -3; i <= 3; i++) {
        canvas.drawLine(p(i * .22 - .5, 0), p(i * .22 + .5, 1), waffle);
        canvas.drawLine(p(i * .22 + .5, 0), p(i * .22 - .5, 1), waffle);
      }
      canvas.restore();
      canvas.drawPath(cone, outline(T.foodCone));
      final scoop = Path()
        ..moveTo(c.dx - s * .6, c.dy + s * .02)
        ..cubicTo(c.dx - s * .8, c.dy - s * .9, c.dx + s * .8, c.dy - s * .9, c.dx + s * .6, c.dy + s * .02)
        ..quadraticBezierTo(c.dx + s * .45, c.dy + s * .2, c.dx + s * .3, c.dy + s * .06)
        ..quadraticBezierTo(c.dx + s * .15, c.dy + s * .24, c.dx, c.dy + s * .06)
        ..quadraticBezierTo(c.dx - s * .18, c.dy + s * .22, c.dx - s * .32, c.dy + s * .06)
        ..quadraticBezierTo(c.dx - s * .48, c.dy + s * .2, c.dx - s * .6, c.dy + s * .02)
        ..close();
      canvas.drawPath(scoop, glossy(T.foodScoop, scoop.getBounds()));
      canvas.drawPath(scoop, outline(T.foodScoop));
      sprinkles(const [(-.3, -.42, .5), (.2, -.55, -.6), (.36, -.2, 1.3)]);
      shine(p(-.28, -.5), s * .3, s * .14);

    case TamaFood.donut:
      final ring = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: s * .9))
        ..addOval(Rect.fromCircle(center: c, radius: s * .3));
      canvas.drawPath(ring, glossy(T.foodDough, ring.getBounds()));
      final glaze = Path()..fillType = PathFillType.evenOdd;
      for (var i = 0; i <= 48; i++) {
        final t = i / 48 * math.pi * 2;
        final r = s * (.72 + .07 * math.sin(t * 7));
        final at = c + Offset(math.cos(t), math.sin(t)) * r;
        i == 0 ? glaze.moveTo(at.dx, at.dy) : glaze.lineTo(at.dx, at.dy);
      }
      glaze
        ..close()
        ..addOval(Rect.fromCircle(center: c, radius: s * .36));
      canvas.drawPath(glaze, glossy(T.foodGlaze, glaze.getBounds()));
      canvas.drawPath(ring, outline(T.foodDough));
      sprinkles(const [(-.5, -.2, .4), (.1, -.58, 1.4), (.52, -.1, -.5), (.3, .46, .9), (-.36, .44, 2.0)]);
      shine(p(-.4, -.46), s * .3, s * .12);

    case TamaFood.flan:
      // Flan en su plato: la capa de caramelo arriba, con goterones.
      final plate = Rect.fromCenter(center: p(0, .68), width: s * 1.36, height: s * .34);
      canvas.drawOval(plate, Paint()..color = T.shellTop);
      canvas.drawOval(plate, outline(T.shellBottom));
      final body = Path()
        ..moveTo(c.dx - s * .42, c.dy - s * .5)
        ..lineTo(c.dx + s * .42, c.dy - s * .5)
        ..lineTo(c.dx + s * .62, c.dy + s * .62)
        ..quadraticBezierTo(c.dx, c.dy + s * .78, c.dx - s * .62, c.dy + s * .62)
        ..close();
      canvas.drawPath(body, glossy(T.foodFlan, body.getBounds()));
      canvas.save();
      canvas.clipPath(body);
      final caramel = Path()
        ..moveTo(c.dx - s, c.dy - s)
        ..lineTo(c.dx + s, c.dy - s)
        ..lineTo(c.dx + s, c.dy - s * .22)
        ..quadraticBezierTo(c.dx + s * .4, c.dy - s * .3, c.dx + s * .3, c.dy - s * .08)
        ..quadraticBezierTo(c.dx + s * .2, c.dy - s * .32, c.dx - s * .1, c.dy - s * .22)
        ..quadraticBezierTo(c.dx - s * .25, c.dy + s * .02, c.dx - s * .38, c.dy - s * .24)
        ..lineTo(c.dx - s, c.dy - s * .24)
        ..close();
      canvas.drawPath(caramel, Paint()..color = T.foodCaramel);
      canvas.restore();
      canvas.drawPath(body, outline(T.foodFlan));
      shine(p(-.2, -.4), s * .26, s * .08);
  }
}

/// Una comida suelta, para botones y chips.
class TamaFoodPainter extends CustomPainter {
  const TamaFoodPainter(this.food, {this.fill = .32});

  final TamaFood food;

  /// Radio de la comida respecto al lado de la caja. Con .32 cabe holgada en
  /// un boton redondo del mismo tamaño.
  final double fill;

  @override
  void paint(Canvas canvas, Size size) =>
      paintFood(canvas, food, size.center(Offset.zero), size.shortestSide * fill);

  @override
  bool shouldRepaint(TamaFoodPainter old) => old.food != food || old.fill != fill;
}
