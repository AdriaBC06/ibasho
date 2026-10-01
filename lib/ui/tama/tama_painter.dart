// Ibasho — la criatura: un Tama dibujado en codigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../backend/prizes.dart';
import '../../backend/tama.dart';
import '../../theme/tokens.dart';
import 'tama_food.dart';
import 'tama_outfit.dart';

/// Postura de un instante. La calcula el animador y la consume el pintor.
///
/// Todo son numeros pequenos y adimensionales: el pintor decide cuanto se
/// traduce cada uno en pixeles segun el tamano del Tama.
@immutable
class TamaPose {
  const TamaPose({
    this.breathe = 0,
    this.squash = 0,
    this.hop = 0,
    this.tilt = 0,
    this.lean = 0,
    this.blink = 0,
    this.gaze = Offset.zero,
    this.joy = .4,
    this.happyEyes = 0,
    this.mouthOpen = 0,
    this.tongue = 0,
    this.blush = 0,
    this.sway = 0,
    this.armWave = 0,
    this.doze = 0,
    this.hearts = 0,
    this.heartPhase = 0,
    this.treat = -1,
    this.food = TamaFood.cookie,
    this.foodArt,
  });

  /// Pose de reposo. Es la que se ve, fija, con movimiento reducido.
  static const TamaPose rest = TamaPose();

  /// Respiracion, de -1 a 1.
  final double breathe;

  /// Positivo aplasta (mas ancho, mas bajo); negativo estira.
  final double squash;

  /// Altura del salto, en unidades del lienzo de 100.
  final double hop;

  /// Inclinacion en radianes, sobre el punto de apoyo.
  final double tilt;

  /// Desplazamiento lateral, en unidades.
  final double lean;

  /// Parpado: 0 abierto, 1 cerrado.
  final double blink;

  /// Hacia donde mira, cada eje de -1 a 1.
  final Offset gaze;

  /// Humor en la cara: -1 melancolico, 1 radiante.
  final double joy;

  /// Ojos cerrados de gusto (mimos), de 0 a 1.
  final double happyEyes;

  /// Boca abierta: graznar, bostezar, masticar.
  final double mouthOpen;

  /// Lengua fuera (el descarado).
  final double tongue;

  /// Rubor extra sobre el de las mejillas.
  final double blush;

  /// Retraso de orejas y antenas, en radianes.
  final double sway;

  /// Saludo de brazos o aleteo, de 0 a 1.
  final double armWave;

  /// Adormilado: parpados a media asta, de 0 a 1.
  final double doze;

  /// Corazones de alegria: intensidad y fase de su subida.
  final double hearts;
  final double heartPhase;

  /// Progreso de la chuche cayendo a la boca, de 0 a 1. Negativo: no hay.
  final double treat;

  /// Que chuche cae.
  final TamaFood food;

  /// Si no es `null`, cae esto en lugar de [food].
  final FoodArt? foodArt;
}

/// Pinta un Tama en una caja cuadrada.
///
/// Se dibuja sobre un lienzo logico de 100x100: la criatura apoya en y = 90 y
/// deja aire arriba para orejas, antenas y corazones.
class TamaPainter extends CustomPainter {
  TamaPainter({
    required this.look,
    TamaPose pose = TamaPose.rest,
    this.shadow = true,
    this.wear = TamaWear.none,
    ValueListenable<TamaPose>? live,
  }) : _pose = pose,
       _live = live,
       // Tambien se repinta cuando llega el dibujo de un premio que lleva.
       super(repaint: Listenable.merge([live, PrizeArt.instance]));

  final TamaLook look;
  final TamaPose _pose;

  /// Postura animada. Cuando esta, el pintor se repinta con cada cambio sin
  /// reconstruir ningun widget.
  final ValueListenable<TamaPose>? _live;

  TamaPose get pose => _live?.value ?? _pose;

  /// Sombra de contacto. Se quita cuando el Tama esta sobre la peana, que
  /// pinta la suya.
  final bool shadow;

  /// Lo que lleva puesto: se pinta como una pieza mas del cuerpo.
  final TamaWear wear;

