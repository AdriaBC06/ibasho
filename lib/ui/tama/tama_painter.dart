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
  })  : _pose = pose,
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
    paintOutfit(canvas, look, body, const {PrizeSlot.back, PrizeSlot.waist, PrizeSlot.aura});

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

    _feetFront(canvas, body, color, rim);
    paintOutfit(canvas, look, body, const {PrizeSlot.feet});
    // Y la parte de delante de lo que va en dos (correas, flotador, hadas).
    paintOutfit(canvas, look, body, const {PrizeSlot.back, PrizeSlot.waist, PrizeSlot.aura}, front: true);
    _face(canvas, body, skin, color);
    // Lo de la cara y el cuello, luego el gorro y al final lo que tiene al
    // lado. El gorrito del cumpleaños solo sale si no lleva gorro.
    paintOutfit(canvas, look, body, const {PrizeSlot.eyes, PrizeSlot.nose, PrizeSlot.neck});
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
            alpha: T.tamaGroundShadow.a * (1 - lift * .55))
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
          colors: [
            T.glintNone,
            T.glintNone,
            T.dusk.withValues(alpha: .10),
          ],
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

  static Color patternColor(Color base, double tone) {
    if (tone < .5) return Color.lerp(base, T.shellTop, .74 - tone * .9)!;
    return Color.lerp(base, T.dusk, .12 + (tone - .5) * .62)!;
  }

  void _pattern(Canvas canvas, TamaBody body, Color color) {
    final variant = look.part(TamaPart.pattern);
    if (variant == 0) return;
    final r = body.bounds;
    final paint = Paint()
      ..color = patternColor(color, look.unit(TamaDial.patternTone));
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
            Offset(r.center.dx + dx * r.width / 2, r.center.dy + dy * r.height / 2),
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
              ..quadraticBezierTo(r.center.dx, y - r.height * .06,
                  r.right + 2, y + r.height * .1),
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
              x0 - step / 2, y + r.height * .09, x0 - step, y);
        }
        path.close();
        canvas.drawPath(path, paint);
    }
  }

  void _crownBehind(
      Canvas canvas, TamaBody body, Paint skin, Color rim, Color color) {
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
              inner, Paint()..color = Color.lerp(color, T.tamaBlush, .62)!);
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
              center: Offset(0, -h * .42), width: w, height: h);
          canvas.drawOval(ear, skin);
          canvas.drawOval(ear, outline);
          canvas.drawOval(
            Rect.fromCenter(
                center: Offset(0, -h * .38), width: w * .48, height: h * .7),
            Paint()..color = Color.lerp(color, T.tamaBlush, .6)!,
          );
          canvas.restore();
        case 3: // Antenas.
          final base = Offset(r.center.dx + side * r.width * .16, r.top + r.height * .08);
          final tip = Offset(
            r.center.dx + side * r.width * (.3 + pose.sway * .25),
            r.top - r.height * .3 * k + pose.sway.abs() * 2,
          );
          canvas.drawPath(
            Path()
              ..moveTo(base.dx, base.dy)
              ..quadraticBezierTo(
                  base.dx + side * 1.5, tip.dy + (base.dy - tip.dy) * .35, tip.dx, tip.dy),
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
              horn, outline..color = Color.lerp(hornColor, T.dusk, .3)!);
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
      }
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
      canvas.drawLine(Offset(-half * 1.4, y + half * .5), Offset(half * 1.4, y - half * .5), stripe);
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
        colors: [T.shellTop, T.partyPompom, Color.lerp(T.partyPompom, T.partyStripe, .55)!],
        stops: const [0, .5, 1],
      ).createShader(Rect.fromCircle(center: tip, radius: 4.4));
    for (final (dx, dy, rad) in const [(-2.0, .6, 2.4), (2.0, .6, 2.4), (0.0, -1.4, 2.7)]) {
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
        canvas.drawCircle(hand + Offset(-side * hr * .8, -hr * .3), hr * .45, handColor);
        canvas.drawCircle(hand + Offset(-side * hr * .8, -hr * .3), hr * .45, outline);
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
          ..cubicTo(side * w * .5, h * .45, side * w * 1.1, h * .05, side * w, -h * .45)
          ..cubicTo(side * w * .75, -h * .25, side * w * .45, -h * .5, side * w * .3, -h * .2)
          ..cubicTo(side * w * .15, -h * .35, 0, -h * .1, 0, h * .3)
          ..close();
        canvas.drawPath(wing, Paint()..color = Color.lerp(color, T.shellTop, .5)!);
        canvas.drawPath(wing, outline);
        canvas.restore();
      }
    }
  }

  void _feetBehind(
      Canvas canvas, TamaBody body, Paint skin, Color rim, Color color) {
    final variant = look.part(TamaPart.feet);
    if (variant == 2) {
      _legs(canvas, body, rim, color);
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
  void _legs(Canvas canvas, TamaBody body, Color rim, Color color) {
    final r = body.bounds;
    final legColor = Color.lerp(color, T.dusk, .12)!;
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = rim.withValues(alpha: .55);
    for (final side in const [-1.0, 1.0]) {
      final x = r.center.dx + side * r.width * .17;
      final leg = RRect.fromRectAndRadius(
        Rect.fromLTRB(x - r.width * .055, r.bottom - 4, x + r.width * .055, floor - 2.5),
        Radius.circular(r.width * .055),
      );
      canvas.drawRRect(leg, Paint()..color = legColor);
      canvas.drawRRect(leg, outline);
      final shoe = Rect.fromCenter(
        center: Offset(x + side * r.width * .03, floor - 2.2),
        width: r.width * .21,
        height: 5.2,
      );
      canvas.drawOval(shoe, Paint()..color = Color.lerp(color, T.dusk, .28)!);
      canvas.drawOval(shoe, outline);
      canvas.drawOval(
        Rect.fromCenter(center: shoe.center.translate(-shoe.width * .15, -1.2), width: shoe.width * .35, height: 1.4),
        Paint()..color = T.glintSoft,
      );
    }
  }

  void _feetFront(Canvas canvas, TamaBody body, Color color, Color rim) {
    if (look.part(TamaPart.feet) != 1 || hidesFeet(look)) return;
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
      _eye(canvas, f, Offset(f.centre.dx + side * f.eyeDx, f.eyeY), side, gaze,
          skin);
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
        final alpha = variant == 1 ? math.min(1.0, base + extra * .3) : extra * .7;
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
      }
    }
  }

  void _eye(Canvas canvas, TamaFace f, Offset c, double side, Offset gaze,
      Paint skin) {
    final r = f.eyeR;
    final variant = look.part(TamaPart.eyes);
    final ink = Paint()..color = T.tamaInk;
    final white = Paint()..color = T.shellTop;
    // Los ojos que ya estan cerrados (sonrientes, soñolientos) no parpadean.
    final alreadyClosed = variant == 2 || variant == 3;
    final closed = alreadyClosed ? 0.0 : pose.blink.clamp(0.0, 1.0);
    final happy = pose.happyEyes.clamp(0.0, 1.0);
    final pupil = Offset(gaze.dx * r * .26, gaze.dy * r * .2);

    // Ojos cerrados: de gusto (arco hacia arriba) o de parpadeo (linea suave).
    if (happy > .5 || closed > .82) {
      final up = happy > .5;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - r * .72, c.dy + (up ? r * .22 : 0))
          ..quadraticBezierTo(
              c.dx, c.dy + (up ? -r * .62 : r * .42), c.dx + r * .72,
              c.dy + (up ? r * .22 : 0)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = r * .3
          ..color = T.tamaInk,
      );
      return;
    }

    canvas.save();
    // El parpadeo aplasta el ojo hacia su linea media.
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, 1 - closed * .9);

    switch (variant) {
      case 0: // Puntitos.
        canvas.drawOval(
          Rect.fromCenter(center: pupil * .6, width: r * 1.1, height: r * 1.46),
          ink,
        );
        canvas.drawCircle(pupil * .6 + Offset(-r * .2, -r * .32), r * .22, white);
      case 1: // Brillantes.
      case 4: // Con destello de estrella.
        final eye = Rect.fromCenter(
            center: pupil * .5, width: r * 1.7, height: r * 2.06);
        canvas.drawOval(
          eye,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                T.tamaInk,
                T.tamaInk,
                Color.lerp(T.tamaInk, look.bodyColor, .5)!,
              ],
              stops: const [0, .5, 1],
            ).createShader(eye),
        );
        if (variant == 1) {
          canvas.drawCircle(pupil + Offset(-r * .3, -r * .42), r * .34, white);
          canvas.drawCircle(pupil + Offset(r * .3, r * .4), r * .14, white);
        } else {
          _star(canvas, pupil + Offset(-r * .22, -r * .34), r * .5, white);
          canvas.drawCircle(pupil + Offset(r * .34, r * .42), r * .12, white);
        }
      case 2: // Sonrientes (^ ^).
        canvas.drawPath(
          Path()
            ..moveTo(-r * .74 + pupil.dx * .5, r * .3)
            ..quadraticBezierTo(pupil.dx * .5, -r * .62, r * .74 + pupil.dx * .5, r * .3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = r * .34
            ..color = T.tamaInk,
        );
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
    }
    canvas.restore();

    // Sueno: parpados a media asta, pintados con la misma piel que el cuerpo
    // para que el corte no se note.
    final doze = pose.doze.clamp(0.0, 1.0);
    if (doze > .02 && variant != 2 && variant != 3) {
      final lidY = c.dy - r * 1.2 + r * 1.3 * doze;
      canvas.drawRect(
        Rect.fromLTRB(c.dx - r * 1.3, c.dy - r * 2.4, c.dx + r * 1.3, lidY),
        skin,
      );
      canvas.drawLine(
        Offset(c.dx - r * .9, lidY),
        Offset(c.dx + r * .9, lidY),
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
              c.dx + side * r * .1, c.dy - r * 1.62, outer.dx, outer.dy),
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
    if (tongue > .05 && variant != 2 && variant != 4) {
      // El labio de cada boca, y la zona que queda por debajo de el: la lengua
      // se recorta a esa zona para que nunca asome por encima de la linea (en
      // la gatuna se colaba entre los dos arcos de la ω).
      final catDip = depth * 1.5 + m * .15;
      final lip = variant == 1
          ? (Path()
            ..moveTo(c.dx - m * 1.05, c.dy - m * .12)
            ..quadraticBezierTo(c.dx - m * .52, c.dy + catDip, c.dx, c.dy)
            ..quadraticBezierTo(c.dx + m * .52, c.dy + catDip, c.dx + m * 1.05, c.dy - m * .12))
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
            ..quadraticBezierTo(c.dx + m * .52, c.dy + d, c.dx + m * 1.05, c.dy - m * .12),
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
          _tongueOut(canvas, Offset(o.center.dx, o.center.dy + o.height * .15), m,
              tongue, reach: o.height * .35, width: o.width * .72);
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
          ..cubicTo(c.dx + w * .9, c.dy + h * 1.2, c.dx - w * .9, c.dy + h * 1.2, c.dx - w, c.dy - m * .05)
          ..close();
        canvas.drawPath(smile, Paint()..color = T.tamaMouth);
        canvas.drawPath(smile, line..strokeWidth = math.max(.8, m * .2));
        // Siempre asoma un poco por el borde de abajo; con la pose de lengua
        // fuera, bastante mas.
        _tongueOut(canvas, Offset(c.dx, c.dy + h * .3), m, .2 + tongue * .8,
            reach: h * .45, width: w * 1.05);
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
      paintFood(canvas, pose.food, p, 6.2 * (1 - t * .4));
    }

    if (pose.hearts <= .01) return;
    final r = body.bounds;
    for (var i = 0; i < 3; i++) {
      final phase = (pose.heartPhase + i / 3) % 1.0;
      final alpha = pose.hearts * math.sin(phase * math.pi);
      if (alpha <= .02) continue;
      final x = r.center.dx + (i - 1) * r.width * .42 + math.sin(phase * 6 + i) * 2;
      final y = r.top + 2 - phase * 20 - pose.hop;
      _heart(canvas, Offset(x, y), 5.2 + i * .6,
          Paint()..color = T.tamaHeart.withValues(alpha: alpha));
    }
  }

  void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + s * .34)
        ..cubicTo(c.dx - s * .62, c.dy - s * .02, c.dx - s * .4, c.dy - s * .6,
            c.dx, c.dy - s * .26)
        ..cubicTo(c.dx + s * .4, c.dy - s * .6, c.dx + s * .62, c.dy - s * .02,
            c.dx, c.dy + s * .34)
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
        TamaPart.feet: look.part(TamaPart.feet) == 2 ? 2 : 0,
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
    final hf = .82 + .36 * look.unit(TamaDial.bodyHeight);

    // Exponente de superelipse (2 es un circulo), radios y deformaciones.
    final (n, rx, ry) = switch (shape) {
      0 => (2.2, 1.0, .95), // redondo
      1 => (2.55, 1.13, .86), // alubia
      2 => (2.1, .9, 1.06), // huevo
      3 => (2.25, .95, 1.02), // pera
      4 => (2.6, 1.18, .9), // mochi
      _ => (2.05, .98, 1.0), // gota
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
      }
      raw.add(Offset(x * rx * wf, y * ry * hf));
    }

    var maxY = -double.infinity;
    for (final p in raw) {
      maxY = math.max(maxY, p.dy);
    }
    // El cuerpo apoya justo encima del suelo, o sobre sus piernecitas.
    final bottom = TamaPainter.floor - 1.2 - (look.part(TamaPart.feet) == 2 ? legLift : 0);
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
    final eyeR = TamaPainter.baseRadius * (.13 + .1 * look.unit(TamaDial.eyeSize)) * scale;
    final half = body.halfWidthAt(eyeY);
    final eyeDx = half * (.28 + .26 * look.unit(TamaDial.eyeSpacing));
    final mouthY = eyeY + eyeR * .9 + r.height * (.03 + .1 * look.unit(TamaDial.mouthHeight));
    final mouthW = TamaPainter.baseRadius * (.075 + .09 * look.unit(TamaDial.mouthSize)) * scale;
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