  static const double floor = 90;
  static const double centreX = 50;
  static const double baseRadius = 27;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final unit = size.shortestSide / 100;
    canvas.save();
    canvas.translate(
      (size.width - 100 * unit) / 2,
      (size.height - 100 * unit) / 2,
    );
    canvas.scale(unit);
    _paintUnit(canvas);
    canvas.restore();
  }

  void _paintUnit(Canvas canvas) {
    final body = TamaBody.of(look);
    final color = look.bodyColor;

    if (shadow) _groundShadow(canvas, body);
    // Lo que esta en el suelo (la caca) no salta ni se inclina con el.
    paintOutfit(canvas, look, body, const {PrizeSlot.ground});

    // Todo lo que es la criatura se mueve junto: salto, inclinacion y
    // aplastamiento, con el punto de apoyo como pivote.
    final squash = pose.squash * .13 + pose.breathe * .022;
    canvas.save();
    canvas.translate(centreX + pose.lean, floor - pose.hop);
    canvas.rotate(pose.tilt);
    canvas.scale(1 + squash * .85, 1 - squash);
    canvas.translate(-centreX, -floor);

    final rect = body.bounds;
    final skin = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.34, -.52),
        radius: 1.08,
        colors: [
          Color.lerp(color, T.shellTop, .42)!,
          color,
          Color.lerp(color, T.dusk, .2)!,
        ],
        stops: const [0, .46, 1],
      ).createShader(rect);
    final rim = Color.lerp(color, T.dusk, .36)!;

    // Premios: primero lo que va detras del cuerpo (alas, mochila, la mitad
    // de detras del flotador).
    paintOutfit(canvas, look, body, const {
      PrizeSlot.back,
      PrizeSlot.waist,
      PrizeSlot.aura,
    });

    _crownBehind(canvas, body, skin, rim, color);
    _arms(canvas, body, skin, rim, color);
    _feetBehind(canvas, body, skin, rim, color);

    // Cuerpo.
    canvas.drawPath(body.path, skin);
    canvas.save();
    canvas.clipPath(body.path);
    _pattern(canvas, body, color);
    _volume(canvas, body);
    canvas.restore();
    canvas.drawPath(
      body.path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = rim.withValues(alpha: .5),
    );
    _specular(canvas, body);
    _crownFront(canvas, body, rim, color);

    _feetFront(canvas, body, color, rim);
    paintOutfit(canvas, look, body, const {PrizeSlot.feet});
    // Y la parte de delante de lo que va en dos (correas, flotador, hadas).
    paintOutfit(canvas, look, body, const {
      PrizeSlot.back,
      PrizeSlot.waist,
      PrizeSlot.aura,
    }, front: true);
    _face(canvas, body, skin, color);
    // Lo de la cara y el cuello, luego el gorro y al final lo que tiene al
    // lado. El gorrito del cumpleaños solo sale si no lleva gorro.
    paintOutfit(canvas, look, body, const {
      PrizeSlot.eyes,
      PrizeSlot.nose,
      PrizeSlot.neck,
    });
    if (look.outfit.hat == null) {
      _wear(canvas, body);
    } else {
      paintOutfit(canvas, look, body, const {PrizeSlot.head});
    }
    paintOutfit(canvas, look, body, const {PrizeSlot.left, PrizeSlot.right});

    canvas.restore();

    _hearts(canvas, body);
    _zzz(canvas, body);
  }

  // --- Suelo ---------------------------------------------------------------

  void _groundShadow(Canvas canvas, TamaBody body) {
    final lift = (pose.hop / 18).clamp(0.0, 1.0);
    final width = body.bounds.width * (.86 - lift * .3);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centreX + pose.lean, floor + 1.4),
        width: width,
        height: 5.2 * (1 - lift * .4),
      ),
      Paint()
        ..color = T.tamaGroundShadow.withValues(
          alpha: T.tamaGroundShadow.a * (1 - lift * .55),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );
  }

  // --- Volumen y brillo -----------------------------------------------------

  /// Sombra propia abajo y luz rebotada en el borde inferior: lo que hace que
  /// parezca plastico blando y no un circulo con degradado.
  void _volume(Canvas canvas, TamaBody body) {
    final rect = body.bounds;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.glintNone, T.glintNone, T.dusk.withValues(alpha: .10)],
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
    canvas.drawPath(
      body.path.shift(const Offset(0, -1.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1)
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [T.glintNone, T.glintNone, T.glintStrong],
          stops: const [0, .7, 1],
        ).createShader(rect),
    );
  }

  /// La firma de la casa, tambien en la criatura: un brillo especular en el
  /// tercio superior.
  void _specular(Canvas canvas, TamaBody body) {
    final r = body.bounds;
    final centre = Offset(r.left + r.width * .34, r.top + r.height * .2);
    canvas.save();
    canvas.clipPath(body.path);
    canvas.translate(centre.dx, centre.dy);
    canvas.rotate(-.42);
    final lens = Rect.fromCenter(
      center: Offset.zero,
      width: r.width * .36,
      height: r.height * .17,
    );
    canvas.drawOval(
      lens,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.glintStrong, T.glintFaint],
        ).createShader(lens),
    );
    canvas.restore();
    canvas.drawCircle(
      Offset(r.left + r.width * .6, r.top + r.height * .12),
      r.width * .028,
      Paint()..color = T.glintPanel,
    );
  }

  // --- Dibujo del cuerpo ----------------------------------------------------

  /// El color del dibujo cuando no tiene uno propio: el del cuerpo, aclarado
  /// u oscurecido segun [tone].
  static Color patternColor(Color body, double tone) {
    if (tone < .5) return Color.lerp(body, T.shellTop, .74 - tone * .9)!;
    return Color.lerp(body, T.dusk, .12 + (tone - .5) * .62)!;
  }

  void _pattern(Canvas canvas, TamaBody body, Color color) {
    final variant = look.part(TamaPart.pattern);
    if (variant == 0) return;
    final r = body.bounds;
    final paint = Paint()
      ..color =
          look.tint(TamaTint.pattern) ??
          patternColor(color, look.unit(TamaDial.patternTone));
    // Lo que va en la barriga, a la altura de la barriga.
    final belly = Offset(r.center.dx, r.top + r.height * .72);
    switch (variant) {
      case 1: // Barriga.
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(r.center.dx, r.top + r.height * .74),
            width: r.width * .66,
            height: r.height * .56,
          ),
          paint,
        );
      case 2: // Motas.
        for (final (dx, dy, s) in const [
          (-.62, -.18, .15),
          (.46, -.5, .11),
          (.7, .2, .14),
          (-.3, .52, .1),
          (-.12, -.62, .07),
        ]) {
          canvas.drawCircle(
            Offset(
              r.center.dx + dx * r.width / 2,
              r.center.dy + dy * r.height / 2,
            ),
            s * r.width,
            paint,
          );
        }
      case 3: // Rayas en el lomo.
        final stroke = Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r.height * .075;
        for (var i = 0; i < 3; i++) {
          final y = r.top + r.height * (.1 + i * .15);
          canvas.drawPath(
            Path()
              ..moveTo(r.left - 2, y + r.height * .1)
              ..quadraticBezierTo(
                r.center.dx,
                y - r.height * .06,
                r.right + 2,
                y + r.height * .1,
              ),
            stroke,
          );
        }
      case 4: // Punta mojada en otro color.
        final y = r.top + r.height * .3;
        final path = Path()..moveTo(r.left - 2, r.top - 2);
        path.lineTo(r.right + 2, r.top - 2);
        path.lineTo(r.right + 2, y);
        const scallops = 4;
        final step = (r.width + 4) / scallops;
        for (var i = 0; i < scallops; i++) {
          final x0 = r.right + 2 - i * step;
          path.quadraticBezierTo(
            x0 - step / 2,
            y + r.height * .09,
            x0 - step,
            y,
          );
        }
        path.close();
        canvas.drawPath(path, paint);
      case 5: // Corazon en la barriga.
        _heart(canvas, belly + Offset(0, r.height * .1), r.width * .46, paint);
      case 6: // Estrella en la barriga.
        _star5(canvas, belly, r.width * .22, paint);
      case 7: // Lunares por todo.
        final step = r.width * .2;
        var row = 0;
        for (var y = r.top + step * .4; y < r.bottom + step; y += step * .86) {
          final shift = row.isOdd ? step / 2 : 0.0;
          for (var x = r.left - step + shift; x < r.right + step; x += step) {
            canvas.drawCircle(Offset(x, y), r.width * .045, paint);
          }
          row++;
        }
      case 8: // Medio y medio.
        canvas.drawRect(
          Rect.fromLTRB(r.left - 2, r.top - 2, r.center.dx, r.bottom + 2),
          paint,
        );
      case 9: // Antifaz de mapache.
        final f = TamaFace.of(look, body);
        final h = f.eyeR * 3.1;
        final band = Path()
          ..moveTo(r.left - 2, f.eyeY - h * .3)
          ..quadraticBezierTo(
            f.centre.dx,
            f.eyeY - h * .62,
            r.right + 2,
            f.eyeY - h * .3,
          )
          ..lineTo(r.right + 2, f.eyeY + h * .38)
          ..quadraticBezierTo(
            f.centre.dx + f.eyeDx * .5,
            f.eyeY + h * .55,
            f.centre.dx,
            f.eyeY + h * .12,
          )
          ..quadraticBezierTo(
            f.centre.dx - f.eyeDx * .5,
            f.eyeY + h * .55,
            r.left - 2,
            f.eyeY + h * .38,
          )
          ..close();
        canvas.drawPath(band, paint);
      case 10: // Zigzag por la cintura.
        final top = r.top + r.height * .68;
        final h = r.height * .12;
        const teeth = 6;
        final step = (r.width + 4) / teeth;
        final zig = Path()..moveTo(r.left - 2, top);
        for (var i = 0; i < teeth; i++) {
          zig.lineTo(r.left - 2 + step * (i + .5), top - h * .45);
          zig.lineTo(r.left - 2 + step * (i + 1), top);
        }
        zig.lineTo(r.right + 2, top + h);
        for (var i = teeth; i > 0; i--) {
          zig.lineTo(r.left - 2 + step * (i - .5), top + h * 1.45);
          zig.lineTo(r.left - 2 + step * (i - 1), top + h);
        }
        zig.close();
        canvas.drawPath(zig, paint);
      case 11: // Rayas de sandia, de arriba abajo.
        final stroke = Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r.width * .07;
        for (final k in const [-.66, -.33, 0.0, .33, .66]) {
          final x = r.center.dx + k * r.width / 2;
          canvas.drawPath(
            Path()
              ..moveTo(r.center.dx + k * r.width * .2, r.top - 2)
              ..quadraticBezierTo(
                x + k * r.width * .22,
                r.center.dy,
                r.center.dx + k * r.width * .34,
                r.bottom + 2,
              ),
            stroke,
          );
        }
    }
  }

  /// Estrella de cinco puntas, algo redondeada.
  void _star5(Canvas canvas, Offset c, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? radius : radius * .48;
      final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = radius * .22,
    );
  }

  void _crownBehind(
    Canvas canvas,
    TamaBody body,
    Paint skin,
    Color rim,
    Color color,
  ) {
    final variant = look.part(TamaPart.crown);
    if (variant == 0) return;
    final r = body.bounds;
    final k = .72 + .62 * look.unit(TamaDial.crownSize);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = rim.withValues(alpha: .5);

    for (final side in const [-1.0, 1.0]) {
      switch (variant) {
        case 1: // Orejas redondas.
          final baseY = r.top + r.height * .16;
          final baseX = r.center.dx + side * body.halfWidthAt(baseY) * .62;
          canvas.save();
          canvas.translate(baseX, baseY);
          canvas.rotate(side * (.34 + pose.sway * .5));
          final w = r.width * .19 * k;
          final h = r.height * .34 * k;
          final ear = Path()
            ..moveTo(-w, h * .3)
            ..quadraticBezierTo(-w * 1.05, -h * .55, 0, -h)
            ..quadraticBezierTo(w * 1.05, -h * .55, w, h * .3)
            ..close();
          canvas.drawPath(ear, skin);
          canvas.drawPath(ear, outline);
          final inner = Path()
            ..moveTo(-w * .5, h * .05)
            ..quadraticBezierTo(-w * .55, -h * .45, 0, -h * .72)
            ..quadraticBezierTo(w * .55, -h * .45, w * .5, h * .05)
            ..close();
          canvas.drawPath(
            inner,
            Paint()..color = Color.lerp(color, T.tamaBlush, .62)!,
          );
          canvas.restore();
        case 2: // Orejas largas de conejo.
          final baseY = r.top + r.height * .14;
          final baseX = r.center.dx + side * r.width * .2;
          canvas.save();
          canvas.translate(baseX, baseY);
          canvas.rotate(side * (.22 + pose.sway * 1.1));
          final w = r.width * .15;
          final h = r.height * .62 * k;
          final ear = Rect.fromCenter(
            center: Offset(0, -h * .42),
            width: w,
            height: h,
          );
          canvas.drawOval(ear, skin);
          canvas.drawOval(ear, outline);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(0, -h * .38),
              width: w * .48,
              height: h * .7,
            ),
            Paint()..color = Color.lerp(color, T.tamaBlush, .6)!,
          );
          canvas.restore();
        case 3: // Antenas.
          final base = Offset(
            r.center.dx + side * r.width * .16,
            r.top + r.height * .08,
          );
          final tip = Offset(
            r.center.dx + side * r.width * (.3 + pose.sway * .25),
            r.top - r.height * .3 * k + pose.sway.abs() * 2,
          );
          canvas.drawPath(
            Path()
              ..moveTo(base.dx, base.dy)
              ..quadraticBezierTo(
                base.dx + side * 1.5,
                tip.dy + (base.dy - tip.dy) * .35,
                tip.dx,
                tip.dy,
              ),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 1.8
              ..color = rim,
          );
          final ball = Rect.fromCircle(center: tip, radius: 3.6 * k);
          canvas.drawOval(
            ball,
            Paint()
              ..shader = RadialGradient(
                center: const Alignment(-.4, -.5),
                colors: [
                  Color.lerp(color, T.shellTop, .6)!,
                  color,
                  Color.lerp(color, T.dusk, .22)!,
                ],
                stops: const [0, .55, 1],
              ).createShader(ball),
          );
          canvas.drawOval(ball, outline);
          canvas.drawCircle(
            tip + Offset(-1.1 * k, -1.2 * k),
            .9 * k,
            Paint()..color = T.glintStrong,
          );
        case 4: // Cuernecillos.
          final baseY = r.top + r.height * .1;
          final baseX = r.center.dx + side * body.halfWidthAt(baseY) * .5;
          canvas.save();
          canvas.translate(baseX, baseY);
          canvas.rotate(side * .3);
          final w = r.width * .08 * k;
          final h = r.height * .2 * k;
          final horn = Path()
            ..moveTo(-w, h * .4)
            ..quadraticBezierTo(-w * .9, -h * .6, side * w * .25, -h)
            ..quadraticBezierTo(w * 1.05, -h * .5, w, h * .4)
            ..close();
          final hornColor = Color.lerp(color, T.shellTop, .62)!;
          canvas.drawPath(horn, Paint()..color = hornColor);
          canvas.drawPath(
            horn,
            outline..color = Color.lerp(hornColor, T.dusk, .3)!,
          );
          canvas.restore();
        case 5: // Mechon rizado, solo uno, en el centro.
          if (side > 0) break;
          final base = Offset(r.center.dx, r.top + r.height * .06);
          canvas.save();
          canvas.translate(base.dx, base.dy);
          canvas.rotate(pose.sway * .9);
          final hair = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.6
            ..color = Color.lerp(color, T.dusk, .18)!;
          final s = k;
          canvas.drawPath(
            Path()
              ..moveTo(0, 2)
              ..cubicTo(-1 * s, -6 * s, 5 * s, -12 * s, 7 * s, -9 * s)
              ..cubicTo(9 * s, -6 * s, 4 * s, -4 * s, 3 * s, -7 * s),
            hair,
          );
          canvas.drawPath(
            Path()
              ..moveTo(-1, 2)
              ..quadraticBezierTo(-4 * s, -3 * s, -5.5 * s, -6.5 * s),
            hair..strokeWidth = 2.1,
          );
          canvas.restore();
        case 6: // Orejas de gato, en punta.
          final baseY = r.top + r.height * .15;
          final baseX = r.center.dx + side * body.halfWidthAt(baseY) * .58;
          canvas.save();
          canvas.translate(baseX, baseY);
          canvas.rotate(side * (.12 + pose.sway * .5));
          final w = r.width * .15 * k;
          final h = r.height * .4 * k;
          // Triangulo recto, con la punta hacia fuera: el de las orejitas es
          // redondo y ladeado.
          Path tri(double s) => Path()
            ..moveTo(-w * s, h * .3)
            ..lineTo(side * w * .35 * s, -h * s)
            ..lineTo(w * s, h * .3)
            ..close();
          canvas.drawPath(tri(1), skin);
          canvas.drawPath(tri(1), outline);
          canvas.drawPath(
            tri(.56),
            Paint()..color = Color.lerp(color, T.tamaBlush, .62)!,
          );
          canvas.restore();
        case 7: // Brote: dos hojitas en un tallo.
          if (side > 0) break;
          final base = Offset(r.center.dx, r.top + 2);
          canvas.save();
          canvas.translate(base.dx, base.dy);
          canvas.rotate(pose.sway * .8);
          final stemTop = Offset(0, -9 * k);
          canvas.drawPath(
            Path()
              ..moveTo(0, 2)
              ..quadraticBezierTo(1.2 * k, -4 * k, stemTop.dx, stemTop.dy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 1.7
              ..color = Color.lerp(T.tamaSprout, T.dusk, .3)!,
          );
          for (final dir in const [-1.0, 1.0]) {
            final leaf = Path()
              ..moveTo(stemTop.dx, stemTop.dy)
              ..quadraticBezierTo(
                dir * 5 * k,
                stemTop.dy - 6.5 * k,
                dir * 10 * k,
                stemTop.dy - 2 * k,
              )
              ..quadraticBezierTo(
                dir * 5 * k,
                stemTop.dy + 2.6 * k,
                stemTop.dx,
                stemTop.dy,
              )
              ..close();
            final leafRect = leaf.getBounds();
            canvas.drawPath(
              leaf,
              Paint()
                ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(T.tamaSprout, T.shellTop, .3)!,
                    T.tamaSprout,
                  ],
                ).createShader(leafRect),
            );
            canvas.drawPath(
              leaf,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = .9
                ..color = Color.lerp(T.tamaSprout, T.dusk, .35)!,
            );
          }
          canvas.restore();
        case 8: // Orejitas de oso, redondas y pequeñas.
          final baseY = r.top + r.height * .13;
          final c = Offset(
            r.center.dx + side * body.halfWidthAt(baseY) * .7,
            baseY - r.height * .02,
          );
          final rad = r.width * .12 * k;
          canvas.drawCircle(c, rad, skin);
          canvas.drawCircle(c, rad, outline);
          canvas.drawCircle(
            c + Offset(0, rad * .12),
            rad * .55,
            Paint()..color = Color.lerp(color, T.tamaBlush, .55)!,
          );
        case 9: // Cresta de dinosaurio, por el lomo.
          if (side > 0) break;
          final spike = Paint()..color = Color.lerp(color, T.dusk, .16)!;
          for (final (dx, s) in const [(-.24, .7), (0.0, 1.0), (.24, .7)]) {
            final x = r.center.dx + dx * r.width;
            final y = r.top + r.height * (.03 + 1.6 * dx * dx);
            final w = r.width * .1;
            final h = r.height * .2 * k * s;
            final tooth = Path()
              ..moveTo(x - w, y + 3)
              ..quadraticBezierTo(x - w * .5, y - h * .5, x, y - h)
              ..quadraticBezierTo(x + w * .5, y - h * .5, x + w, y + 3)
              ..close();
            canvas.drawPath(tooth, spike);
            canvas.drawPath(tooth, outline);
          }
        case 11: // Cuerno de unicornio.
          if (side > 0) break;
          final base = Offset(r.center.dx, r.top + r.height * .06);
          final h = r.height * .36 * k;
          final w = r.width * .075 * k;
          final horn = Path()
            ..moveTo(base.dx - w, base.dy + 2)
            ..lineTo(base.dx - w * .12, base.dy - h)
            ..quadraticBezierTo(
              base.dx,
              base.dy - h - 1,
              base.dx + w * .12,
              base.dy - h,
            )
            ..lineTo(base.dx + w, base.dy + 2)
            ..close();
          final hornRect = horn.getBounds();
          canvas.drawPath(
            horn,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  Color.lerp(T.tamaHorn, T.shellTop, .5)!,
                  T.tamaHorn,
                  Color.lerp(T.tamaHorn, T.dusk, .15)!,
                ],
                stops: const [0, .45, 1],
              ).createShader(hornRect),
          );
          canvas.save();
          canvas.clipPath(horn);
          final spiral = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Color.lerp(T.tamaHorn, T.dusk, .3)!;
          for (var i = 1; i < 4; i++) {
            final y = base.dy - h * i / 4;
            canvas.drawLine(
              Offset(base.dx - w, y + w * .6),
              Offset(base.dx + w, y - w * .2),
              spiral,
            );
          }
          canvas.restore();
          canvas.drawPath(
            horn,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..strokeJoin = StrokeJoin.round
              ..color = Color.lerp(T.tamaHorn, T.dusk, .38)!,
          );
        case 12: // Penacho de codorniz: un tallo curvo con su gota.
          if (side > 0) break;
          final base = Offset(r.center.dx - r.width * .04, r.top + 2);
          canvas.save();
          canvas.translate(base.dx, base.dy);
          canvas.rotate(pose.sway * 1.2);
          final tip = Offset(5.5 * k, -11 * k);
          canvas.drawPath(
            Path()
              ..moveTo(0, 2)
              ..cubicTo(-1.5 * k, -6 * k, 1 * k, -10 * k, tip.dx, tip.dy),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 1.6
              ..color = rim,
          );
          canvas.save();
          canvas.translate(tip.dx, tip.dy);
          canvas.rotate(.9);
          final drop = Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(3.4 * k, 1.2 * k, 2.6 * k, 4 * k)
            ..quadraticBezierTo(0, 6.4 * k, -2.6 * k, 4 * k)
            ..quadraticBezierTo(-3.4 * k, 1.2 * k, 0, 0)
            ..close();
          canvas.drawPath(
            drop,
            Paint()..color = Color.lerp(color, T.dusk, .2)!,
          );
          canvas.drawPath(drop, outline);
          canvas.restore();
          canvas.restore();
        case 13: // Orejas de raton, grandes y redondas.
          final baseY = r.top + r.height * .2;
          final c = Offset(
            r.center.dx + side * (body.halfWidthAt(baseY) * .8 + r.width * .02),
            r.top + r.height * .02,
          );
          final rad = r.width * .2 * k;
          canvas.drawCircle(c, rad, skin);
          canvas.drawCircle(c, rad, outline);
          canvas.drawCircle(
            c + Offset(-side * rad * .06, rad * .06),
            rad * .66,
            Paint()..color = Color.lerp(color, T.tamaBlush, .55)!,
          );
      }
    }
  }

  /// Lo de la coronilla que cae por delante del cuerpo: las orejas caidas de
  /// perrito, a los lados de la cabeza.
  void _crownFront(Canvas canvas, TamaBody body, Color rim, Color color) {
    if (look.part(TamaPart.crown) != 10) return;
    final r = body.bounds;
    final k = .72 + .62 * look.unit(TamaDial.crownSize);
    final ear = Paint()..color = Color.lerp(color, T.dusk, .14)!;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = rim.withValues(alpha: .55);
    for (final side in const [-1.0, 1.0]) {
      final y = r.top + r.height * .12;
      final x = r.center.dx + side * (body.halfWidthAt(y) + 1);
      canvas.save();
      canvas.translate(x, y);
      // Cuelgan hacia fuera, por el costado: nunca encima de los ojos.
      canvas.rotate(-side * (.5 + pose.sway * .6));
      final w = r.width * .15 * k;
      final h = r.height * .36 * k;
      final flap = Path()
        ..moveTo(-w * .4, 0)
        ..quadraticBezierTo(-w * .7, h * .7, 0, h)
        ..quadraticBezierTo(w * .7, h * .7, w * .5, 0)
        ..quadraticBezierTo(0, -h * .1, -w * .4, 0)
        ..close();
      canvas.drawPath(flap, ear);
      canvas.drawPath(flap, outline);
      canvas.restore();
    }
  }

  // --- Lo que lleva puesto --------------------------------------------------

  /// Gorrito de fiesta: un cono a rayas ladeado sobre la coronilla, con su
  /// borla. Se apoya en el contorno real del cuerpo (la altura de la cima y el
  /// ancho a esa altura), asi que cae bien en un mochi chato y en una gota
  /// alta, y baila con el balanceo de las orejas.
  void _wear(Canvas canvas, TamaBody body) {
    if (wear != TamaWear.partyHat) return;
    final r = body.bounds;
    // Un poco hacia un lado: centrado del todo parece un cucurucho clavado.
    final baseY = r.top + r.height * .08;
    final half = math.max(body.halfWidthAt(baseY) * .78, r.width * .17);
    final baseX = r.center.dx + r.width * .06;
    // Alto, pero sin salirse del lienzo por arriba en los cuerpos altos.
    final height = math.max(14.0, math.min(r.height * .5, baseY - 6));

    canvas.save();
    canvas.translate(baseX, baseY);
    canvas.rotate(.2 + pose.sway * .6 + pose.tilt * .3);

    // El ala del gorro sigue la curva de la cabeza: base algo combada.
    final cone = Path()
      ..moveTo(-half, 0)
      ..quadraticBezierTo(0, half * .32, half, 0)
      ..lineTo(half * .08, -height)
      ..quadraticBezierTo(0, -height - 1.2, -half * .08, -height)
      ..close();
    final shade = Rect.fromLTRB(-half, -height, half, half * .3);
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Color.lerp(T.partyHat, T.shellTop, .28)!,
            T.partyHat,
            Color.lerp(T.partyHat, T.dusk, .16)!,
          ],
          stops: const [0, .45, 1],
        ).createShader(shade),
    );

    // Rayas diagonales, recortadas al cono.
    canvas.save();
    canvas.clipPath(cone);
    final stripe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = half * .36
      ..color = T.partyStripe;
    for (var i = 0; i < 4; i++) {
      final y = -height * (.12 + i * .27);
      canvas.drawLine(
        Offset(-half * 1.4, y + half * .5),
        Offset(half * 1.4, y - half * .5),
        stripe,
      );
    }
    // Brillo de la casa en el lado de la luz.
    canvas.drawPath(
      Path()
        ..moveTo(-half * .55, -half * .05)
        ..lineTo(-half * .02, -height * .82),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.3
        ..color = T.glintStrong,
    );
    canvas.restore();

    canvas.drawPath(
      cone,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(T.partyHat, T.dusk, .38)!.withValues(alpha: .7),
    );

    // Borla: tres bolitas que se sacuden con los saltos.
    final tip = Offset(pose.sway * 3, -height - 1.6 - pose.hop * .05);
    final puff = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.35, -.45),
        colors: [
          T.shellTop,
          T.partyPompom,
          Color.lerp(T.partyPompom, T.partyStripe, .55)!,
        ],
        stops: const [0, .5, 1],
      ).createShader(Rect.fromCircle(center: tip, radius: 4.4));
    for (final (dx, dy, rad) in const [
      (-2.0, .6, 2.4),
      (2.0, .6, 2.4),
      (0.0, -1.4, 2.7),
    ]) {
      canvas.drawCircle(tip + Offset(dx, dy), rad, puff);
    }
    canvas.restore();
  }

  void _arms(Canvas canvas, TamaBody body, Paint skin, Color rim, Color color) {
    final r = body.bounds;
    final variant = look.part(TamaPart.arms);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = rim.withValues(alpha: .5);
    if (variant == 3) return; // Sin brazos.
    for (final side in const [-1.0, 1.0]) {
      if (variant == 2) {
        // Manitas: un brazo corto con su mano redonda y un pulgar.
        final y = r.top + r.height * .56;
        final x = r.center.dx + side * (body.halfWidthAt(y) - 1.5);
        canvas.save();
        canvas.translate(x, y);
        // Hacia fuera y abajo; al saludar sube.
        canvas.rotate(-side * (.62 + pose.armWave * 1.3));
        final arm = Rect.fromCenter(
          center: Offset(0, r.height * .1),
          width: r.width * .09,
          height: r.height * .22,
        );
        canvas.drawOval(arm, skin);
        canvas.drawOval(arm, outline);
        final hand = Offset(0, r.height * .22);
        final hr = r.width * .09;
        final handColor = Paint()..color = Color.lerp(color, T.shellTop, .3)!;
        canvas.drawCircle(
          hand + Offset(-side * hr * .8, -hr * .3),
          hr * .45,
          handColor,
        );
        canvas.drawCircle(
          hand + Offset(-side * hr * .8, -hr * .3),
          hr * .45,
          outline,
        );
        canvas.drawCircle(hand, hr, handColor);
        canvas.drawCircle(hand, hr, outline);
        canvas.restore();
      } else if (variant == 0) {
        // Bracitos.
        final y = r.top + r.height * .64;
        final x = r.center.dx + side * (body.halfWidthAt(y) + .6);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(side * (.55 + pose.armWave * 1.1));
        final arm = Rect.fromCenter(
          center: Offset(side * 0, 3.4),
          width: r.width * .15,
          height: r.height * .26,
        );
        canvas.drawOval(arm, skin);
        canvas.drawOval(arm, outline);
        canvas.restore();
      } else if (variant > 3) {
        _armMore(canvas, body, skin, outline, color, side, variant);
      } else {
        // Alitas.
        final y = r.top + r.height * .46;
        final x = r.center.dx + side * (body.halfWidthAt(y) - 2.5);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(side * (-.25 - pose.armWave * .55));
        final w = r.width * .24;
        final h = r.height * .24;
        final wing = Path()
          ..moveTo(0, h * .3)
          ..cubicTo(
            side * w * .5,
            h * .45,
            side * w * 1.1,
            h * .05,
            side * w,
            -h * .45,
          )
          ..cubicTo(
            side * w * .75,
            -h * .25,
            side * w * .45,
            -h * .5,
            side * w * .3,
            -h * .2,
          )
          ..cubicTo(side * w * .15, -h * .35, 0, -h * .1, 0, h * .3)
          ..close();
        canvas.drawPath(
          wing,
          Paint()..color = Color.lerp(color, T.shellTop, .5)!,
        );
        canvas.drawPath(wing, outline);
        canvas.restore();
      }
    }
  }

  /// Los brazos de la 0.8.0: aletas, garritas, alas de murcielago, hojitas
  /// y manos flotantes.
  void _armMore(
    Canvas canvas,
    TamaBody body,
    Paint skin,
    Paint outline,
    Color color,
    double side,
    int variant,
  ) {
    final r = body.bounds;
    switch (variant) {
      case 4: // Aletas de pingüino.
        final y = r.top + r.height * .5;
        final x = r.center.dx + side * (body.halfWidthAt(y) - 1.2);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-side * (.45 + pose.armWave * .9));
        final w = r.width * .13;
        final h = r.height * .42;
        final fin = Path()
          ..moveTo(-w * .5, 0)
          ..quadraticBezierTo(-w * .7, h * .6, side * w * .1, h)
          ..quadraticBezierTo(w * .8, h * .55, w * .5, 0)
          ..close();
        canvas.drawPath(fin, Paint()..color = Color.lerp(color, T.dusk, .1)!);
        canvas.drawPath(fin, outline);
        canvas.restore();
      case 5: // Garritas: bracito con tres uñas.
        final y = r.top + r.height * .62;
        final x = r.center.dx + side * (body.halfWidthAt(y) + .4);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(side * (.5 + pose.armWave * 1.1));
        final arm = Rect.fromCenter(
          center: const Offset(0, 3.4),
          width: r.width * .14,
          height: r.height * .26,
        );
        canvas.drawOval(arm, skin);
        canvas.drawOval(arm, outline);
        // Las uñas, por delante del bracito, en abanico.
        final claw = Paint()..color = Color.lerp(T.shellTop, color, .1)!;
        final clawEdge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .7
          ..strokeJoin = StrokeJoin.round
          ..color = outline.color;
        for (final a in const [-.5, 0.0, .5]) {
          final base = Offset(math.sin(a) * arm.width * .4, arm.bottom - 1.6);
          final tip = base + Offset(math.sin(a) * 2.6, 3.2);
          final nail = Path()
            ..moveTo(base.dx - 1.3, base.dy)
            ..quadraticBezierTo(tip.dx - .6, tip.dy - 1, tip.dx, tip.dy)
            ..quadraticBezierTo(
              tip.dx + .4,
              tip.dy - 1.4,
              base.dx + 1.3,
              base.dy,
            )
            ..close();
          canvas.drawPath(nail, claw);
          canvas.drawPath(nail, clawEdge);
        }
        canvas.restore();
      case 6: // Alas de murcielago, con el borde en ondas.
        final y = r.top + r.height * .44;
        final x = r.center.dx + side * (body.halfWidthAt(y) - 2.5);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(side * (-.18 - pose.armWave * .6));
        final w = r.width * .3;
        final h = r.height * .3;
        final wing = Path()
          ..moveTo(0, h * .25)
          ..lineTo(side * w * .2, -h * .2)
          ..quadraticBezierTo(side * w * .6, -h * .55, side * w, -h * .4)
          ..quadraticBezierTo(side * w * .9, -h * .05, side * w * .95, h * .3)
          ..quadraticBezierTo(side * w * .78, h * .12, side * w * .62, h * .34)
          ..quadraticBezierTo(side * w * .46, h * .14, side * w * .3, h * .38)
          ..quadraticBezierTo(side * w * .16, h * .2, 0, h * .25)
          ..close();
        canvas.drawPath(wing, Paint()..color = Color.lerp(color, T.dusk, .3)!);
        canvas.drawPath(wing, outline);
        final bone = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = .8
          ..color = Color.lerp(color, T.dusk, .45)!;
        for (final t in const [.62, .3]) {
          canvas.drawLine(
            Offset(side * w * .2, -h * .2),
            Offset(side * w * t, h * .3),
            bone,
          );
        }
        canvas.restore();
      case 7: // Hojitas.
        final y = r.top + r.height * .58;
        final x = r.center.dx + side * (body.halfWidthAt(y) - 1);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-side * (1.1 + pose.armWave * 1.1));
        final w = r.width * .12;
        final h = r.height * .36;
        final leaf = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-w, h * .45, 0, h)
          ..quadraticBezierTo(w, h * .45, 0, 0)
          ..close();
        canvas.drawPath(
          leaf,
          Paint()..color = Color.lerp(color, T.shellTop, .2)!,
        );
        canvas.drawPath(leaf, outline);
        canvas.drawLine(
          Offset(0, h * .08),
          Offset(0, h * .82),
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = .8
            ..color = outline.color,
        );
        canvas.restore();
      case 8: // Manos flotantes, sin brazo, que suben al saludar.
        final y = r.top + r.height * (.64 - pose.armWave * .22);
        final x =
            r.center.dx +
            side * (body.halfWidthAt(r.top + r.height * .64) + r.width * .1);
        final rad = r.width * .085;
        final hand = Paint()..color = Color.lerp(color, T.shellTop, .3)!;
        final c = Offset(x, y);
        canvas.drawCircle(c, rad, hand);
        canvas.drawCircle(c, rad, outline);
        canvas.drawCircle(
          c + Offset(-side * rad * .1, -rad * .9),
          rad * .42,
          hand,
        );
        canvas.drawCircle(
          c + Offset(-side * rad * .1, -rad * .9),
          rad * .42,
          outline,
        );
        canvas.drawCircle(
          c + Offset(-rad * .3, -rad * .3),
          rad * .22,
          Paint()..color = T.glintSoft,
        );
    }
  }

  void _feetBehind(
    Canvas canvas,
    TamaBody body,
    Paint skin,
    Color rim,
    Color color,
  ) {
    final variant = look.part(TamaPart.feet);
    if (variant == 2 || variant == 7) {
      _legs(canvas, body, rim, color, long: variant == 7);
      return;
    }
    if (variant != 0 || hidesFeet(look)) return;
    // Patitas redondas asomando por debajo.
    final r = body.bounds;
    for (final side in const [-1.0, 1.0]) {
      final foot = Rect.fromCenter(
        center: Offset(r.center.dx + side * r.width * .22, floor - 1.4),
        width: r.width * .24,
        height: 7.4,
      );
      canvas.drawOval(foot, Paint()..color = Color.lerp(color, T.dusk, .1)!);
      canvas.drawOval(
        foot,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = rim.withValues(alpha: .5),
      );
    }
  }

  /// Piernecitas: dos patas cortas con zapatito redondo. El cuerpo va algo mas
  /// alto para que se vean (ver [TamaBody.legLift]).
  /// Con [long], las piernas largas: mas finas y con un pie redondo.
  void _legs(
    Canvas canvas,
    TamaBody body,
    Color rim,
    Color color, {
    bool long = false,
  }) {
    final r = body.bounds;
    final half = r.width * (long ? .04 : .055);
    final legColor = Color.lerp(color, T.dusk, .12)!;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = rim.withValues(alpha: .55);
    for (final side in const [-1.0, 1.0]) {
      final x = r.center.dx + side * r.width * (long ? .14 : .17);
      final leg = RRect.fromRectAndRadius(
        Rect.fromLTRB(x - half, r.bottom - 4, x + half, floor - 2.5),
        Radius.circular(half),
      );
      canvas.drawRRect(leg, Paint()..color = legColor);
      canvas.drawRRect(leg, outline);
      final shoe = Rect.fromCenter(
        center: Offset(x + side * r.width * .03, floor - 2.2),
        width: r.width * (long ? .17 : .21),
        height: long ? 5.6 : 5.2,
      );
      canvas.drawOval(shoe, Paint()..color = Color.lerp(color, T.dusk, .28)!);
      canvas.drawOval(shoe, outline);
      canvas.drawOval(
        Rect.fromCenter(
          center: shoe.center.translate(-shoe.width * .15, -1.2),
          width: shoe.width * .35,
          height: 1.4,
        ),
        Paint()..color = T.glintSoft,
      );
    }
  }

  void _feetFront(Canvas canvas, TamaBody body, Color color, Color rim) {
    if (hidesFeet(look)) return;
    final variant = look.part(TamaPart.feet);
    if (variant > 3 && variant != 7) {
      _feetMore(canvas, body, color, rim, variant);
      return;
    }
    if (variant != 1) return;
    // Zarpitas delante, con sus deditos.
    final r = body.bounds;
    final pawColor = Color.lerp(color, T.shellTop, .22)!;
    for (final side in const [-1.0, 1.0]) {
      final c = Offset(r.center.dx + side * r.width * .2, floor - 3);
      final paw = Rect.fromCenter(center: c, width: r.width * .25, height: 8.6);
      canvas.drawOval(paw, Paint()..color = pawColor);
      canvas.drawOval(
        paw,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = rim.withValues(alpha: .6),
      );
      final toe = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = .9
        ..color = rim.withValues(alpha: .55);
      for (final dx in const [-.18, .18]) {
        canvas.drawLine(
          Offset(c.dx + dx * paw.width, c.dy + 1.2),
          Offset(c.dx + dx * paw.width, c.dy + 3.4),
          toe,
        );
      }
    }
  }

  /// Los pies de la 0.8.0, delante del cuerpo: de pato, botitas,
  /// almohadillas y de pajaro.
  void _feetMore(
    Canvas canvas,
    TamaBody body,
    Color color,
    Color rim,
    int variant,
  ) {
    final r = body.bounds;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeJoin = StrokeJoin.round
      ..color = rim.withValues(alpha: .6);
    for (final side in const [-1.0, 1.0]) {
      switch (variant) {
        case 4: // De pato: palmeadas, con tres deditos.
          final c = Offset(r.center.dx + side * r.width * .21, floor - 2.4);
          final w = r.width * .15;
          final foot = Path()
            ..moveTo(c.dx - w * .5, c.dy - 3.4)
            ..quadraticBezierTo(c.dx - w * 1.15, c.dy, c.dx - w, c.dy + 2.4)
            ..quadraticBezierTo(
              c.dx - w * .66,
              c.dy + 1.2,
              c.dx - w * .34,
              c.dy + 2.6,
            )
            ..quadraticBezierTo(c.dx, c.dy + 1.4, c.dx + w * .34, c.dy + 2.6)
            ..quadraticBezierTo(
              c.dx + w * .66,
              c.dy + 1.2,
              c.dx + w,
              c.dy + 2.4,
            )
            ..quadraticBezierTo(
              c.dx + w * 1.15,
              c.dy,
              c.dx + w * .5,
              c.dy - 3.4,
            )
            ..close();
          canvas.drawPath(foot, Paint()..color = T.tamaBeak);
          canvas.drawPath(
            foot,
            outline..color = Color.lerp(T.tamaBeak, T.dusk, .4)!,
          );
        case 5: // Botitas con su vuelta.
          final c = Offset(r.center.dx + side * r.width * .2, floor - 3.6);
          final boot = RRect.fromRectAndCorners(
            Rect.fromCenter(center: c, width: r.width * .24, height: 8),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
            bottomLeft: const Radius.circular(4),
            bottomRight: const Radius.circular(4),
          );
          final bootColor = Color.lerp(color, T.dusk, .3)!;
          canvas.drawRRect(boot, Paint()..color = bootColor);
          final cuff = RRect.fromRectAndRadius(
            Rect.fromLTWH(boot.left - .6, boot.top - .6, boot.width + 1.2, 3),
            const Radius.circular(1.5),
          );
          canvas.drawRRect(
            cuff,
            Paint()..color = Color.lerp(color, T.shellTop, .55)!,
          );
          canvas.drawRRect(
            boot,
            outline..color = Color.lerp(bootColor, T.dusk, .3)!,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: c + Offset(-r.width * .05, 1),
              width: 2.6,
              height: 1.5,
            ),
            Paint()..color = T.glintSoft,
          );
        case 6: // Patitas con almohadillas rosas.
          final c = Offset(r.center.dx + side * r.width * .2, floor - 3);
          final paw = Rect.fromCenter(
            center: c,
            width: r.width * .26,
            height: 8.8,
          );
          canvas.drawOval(
            paw,
            Paint()..color = Color.lerp(color, T.shellTop, .25)!,
          );
          canvas.drawOval(paw, outline..color = rim.withValues(alpha: .6));
          final pad = Paint()..color = T.tamaBlush;
          canvas.drawOval(
            Rect.fromCenter(
              center: c + Offset(0, 1.4),
              width: paw.width * .42,
              height: 3.4,
            ),
            pad,
          );
          for (final dx in const [-.28, 0.0, .28]) {
            canvas.drawCircle(
              c + Offset(dx * paw.width, -1.8 - (dx == 0 ? .5 : 0)),
              1.05,
              pad,
            );
          }
        case 8: // De pajaro: tres deditos finos.
          final c = Offset(r.center.dx + side * r.width * .17, floor - 1.6);
          final toe = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1.6
            ..color = Color.lerp(T.tamaBeak, T.dusk, .12)!;
          canvas.drawLine(c + const Offset(0, -1.8), c, toe);
          for (final a in const [-.95, 0.0, .95]) {
            canvas.drawLine(
              c,
              c + Offset(math.sin(a) * 4.6, math.cos(a) * 1.4 + .6),
              toe,
            );
          }
      }
    }
  }

  // --- Cara -----------------------------------------------------------------

  void _face(Canvas canvas, TamaBody body, Paint skin, Color color) {
    final f = TamaFace.of(look, body);
    final gaze = Offset(
      pose.gaze.dx.clamp(-1.0, 1.0),
      pose.gaze.dy.clamp(-1.0, 1.0),
    );
    // La cara entera se desplaza un poco hacia donde mira: da sensacion de
    // cabeza que gira, no de ojos pegados.
    final faceShift = Offset(gaze.dx * 1.6, gaze.dy * 1.0);

    canvas.save();
    canvas.translate(faceShift.dx, faceShift.dy);
    _cheeks(canvas, f, color);
    for (final side in const [-1.0, 1.0]) {
      _eye(canvas, f, Offset(f.centre.dx + side * f.eyeDx, f.eyeY), side, gaze);
    }
    _mouth(canvas, f);
    canvas.restore();
  }

  void _cheeks(Canvas canvas, TamaFace f, Color color) {
    final variant = look.part(TamaPart.cheeks);
    final base = .22 + .62 * look.unit(TamaDial.cheekIntensity);
    for (final side in const [-1.0, 1.0]) {
      final c = Offset(
        f.centre.dx + side * (f.eyeDx + f.eyeR * .7),
        f.eyeY + f.eyeR * 1.2,
      );
      // El rubor del momento (vergueenza, mimos) sale aunque no haya mejillas.
      final extra = pose.blush.clamp(0.0, 1.0);
      if (variant == 1 || extra > 0) {
        final alpha = variant == 1
            ? math.min(1.0, base + extra * .3)
            : extra * .7;
        canvas.drawOval(
          Rect.fromCenter(center: c, width: f.eyeR * 2.0, height: f.eyeR * 1.1),
          Paint()
            ..color = T.tamaBlush.withValues(alpha: alpha * .9)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, f.eyeR * .28),
        );
      }
      switch (variant) {
        case 2: // Pecas.
          final dot = Paint()
            ..color = Color.lerp(color, T.dusk, .42)!.withValues(alpha: base);
          for (final (dx, dy) in const [(-.5, -.1), (.1, -.35), (.45, .2)]) {
            canvas.drawCircle(
              c + Offset(dx * f.eyeR * side, dy * f.eyeR),
              f.eyeR * .14,
              dot,
            );
          }
        case 3: // Rayitas de sonrojo.
          final line = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = f.eyeR * .16
            ..color = T.tamaBlush.withValues(alpha: math.min(1.0, base + .15));
          for (var i = -1; i <= 1; i++) {
            final x = c.dx + i * f.eyeR * .42;
            canvas.drawLine(
              Offset(x + f.eyeR * .2, c.dy - f.eyeR * .3),
              Offset(x - f.eyeR * .2, c.dy + f.eyeR * .3),
              line,
            );
          }
        case 4: // Corazoncitos.
          _heart(
            canvas,
            c + Offset(0, f.eyeR * .2),
            f.eyeR * 1.15,
            Paint()
              ..color = T.tamaBlush.withValues(alpha: math.min(1.0, base + .2)),
          );
        case 5: // Remolinos.
          final swirl = Path();
          for (var i = 0; i <= 28; i++) {
            final t = i / 28;
            final a = side * t * math.pi * 3.2;
            final rad = f.eyeR * (.08 + .5 * t);
            final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad * .8);
            i == 0 ? swirl.moveTo(p.dx, p.dy) : swirl.lineTo(p.dx, p.dy);
          }
          canvas.drawPath(
            swirl,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..strokeWidth = f.eyeR * .14
              ..color = T.tamaBlush.withValues(alpha: math.min(1.0, base + .2)),
          );
        case 6: // Estrellitas.
          final star = Paint()
            ..color = T.tamaSparkle.withValues(
              alpha: math.min(1.0, base + .25),
            );
          _star(canvas, c + Offset(side * f.eyeR * .1, 0), f.eyeR * 1.3, star);
          _star(
            canvas,
            c + Offset(side * f.eyeR * .62, -f.eyeR * .5),
            f.eyeR * .6,
            star,
          );
        case 7: // Pegatina: un circulo de rubor con su brillo.
          final disc = Rect.fromCenter(
            center: c,
            width: f.eyeR * 1.5,
            height: f.eyeR * 1.2,
          );
          canvas.drawOval(
            disc,
            Paint()
              ..color = Color.lerp(
                T.tamaBlush,
                color,
                .15,
              )!.withValues(alpha: math.min(1.0, base + .25)),
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: disc.center + Offset(-disc.width * .2, -disc.height * .2),
              width: disc.width * .3,
              height: disc.height * .22,
            ),
            Paint()..color = T.glintStrong,
          );
      }
    }
  }

  void _eye(Canvas canvas, TamaFace f, Offset c, double side, Offset gaze) {
    final r = f.eyeR;
    final variant = look.part(TamaPart.eyes);
    final ink = Paint()..color = T.tamaInk;
    final white = Paint()..color = T.shellTop;
    // Los ojos que ya estan cerrados (sonrientes, soñolientos) no parpadean.
    // El guiño cierra solo el de su izquierda.
    final winking = variant == 12 && side < 0;
    final alreadyClosed =
        variant == 2 || variant == 3 || variant == 8 || winking;
    final closed = alreadyClosed ? 0.0 : pose.blink.clamp(0.0, 1.0);
    final happy = pose.happyEyes.clamp(0.0, 1.0);
    final pupil = Offset(gaze.dx * r * .26, gaze.dy * r * .2);
    // El color propio de los ojos, en los que tienen iris o reflejo.
    final tint = tintableEyes.contains(variant)
        ? look.tint(TamaTint.eyes)
        : null;

    // Ojos cerrados: de gusto (arco hacia arriba) o de parpadeo (linea suave).
    if (happy > .5 || closed > .82) {
      final up = happy > .5;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * .72, c.dy + (up ? r * .22 : 0))
          ..quadraticBezierTo(
            c.dx,
            c.dy + (up ? -r * .62 : r * .42),
            c.dx + r * .72,
            c.dy + (up ? r * .22 : 0),
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * .3
          ..color = T.tamaInk,
      );
      return;
    }

    // Sueno: el parpado baja recortando el ojo por arriba; solo se ve su linea.
    final doze = alreadyClosed ? 0.0 : pose.doze.clamp(0.0, 1.0);
    final lidY = c.dy - r * 1.2 + r * 1.3 * doze;

    canvas.save();
    if (doze > .02) {
      canvas.clipRect(
        Rect.fromLTRB(c.dx - r * 2, lidY, c.dx + r * 2, c.dy + r * 2.4),
      );
    }
    // El parpadeo aplasta el ojo hacia su linea media.
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, 1 - closed * .9);

    // Ojo brillante, con dos brillos o con destello de estrella.
    void shiny({bool star = false}) {
      final eye = Rect.fromCenter(
        center: pupil * .5,
        width: r * 1.7,
        height: r * 2.06,
      );
      canvas.drawOval(
        eye,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // Con color propio el iris se ve entero, no solo un reflejo.
            colors: tint == null
                ? [
                    T.tamaInk,
                    T.tamaInk,
                    Color.lerp(T.tamaInk, look.bodyColor, .5)!,
                  ]
                : [
                    T.tamaInk,
                    Color.lerp(T.tamaInk, tint, .45)!,
                    Color.lerp(T.tamaInk, tint, .9)!,
                  ],
            stops: const [0, .5, 1],
          ).createShader(eye),
      );
      if (!star) {
        canvas.drawCircle(pupil + Offset(-r * .3, -r * .42), r * .34, white);
        canvas.drawCircle(pupil + Offset(r * .3, r * .4), r * .14, white);
      } else {
        _star(canvas, pupil + Offset(-r * .22, -r * .34), r * .5, white);
        canvas.drawCircle(pupil + Offset(r * .34, r * .42), r * .12, white);
      }
    }

    // Arco cerrado de contento (^), como los sonrientes.
    void arc() => canvas.drawPath(
      Path()
        ..moveTo(-r * .74 + pupil.dx * .5, r * .3)
        ..quadraticBezierTo(
          pupil.dx * .5,
          -r * .62,
          r * .74 + pupil.dx * .5,
          r * .3,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * .34
        ..color = T.tamaInk,
    );

    switch (variant) {
      case 0: // Puntitos.
        canvas.drawOval(
          Rect.fromCenter(center: pupil * .6, width: r * 1.1, height: r * 1.46),
          ink,
        );
        canvas.drawCircle(
          pupil * .6 + Offset(-r * .2, -r * .32),
          r * .22,
          white,
        );
      case 1: // Brillantes.
        shiny();
      case 4: // Con destello de estrella.
        shiny(star: true);
      case 2: // Sonrientes (^ ^).
        arc();
      case 3: // Soñolientos: cerrados en paz, con dos pestañitas.
        final lid = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * .3
          ..color = T.tamaInk;
        final dx = pupil.dx * .3;
        canvas.drawPath(
          Path()
            ..moveTo(-r * .78 + dx, -r * .05)
            ..quadraticBezierTo(dx, r * .62, r * .78 + dx, -r * .05),
          lid,
        );
        lid.strokeWidth = r * .16;
        final outer = side > 0 ? r * .78 : -r * .78;
        canvas.drawLine(
          Offset(outer + dx, -r * .05),
          Offset(outer * 1.28 + dx, -r * .3),
          lid,
        );
        canvas.drawLine(
          Offset(outer * .5 + dx, r * .22),
          Offset(outer * .72 + dx, r * .52),
          lid,
        );
      case 5: // Saltones: blanco con pupila que se mueve.
        final ball = Rect.fromCircle(center: Offset.zero, radius: r * 1.02);
        canvas.drawOval(ball, white);
        canvas.drawOval(
          ball,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .14
            ..color = T.tamaInk.withValues(alpha: .8),
        );
        final p = Offset(gaze.dx * r * .42, gaze.dy * r * .36 + r * .06);
        canvas.drawCircle(p, r * .52, ink);
        canvas.drawCircle(p + Offset(-r * .18, -r * .2), r * .16, white);
      case 6: // Corazones.
        final s = r * 2.7;
        _heart(
          canvas,
          pupil * .5 + Offset(0, s * .13),
          s,
          Paint()..color = tint ?? T.tamaHeart,
        );
        canvas.drawCircle(
          pupil * .5 + Offset(-r * .5, -r * .42),
          r * .26,
          white,
        );
      case 7: // Remolinos, de mareo.
        final swirl = Path();
        for (var i = 0; i <= 36; i++) {
          final t = i / 36;
          final a = side * t * math.pi * 4.2;
          final rad = r * (.06 + .9 * t);
          final p = pupil * .3 + Offset(math.cos(a) * rad, math.sin(a) * rad);
          i == 0 ? swirl.moveTo(p.dx, p.dy) : swirl.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
          swirl,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = r * .2
            ..color = T.tamaInk,
        );
      case 8: // Apretados (> <).
        final dx = side * r * .1;
        canvas.drawPath(
          Path()
            ..moveTo(side * r * .62 + dx, -r * .55)
            ..lineTo(-side * r * .5 + dx, 0)
            ..lineTo(side * r * .62 + dx, r * .55),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = r * .3
            ..color = T.tamaInk,
        );
      case 9: // De anime: grandes, con el iris del color del Tama (o el suyo).
        final eye = Rect.fromCenter(
          center: pupil * .4,
          width: r * 1.8,
          height: r * 2.4,
        );
        canvas.drawOval(eye, ink);
        final iris = eye.deflate(r * .16);
        canvas.drawOval(
          iris,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                T.tamaInk,
                Color.lerp(tint ?? look.bodyColor, T.dusk, .3)!,
                Color.lerp(tint ?? look.bodyColor, T.shellTop, .35)!,
              ],
              stops: const [0, .45, 1],
            ).createShader(iris),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: pupil * .6 + Offset(0, r * .1),
            width: r * .7,
            height: r * 1,
          ),
          ink,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: pupil + Offset(-r * .32, -r * .55),
            width: r * .62,
            height: r * .74,
          ),
          white,
        );
        canvas.drawCircle(pupil + Offset(r * .34, r * .5), r * .16, white);
        canvas.drawCircle(pupil + Offset(r * .4, -r * .2), r * .09, white);
      case 10: // De gato: iris verde (o el suyo) y pupila en rendija.
        final eye = Rect.fromCenter(
          center: Offset.zero,
          width: r * 1.8,
          height: r * 1.9,
        );
        canvas.drawOval(
          eye,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Color.lerp(tint ?? T.tamaCatEye, T.shellTop, .35)!,
                tint ?? T.tamaCatEye,
              ],
            ).createShader(eye),
        );
        canvas.drawOval(
          eye,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * .16
            ..color = T.tamaInk,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(gaze.dx * r * .3, gaze.dy * r * .15),
            width: r * .34,
            height: r * 1.45,
          ),
          ink,
        );
        canvas.drawCircle(Offset(-r * .36, -r * .4), r * .16, white);
      case 11: // Puntitos con pestañas.
        canvas.drawOval(
          Rect.fromCenter(center: pupil * .6, width: r * 1.1, height: r * 1.46),
          ink,
        );
        canvas.drawCircle(
          pupil * .6 + Offset(-r * .2, -r * .32),
          r * .22,
          white,
        );
        final lash = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * .16
          ..color = T.tamaInk;
        // Tres pestañas en la parte de fuera de arriba, hacia fuera.
        final centre = pupil * .6;
        for (final a in const [.45, .9, 1.3]) {
          final dir = Offset(side * math.sin(a), -math.cos(a));
          final from = centre + Offset(dir.dx * r * .55, dir.dy * r * .73);
          canvas.drawLine(from, from + dir * (r * .42), lash);
        }
      case 12: // Guiño: el de su izquierda cerrado, el otro brillante.
        if (winking) {
          arc();
        } else {
          shiny();
        }
      case 13: // Alargados, con brillo arriba y el color del Tama abajo.
        final eye = Rect.fromCenter(
          center: pupil * .5,
          width: r * 1.0,
          height: r * 2.1,
        );
        canvas.drawOval(
          eye,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                T.tamaInk,
                T.tamaInk,
                Color.lerp(
                  T.tamaInk,
                  tint ?? look.bodyColor,
                  tint != null ? .85 : .7,
                )!,
              ],
              stops: const [0, .55, 1],
            ).createShader(eye),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: pupil * .5 + Offset(0, -r * .5),
            width: r * .6,
            height: r * .8,
          ),
          white,
        );
    }
    canvas.restore();

    // La linea del parpado mide lo que el ojo a esa altura: si aun no lo toca,
    // no se pinta.
    final (halfW, halfH) = switch (variant) {
      0 || 11 => (r * .55, r * .73),
      5 => (r * 1.02, r * 1.02),
      6 => (r * 1.25, r * 1.0),
      7 || 10 => (r * .92, r * .96),
      9 => (r * .9, r * 1.2),
      13 => (r * .5, r * 1.05),
      _ => (r * .85, r * 1.03),
    };
    final dy = (lidY - c.dy) / (halfH * (1 - closed * .9));
    if (doze > .02 && dy.abs() < 1) {
      final w = halfW * math.sqrt(1 - dy * dy) + r * .08;
      canvas.drawLine(
        Offset(c.dx - w, lidY),
        Offset(c.dx + w, lidY),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * .2
          ..color = T.tamaInk,
      );
    }

    // Melancolia: cejitas de preocupacion, con el extremo de dentro alto. Un
    // parpado caido se leia como enfado.
    final sad = math.max(0.0, -pose.joy);
    if (sad > .05) {
      final inner = Offset(c.dx - side * r * .7, c.dy - r * (1.55 + .25 * sad));
      final outer = Offset(c.dx + side * r * .8, c.dy - r * 1.25);
      canvas.drawPath(
        Path()
          ..moveTo(inner.dx, inner.dy)
          ..quadraticBezierTo(
            c.dx + side * r * .1,
            c.dy - r * 1.62,
            outer.dx,
            outer.dy,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * .2
          ..color = T.tamaInk.withValues(alpha: math.min(1.0, sad * 1.6)),
      );
    }
  }

  void _star(Canvas canvas, Offset c, double size, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4;
      final rad = i.isEven ? size * .5 : size * .16;
      final p = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _mouth(Canvas canvas, TamaFace f) {
    final m = f.mouthW;
    final c = Offset(f.centre.dx, f.mouthY);
    final variant = look.part(TamaPart.mouth);
    final open = pose.mouthOpen.clamp(0.0, 1.0);
    final joy = pose.joy.clamp(-1.0, 1.0);
    // Profundidad de la sonrisa: con humor bajo se endereza y acaba en puchero.
    final depth = m * (.18 + .5 * joy);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(.9, m * .28)
      ..color = T.tamaInk;

    void openMouth(double amount) {
      final rect = Rect.fromCenter(
        center: c + Offset(0, m * .3 * amount),
        width: m * (.9 + .5 * amount),
        height: m * (.35 + 1.1 * amount),
      );
      canvas.drawOval(rect, Paint()..color = T.tamaMouth);
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.bottom),
          width: rect.width * .8,
          height: rect.height * .8,
        ),
        Paint()..color = T.tamaTongue,
      );
      canvas.restore();
      canvas.drawOval(rect, line..strokeWidth = math.max(.8, m * .2));
    }

    if (open > .12) {
      openMouth(open);
      return;
    }

    // En las bocas de linea la lengua asoma por el punto mas bajo del labio,
    // pintada antes para quedar detras. Boquita y lengüita la sacan desde
    // dentro de su propia boca abierta (ver sus casos).
    final tongue = pose.tongue.clamp(0.0, 1.0);
    // Las bocas abiertas (boquita, lengüita, la D) la sacan desde dentro; el
    // pico, el morrito y la de dientes apretados, no.
    const ownTongue = {2, 4, 5, 8, 9, 12};
    if (tongue > .05 && !ownTongue.contains(variant)) {
      // El labio de cada boca, y la zona que queda por debajo de el: la lengua
      // se recorta a esa zona para que nunca asome por encima de la linea (en
      // la gatuna se colaba entre los dos arcos de la ω).
      final catDip = depth * 1.5 + m * .15;
      final lip = variant == 1
          ? (Path()
              ..moveTo(c.dx - m * 1.05, c.dy - m * .12)
              ..quadraticBezierTo(c.dx - m * .52, c.dy + catDip, c.dx, c.dy)
              ..quadraticBezierTo(
                c.dx + m * .52,
                c.dy + catDip,
                c.dx + m * 1.05,
                c.dy - m * .12,
              ))
          : (Path()
              ..moveTo(c.dx - m, c.dy)
              ..quadraticBezierTo(c.dx, c.dy + depth * 2, c.dx + m, c.dy));
      final below = Path.from(lip)
        ..lineTo(c.dx + m * 1.05, c.dy + m * 4)
        ..lineTo(c.dx - m * 1.05, c.dy + m * 4)
        ..close();
      // En la gatuna la lengua sale de entre los dos arcos, a la altura de su
      // parte baja; en las demas, del punto mas bajo de la sonrisa.
      final lipY = variant == 1 ? c.dy + catDip * .42 : c.dy + depth;
      canvas.save();
      canvas.clipPath(below);
      _tongueOut(canvas, Offset(c.dx, lipY), m, tongue);
      canvas.restore();
    }

    switch (variant) {
      case 0: // Sonrisa.
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - m, c.dy)
            ..quadraticBezierTo(c.dx, c.dy + depth * 2, c.dx + m, c.dy),
          line,
        );
      case 1: // Boca de gato.
        final d = depth * 1.5 + m * .15;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - m * 1.05, c.dy - m * .12)
            ..quadraticBezierTo(c.dx - m * .52, c.dy + d, c.dx, c.dy)
            ..quadraticBezierTo(
              c.dx + m * .52,
              c.dy + d,
              c.dx + m * 1.05,
              c.dy - m * .12,
            ),
          line,
        );
      case 2: // Boquita en o, con la lengua asomando dentro.
        final o = Rect.fromCenter(
          center: c + Offset(0, m * .2),
          width: m * 1.4,
          height: m * (1.45 + math.max(0, joy) * .15),
        );
        canvas.drawOval(o, Paint()..color = T.tamaMouth);
        canvas.save();
        canvas.clipPath(Path()..addOval(o));
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(o.center.dx, o.bottom - o.height * .08),
            width: o.width * .82,
            height: o.height * .9,
          ),
          Paint()..color = T.tamaTongue,
        );
        canvas.restore();
        canvas.drawOval(o, line..strokeWidth = math.max(.8, m * .2));
        if (tongue > .05) {
          // La lengua sale por abajo, por encima del borde de la boquita.
          _tongueOut(
            canvas,
            Offset(o.center.dx, o.center.dy + o.height * .15),
            m,
            tongue,
            reach: o.height * .35,
            width: o.width * .72,
          );
        }
      case 3: // Colmillo.
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + m * .18, c.dy + depth * .95)
            ..lineTo(c.dx + m * .52, c.dy + depth * .7)
            ..lineTo(c.dx + m * .36, c.dy + depth * .7 + m * .6)
            ..close(),
          Paint()..color = T.shellTop,
        );
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - m, c.dy)
            ..quadraticBezierTo(c.dx, c.dy + depth * 2, c.dx + m, c.dy),
          line,
        );
      case 4: // Sonrisa abierta con la lengüita fuera.
        final w = m * 1.15;
        final h = m * (.75 + .3 * math.max(0, joy));
        final smile = Path()
          ..moveTo(c.dx - w, c.dy - m * .05)
          ..quadraticBezierTo(c.dx, c.dy + m * .12, c.dx + w, c.dy - m * .05)
          ..cubicTo(
            c.dx + w * .9,
            c.dy + h * 1.2,
            c.dx - w * .9,
            c.dy + h * 1.2,
            c.dx - w,
            c.dy - m * .05,
          )
          ..close();
        canvas.drawPath(smile, Paint()..color = T.tamaMouth);
        canvas.drawPath(smile, line..strokeWidth = math.max(.8, m * .2));
        // Siempre asoma un poco por el borde de abajo; con la pose de lengua
        // fuera, bastante mas.
        _tongueOut(
          canvas,
          Offset(c.dx, c.dy + h * .3),
          m,
          .2 + tongue * .8,
          reach: h * .45,
          width: w * 1.05,
        );
      case 5: // Sonrisa en D, abierta de oreja a oreja.
        final w = m * 1.05;
        final h = m * (.9 + .4 * math.max(0, joy));
        final d = Path()
          ..moveTo(c.dx - w, c.dy - m * .1)
          ..lineTo(c.dx + w, c.dy - m * .1)
          ..quadraticBezierTo(c.dx + w, c.dy + h * 1.1, c.dx, c.dy + h)
          ..quadraticBezierTo(c.dx - w, c.dy + h * 1.1, c.dx - w, c.dy - m * .1)
          ..close();
        canvas.drawPath(d, Paint()..color = T.tamaMouth);
        canvas.save();
        canvas.clipPath(d);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(c.dx, c.dy + h * (1 - tongue * .1)),
            width: w * 1.3,
            height: h * (.9 + tongue * .4),
          ),
          Paint()..color = T.tamaTongue,
        );
        canvas.restore();
        canvas.drawPath(d, line..strokeWidth = math.max(.8, m * .2));
      case 6: // Ondulada.
        final wave = depth * .6;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - m * 1.1, c.dy)
            ..cubicTo(
              c.dx - m * .8,
              c.dy - m * .35,
              c.dx - m * .45,
              c.dy - m * .35,
              c.dx - m * .3,
              c.dy + wave * .3,
            )
            ..cubicTo(
              c.dx - m * .15,
              c.dy + m * .35 + wave,
              c.dx + m * .15,
              c.dy + m * .35 + wave,
              c.dx + m * .3,
              c.dy + wave * .3,
            )
            ..cubicTo(
              c.dx + m * .45,
              c.dy - m * .35,
              c.dx + m * .8,
              c.dy - m * .35,
              c.dx + m * 1.1,
              c.dy,
            ),
          line,
        );
      case 7: // Dientes de conejo.
        final y = c.dy + depth;
        final tooth = Paint()..color = T.shellTop;
        final edge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.5, m * .1)
          ..color = T.tamaInk.withValues(alpha: .7);
        for (final dx in const [-1.0, 1.0]) {
          final t = RRect.fromRectAndCorners(
            Rect.fromLTWH(
              dx < 0 ? c.dx - m * .42 : c.dx,
              y - m * .04,
              m * .42,
              m * .62,
            ),
            bottomLeft: Radius.circular(m * .1),
            bottomRight: Radius.circular(m * .1),
          );
          canvas.drawRRect(t, tooth);
          canvas.drawRRect(t, edge);
        }
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - m, c.dy)
            ..quadraticBezierTo(c.dx, c.dy + depth * 2, c.dx + m, c.dy),
          line,
        );
      case 8: // Piquito.
        final w = m * .85;
        final h = m * (.95 + .2 * math.max(0, joy));
        final beak = Path()
          ..moveTo(c.dx - w, c.dy - m * .2)
          ..quadraticBezierTo(c.dx, c.dy - m * .5, c.dx + w, c.dy - m * .2)
          ..quadraticBezierTo(c.dx + w * .4, c.dy + h * .5, c.dx, c.dy + h)
          ..quadraticBezierTo(
            c.dx - w * .4,
            c.dy + h * .5,
            c.dx - w,
            c.dy - m * .2,
          )
          ..close();
        canvas.drawPath(beak, Paint()..color = T.tamaBeak);
        canvas.drawLine(
          Offset(c.dx - w * .6, c.dy + h * .1),
          Offset(c.dx + w * .6, c.dy + h * .1),
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(.5, m * .1)
            ..color = Color.lerp(T.tamaBeak, T.dusk, .35)!,
        );
        canvas.drawPath(
          beak,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = math.max(.6, m * .14)
            ..color = Color.lerp(T.tamaBeak, T.dusk, .4)!,
        );
        canvas.drawCircle(
          Offset(c.dx - w * .35, c.dy - m * .12),
          m * .12,
          Paint()..color = T.glintStrong,
        );
      case 9: // Morrito (un 3 de lado).
        final s = m * .55;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - s * .3, c.dy - s * .9)
            ..quadraticBezierTo(
              c.dx + s * .9,
              c.dy - s * .95,
              c.dx + s * .1,
              c.dy - s * .05,
            )
            ..quadraticBezierTo(
              c.dx + s * .9,
              c.dy + s * .85,
              c.dx - s * .3,
              c.dy + s * .8,
            ),
          line..strokeWidth = math.max(.8, m * .24),
        );
      case 10: // Dos colmillos.
        for (final dx in const [-1.0, 1.0]) {
          canvas.drawPath(
            Path()
              ..moveTo(c.dx + dx * m * .22, c.dy + depth * .95)
              ..lineTo(c.dx + dx * m * .56, c.dy + depth * .7)
              ..lineTo(c.dx + dx * m * .4, c.dy + depth * .7 + m * .55)
              ..close(),
            Paint()..color = T.shellTop,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - m, c.dy)
            ..quadraticBezierTo(c.dx, c.dy + depth * 2, c.dx + m, c.dy),
          line,
        );
      case 11: // Puntito.
        canvas.drawOval(
          Rect.fromCenter(
            center: c + Offset(0, depth * .4),
            width: m * .55,
            height: m * (.42 + .1 * math.max(0, joy)),
          ),
          Paint()..color = T.tamaInk,
        );
      case 12: // Dientes: sonrisa enseñando las dos filas, apretadas.
        final w = m * 1.12;
        final h = m * (.8 + .25 * math.max(0, joy));
        final top = c.dy - m * .12;
        final grin = Path()
          ..moveTo(c.dx - w, top)
          ..quadraticBezierTo(c.dx, top + m * .22, c.dx + w, top)
          ..cubicTo(
            c.dx + w * .92,
            top + h * 1.25,
            c.dx - w * .92,
            top + h * 1.25,
            c.dx - w,
            top,
          )
          ..close();
        canvas.drawPath(grin, Paint()..color = T.shellTop);
        canvas.save();
        canvas.clipPath(grin);
        final gap = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(.45, m * .09)
          ..color = T.tamaInk.withValues(alpha: .55);
        // Donde se juntan las dos filas, y la separacion de cada diente.
        final bite = top + h * .5;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - w, bite - m * .04)
            ..quadraticBezierTo(c.dx, bite + m * .12, c.dx + w, bite - m * .04),
          gap,
        );
        for (final dx in const [-.62, -.3, 0.0, .3, .62]) {
          canvas.drawLine(
            Offset(c.dx + dx * w, top - m * .1),
            Offset(c.dx + dx * w * .96, top + h * 1.1),
            gap,
          );
        }
        canvas.restore();
        canvas.drawPath(grin, line..strokeWidth = math.max(.8, m * .2));
    }
  }

  /// Lengua fuera, del descarado: un lobulo centrado con su pliegue que asoma
  /// por debajo del labio. Se pinta antes que la boca, asi la linea del labio
  /// queda encima y la lengua sale de dentro en vez de estar pegada delante.
  void _tongueOut(
    Canvas canvas,
    Offset lip,
    double m,
    double amount, {
    double reach = 0,
    double? width,
  }) {
    final w = width ?? m * .78;
    // Ancha y redondeada: nunca mucho mas larga que ancha, o parece una pajita.
    final length = math.min(reach + m * (.35 + .75 * amount), reach + w * 1.05);
    final tongueWidth = w;
    final top = lip.dy - m * .12;
    final lobe = Path()
      ..moveTo(lip.dx - tongueWidth / 2, top)
      ..lineTo(lip.dx - tongueWidth / 2, top + length - tongueWidth / 2)
      ..arcToPoint(
        Offset(lip.dx + tongueWidth / 2, top + length - tongueWidth / 2),
        radius: Radius.circular(tongueWidth / 2),
        clockwise: false,
      )
      ..lineTo(lip.dx + tongueWidth / 2, top)
      ..close();
    canvas.drawPath(lobe, Paint()..color = T.tamaTongue);
    canvas.drawLine(
      Offset(lip.dx, top + m * .12),
      Offset(lip.dx, top + length * .62),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(.5, m * .09)
        ..color = Color.lerp(T.tamaTongue, T.tamaMouth, .45)!,
    );
  }

  // --- Efectos --------------------------------------------------------------

  void _hearts(Canvas canvas, TamaBody body) {
    final treat = pose.treat;
    if (treat >= 0 && treat < 1) {
      // La chuche cae desde arriba hasta la boca.
      final f = TamaFace.of(look, body);
      final target = Offset(centreX + pose.lean, f.mouthY - pose.hop);
      final start = Offset(target.dx + 22, 18);
      final t = Curves.easeIn.transform(treat.clamp(0.0, 1.0));
      final p = Offset.lerp(start, target, t)!;
      // Grande al caer, mas pequeña al llegar a la boca.
      final size = 6.2 * (1 - t * .4);
      final art = pose.foodArt;
      if (art != null) {
        art(canvas, p, size);
      } else {
        paintFood(canvas, pose.food, p, size);
      }
    }

    if (pose.hearts <= .01) return;
    final r = body.bounds;
    for (var i = 0; i < 3; i++) {
      final phase = (pose.heartPhase + i / 3) % 1.0;
      final alpha = pose.hearts * math.sin(phase * math.pi);
      if (alpha <= .02) continue;
      final x =
          r.center.dx + (i - 1) * r.width * .42 + math.sin(phase * 6 + i) * 2;
      final y = r.top + 2 - phase * 20 - pose.hop;
      _heart(
        canvas,
        Offset(x, y),
        5.2 + i * .6,
        Paint()..color = T.tamaHeart.withValues(alpha: alpha),
      );
    }
  }

  void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + s * .34)
        ..cubicTo(
          c.dx - s * .62,
          c.dy - s * .02,
          c.dx - s * .4,
          c.dy - s * .6,
          c.dx,
          c.dy - s * .26,
        )
        ..cubicTo(
          c.dx + s * .4,
          c.dy - s * .6,
          c.dx + s * .62,
          c.dy - s * .02,
          c.dx,
          c.dy + s * .34,
        )
        ..close(),
      paint,
    );
  }

  void _zzz(Canvas canvas, TamaBody body) {
    if (pose.doze < .6) return;
    final r = body.bounds;
    final alpha = ((pose.doze - .6) / .4).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.3
      ..color = T.inkSoft.withValues(alpha: alpha * .8);
    for (var i = 0; i < 2; i++) {
      final s = 3.2 + i * 1.4;
      final o = Offset(r.right - 2 + i * 5, r.top + 4 - i * 7 - pose.hop);
      canvas.drawPath(
        Path()
          ..moveTo(o.dx, o.dy)
          ..lineTo(o.dx + s, o.dy)
          ..lineTo(o.dx, o.dy + s)
          ..lineTo(o.dx + s, o.dy + s),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(TamaPainter old) =>
      old.look != look ||
      old._pose != _pose ||
      old._live != _live ||
      old.shadow != shadow ||
      old.wear != wear;
}

/// Silueta del cuerpo para un aspecto: el contorno y lo que hace falta para
/// colocar orejas, brazos y cara.
class TamaBody {
  TamaBody._(this.path, this.bounds, this._right);

  final Path path;
  final Rect bounds;

  /// Puntos del lado derecho del contorno, de arriba a abajo.
  final List<Offset> _right;

  static final Map<TamaLook, TamaBody> _cache = <TamaLook, TamaBody>{};

  /// Cuanto sube el cuerpo cuando tiene piernecitas.
  static const double legLift = 7;

  /// Cuanto sube el cuerpo con unos pies [feet]: las piernecitas y las
  /// piernas largas lo levantan para que se vean.
  static double liftFor(int feet) => switch (feet) {
    2 => legLift,
    7 => 11,
    _ => 0,
  };

  /// Semiancho del cuerpo a una altura dada.
  double halfWidthAt(double y) {
    if (y <= _right.first.dy) return 0;
    for (var i = 1; i < _right.length; i++) {
      final a = _right[i - 1];
      final b = _right[i];
      if (y <= b.dy) {
        final t = b.dy == a.dy ? 0.0 : (y - a.dy) / (b.dy - a.dy);
        return (a.dx + (b.dx - a.dx) * t) - TamaPainter.centreX;
      }
    }
    return 0;
  }

  static TamaBody of(TamaLook look) {
    final key = TamaLook(
      parts: {
        TamaPart.body: look.part(TamaPart.body),
        TamaPart.feet: liftFor(look.part(TamaPart.feet)) > 0
            ? look.part(TamaPart.feet)
            : 0,
      },
      dials: {
        TamaDial.bodyWidth: look.dial(TamaDial.bodyWidth),
        TamaDial.bodyHeight: look.dial(TamaDial.bodyHeight),
      },
    );
    final hit = _cache[key];
    if (hit != null) return hit;
    if (_cache.length > 64) _cache.clear();
    return _cache[key] = _build(look);
  }

  static double _smooth(double e0, double e1, double x) {
    final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static TamaBody _build(TamaLook look) {
    final shape = look.part(TamaPart.body);
    final wf = .82 + .36 * look.unit(TamaDial.bodyWidth);
    // Con piernas largas el cuerpo es algo mas bajo: lo alto lo ponen ellas.
    final legs = look.part(TamaPart.feet) == 7 ? .88 : 1.0;
    final hf = (.82 + .36 * look.unit(TamaDial.bodyHeight)) * legs;

    // Exponente de superelipse (2 es un circulo), radios y deformaciones.
    final (n, rx, ry) = switch (shape) {
      0 => (2.2, 1.0, .95), // redondo
      1 => (2.55, 1.13, .86), // alubia
      2 => (2.1, .9, 1.06), // huevo
      3 => (2.25, .95, 1.02), // pera
      4 => (2.6, 1.18, .9), // mochi
      5 => (2.05, .98, 1.0), // gota
      6 => (4.0, 1.0, .92), // cuadradito
      7 => (2.2, 1.04, .9), // nube
      8 => (2.3, 1.0, 1.0), // campana
      9 => (3.8, 1.08, .88), // flan
      10 => (2.4, 1.14, .98), // onigiri
      11 => (2.1, .96, 1.04), // cacahuete
      12 => (2.9, .86, 1.04), // capsula
      _ => (2.2, .96, 1.04), // fantasma
    };

    const count = 72;
    final raw = <Offset>[];
    for (var i = 0; i < count; i++) {
      final t = -math.pi / 2 + i * 2 * math.pi / count;
      final c = math.cos(t);
      final s = math.sin(t);
      var x = c.sign * math.pow(c.abs(), 2 / n).toDouble();
      var y = s.sign * math.pow(s.abs(), 2 / n).toDouble();
      switch (shape) {
        case 0:
          if (y > .6) y = .6 + (y - .6) * .7;
        case 1:
          if (y > .5) y = .5 + (y - .5) * .75;
        case 2:
          x *= 1 + .13 * y;
        case 3:
          x *= .76 + .38 * math.pow((y + 1) / 2, 1.5).toDouble();
          if (y > .6) y = .6 + (y - .6) * .7;
        case 4:
          if (y > .4) y = .4 + (y - .4) * .55;
          x *= 1 + .06 * y;
        case 5:
          if (y < 0) {
            x *= .56 + .44 * _smooth(-1.05, .4, y);
            y *= 1.08;
          } else if (y > .6) {
            y = .6 + (y - .6) * .75;
          }
        case 6:
          if (y > .6) y = .6 + (y - .6) * .7;
        case 7:
          // Borreguitos en la mitad de arriba; la de abajo, lisa para apoyar.
          final bump = 1 + .09 * math.cos(t * 10) * (1 - _smooth(.15, .6, y));
          x *= bump;
          y *= bump;
          if (y > .5) y = .5 + (y - .5) * .7;
        case 8:
          // Estrecha arriba y con vuelo abajo.
          x *= .66 + .46 * math.pow((y + 1) / 2, 1.6).toDouble();
          if (y > .62) y = .62 + (y - .62) * .6;
        case 9:
          // Mas estrecho arriba, con la tapa plana, como un flan desmoldado.
          x *= .66 + .38 * (y + 1) / 2;
          if (y > .5) y = .5 + (y - .5) * .7;
        case 10:
          x *= .4 + .6 * math.pow((y + 1) / 2, .8).toDouble();
          if (y > .55) y = .55 + (y - .55) * .6;
        case 11:
          // Cintura y la bola de arriba algo mas pequeña.
          x *= 1 - .2 * math.exp(-math.pow((y + .08) / .24, 2)).toDouble();
          if (y < 0) x *= .9;
          if (y > .7) y = .7 + (y - .7) * .7;
        case 12:
          if (y > .7) y = .7 + (y - .7) * .75;
        case 13:
          // Cabeza redonda, faldon recto y el borde de abajo en ondas.
          if (y > 0) x *= 1 + .07 * y;
          if (y > .7) {
            final hem = _smooth(.7, .95, y);
            y = .7 + (y - .7) * .6 + .05 * math.cos(x * math.pi * 3) * hem;
          }
      }
      raw.add(Offset(x * rx * wf, y * ry * hf));
    }

    var maxY = -double.infinity;
    for (final p in raw) {
      maxY = math.max(maxY, p.dy);
    }
    // El cuerpo apoya justo encima del suelo, o sobre sus piernecitas.
    final bottom = TamaPainter.floor - 1.2 - liftFor(look.part(TamaPart.feet));
    final points = [
      for (final p in raw)
        Offset(
          TamaPainter.centreX + p.dx * TamaPainter.baseRadius,
          bottom + (p.dy - maxY) * TamaPainter.baseRadius,
        ),
    ];

    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < count; i++) {
      final p0 = points[(i - 1 + count) % count];
      final p1 = points[i];
      final p2 = points[(i + 1) % count];
      final p3 = points[(i + 2) % count];
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    path.close();

    // Lado derecho, de la cima (indice 0) al fondo (indice count / 2).
    final right = points.sublist(0, count ~/ 2 + 1);
    return TamaBody._(path, path.getBounds(), right);
  }
}

/// Donde van ojos, mejillas y boca.
class TamaFace {
  const TamaFace._({
    required this.centre,
    required this.eyeY,
    required this.eyeDx,
    required this.eyeR,
    required this.mouthY,
    required this.mouthW,
  });

  final Offset centre;
  final double eyeY;
  final double eyeDx;
  final double eyeR;
  final double mouthY;
  final double mouthW;

  static TamaFace of(TamaLook look, TamaBody body) {
    final r = body.bounds;
    final scale = math.sqrt(r.width * r.height) / (TamaPainter.baseRadius * 2);
    // Cara algo baja y ojos separados: proporciones de cria, que es lo que
    // hace que algo parezca achuchable.
    final eyeY = r.top + r.height * (.38 + .24 * look.unit(TamaDial.eyeHeight));
    final eyeR =
        TamaPainter.baseRadius *
        (.13 + .1 * look.unit(TamaDial.eyeSize)) *
        scale;
    final half = body.halfWidthAt(eyeY);
    final eyeDx = half * (.28 + .26 * look.unit(TamaDial.eyeSpacing));
    final mouthY =
        eyeY +
        eyeR * .9 +
        r.height * (.03 + .1 * look.unit(TamaDial.mouthHeight));
    final mouthW =
        TamaPainter.baseRadius *
        (.075 + .09 * look.unit(TamaDial.mouthSize)) *
        scale;
    return TamaFace._(
      centre: Offset(r.center.dx, eyeY),
      eyeY: eyeY,
      eyeDx: eyeDx,
      eyeR: eyeR,
      mouthY: mouthY,
      mouthW: mouthW,
    );
  }
}
