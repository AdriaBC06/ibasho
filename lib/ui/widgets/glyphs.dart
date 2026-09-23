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
///
/// Normas de dibujo, para los que hay y los que vengan:
/// - Todo el trazo cabe dentro de la caja, con al menos 1,2 de margen contando
///   el grosor.
/// - Un icono se lee como una sola linea: las piezas se unen en sus extremos o
///   se separan con aire, nunca se cruzan ni se montan unas encima de otras.
///   Si una forma lleva orejas, dientes o patas, van en el mismo contorno.
/// - Se pinta en una sola capa (ver [_GlyphPainter.paint]): con un color
///   translucido, donde dos trazos se tocan no se oscurece.
/// `test/glyphs_test.dart` comprueba las dos primeras con pixeles de verdad.
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
  minus,
  lock,
  eye,
  eyeOff,
  cake,
  clock,
  chevronDown,
  tama,
  undo,
  heart,
  treat,
  pencil,
  eraser,
  portrait,
  trash,
  wave,
  friends,
  personPlus,
  speakerOff,
  download,
  paste,
  star,
  send,
  news,
  chat,
  bulb,
  coin,
  mine,
  blocks,
  kana,
  pause,
  yatai,
  gift,
  trophy,
  flag,
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
    // Todo el icono va a una capa con la opacidad aplicada una sola vez: dos
    // trazos que se tocan no suman transparencia y el icono sigue siendo una
    // unica linea aunque el color sea translucido.
    // El ojo tachado recorta su hueco con `BlendMode.clear`: siempre necesita
    // capa propia, o recortaria tambien lo que haya debajo del icono.
    final layered = color.a < 1 || glyph == Glyph.eyeOff;
    if (layered) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, color.a),
      );
    }
    canvas.save();
    canvas.scale(scale);
    // Dentro de la capa se pinta opaco; la opacidad la pone la capa.
    final ink = color.withValues(alpha: 1);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    final fill = Paint()..color = ink;

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
          ..color = ink;
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
        // Cuerpo de capsula; la cabeza y las patas nacen en su borde y las
        // antenas en la cabeza: todo se toca por los extremos, nada se cruza.
        const cx = 12.0;
        const radius = 4.4;
        const top = 9.6;
        const bottom = 20.4;
        double edge(double y) {
          final c = y < top + radius
              ? top + radius
              : (y > bottom - radius ? bottom - radius : y);
          final dy = (y - c).abs();
          return math.sqrt(math.max(0, radius * radius - dy * dy));
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(cx - radius, top, cx + radius, bottom),
            const Radius.circular(radius),
          ),
          stroke,
        );
        final neck = top + radius - math.sqrt(radius * radius - 2.6 * 2.6);
        canvas.drawPath(
          Path()
            ..moveTo(cx - 2.6, neck)
            ..cubicTo(cx - 2.6, 5.6, cx + 2.6, 5.6, cx + 2.6, neck),
          stroke,
        );
        canvas.drawLine(const Offset(cx - 1.5, 6.6), const Offset(cx - 3.2, 3.6), stroke);
        canvas.drawLine(const Offset(cx + 1.5, 6.6), const Offset(cx + 3.2, 3.6), stroke);
        for (final y in const [13.2, 16.8]) {
          final e = edge(y);
          canvas.drawLine(Offset(cx - e, y), Offset(cx - e - 3.2, y - 1.3), stroke);
          canvas.drawLine(Offset(cx + e, y), Offset(cx + e + 3.2, y - 1.3), stroke);
        }
        canvas.drawLine(const Offset(cx, 14), const Offset(cx, 17.4), stroke);
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
      case Glyph.minus:
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
        // La barra corta el ojo con un hueco a cada lado, no se monta encima.
        canvas.drawLine(
          const Offset(4.6, 20.2),
          const Offset(19.4, 3.8),
          Paint()
            ..blendMode = BlendMode.clear
            ..strokeWidth = strokeWidth * 2.6
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawLine(const Offset(4.6, 20.2), const Offset(19.4, 3.8), stroke);
      case Glyph.cake:
        // Tarta con glaseado y una vela; la llama va separada con aire.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(4, 11.4, 16, 9), const Radius.circular(2.8)),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4, 14.8)
            ..quadraticBezierTo(6, 17.2, 8, 14.8)
            ..quadraticBezierTo(10, 17.2, 12, 14.8)
            ..quadraticBezierTo(14, 17.2, 16, 14.8)
            ..quadraticBezierTo(18, 17.2, 20, 14.8),
          stroke,
        );
        canvas.drawLine(const Offset(12, 11.4), const Offset(12, 8.2), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(12, 2.6)
            ..quadraticBezierTo(13.5, 4.6, 12, 5.5)
            ..quadraticBezierTo(10.5, 4.6, 12, 2.6)
            ..close(),
          fill,
        );
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
        // Silueta de un Tama en un solo contorno: orejas y cuerpo son la misma
        // linea, sin trazos sueltos que entren en la cabeza.
        canvas.drawPath(
          Path()
            ..moveTo(5.4, 10.2)
            ..lineTo(5.4, 4.6)
            ..quadraticBezierTo(5.5, 3.9, 6.2, 4.3)
            ..lineTo(9.6, 6.9)
            ..quadraticBezierTo(12, 6.2, 14.4, 6.9)
            ..lineTo(17.8, 4.3)
            ..quadraticBezierTo(18.5, 3.9, 18.6, 4.6)
            ..lineTo(18.6, 10.2)
            ..cubicTo(20.2, 13, 20.2, 20.2, 12, 20.2)
            ..cubicTo(3.8, 20.2, 3.8, 13, 5.4, 10.2)
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(9.3, 13.6), 1.25, fill);
        canvas.drawCircle(const Offset(14.7, 13.6), 1.25, fill);
      case Glyph.undo:
        canvas.drawPath(
          Path()
            ..moveTo(8.2, 13.6)
            ..lineTo(15, 13.6)
            ..cubicTo(18, 13.6, 20, 15.6, 20, 18.2)
            ..cubicTo(20, 20, 19.4, 20.4, 19.4, 20.4),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(11.6, 9.6)
            ..lineTo(7.4, 13.6)
            ..lineTo(11.6, 17.6),
          stroke,
        );
      case Glyph.heart:
        canvas.drawPath(
          Path()
            ..moveTo(12, 19.6)
            ..cubicTo(5, 15, 3.4, 11.4, 3.4, 9)
            ..cubicTo(3.4, 6.2, 5.6, 4.4, 7.9, 4.4)
            ..cubicTo(9.8, 4.4, 11.2, 5.6, 12, 7.2)
            ..cubicTo(12.8, 5.6, 14.2, 4.4, 16.1, 4.4)
            ..cubicTo(18.4, 4.4, 20.6, 6.2, 20.6, 9)
            ..cubicTo(20.6, 11.4, 19, 15, 12, 19.6)
            ..close(),
          stroke,
        );
      case Glyph.treat:
        // Un caramelo envuelto: el centro y los dos lazos se tocan, no se cruzan.
        canvas.drawOval(const Rect.fromLTWH(7.4, 8, 9.2, 8), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(7.4, 12)
            ..lineTo(3.2, 8.4)
            ..quadraticBezierTo(4.4, 12, 3.2, 15.6)
            ..close(),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16.6, 12)
            ..lineTo(20.8, 8.4)
            ..quadraticBezierTo(19.6, 12, 20.8, 15.6)
            ..close(),
          stroke,
        );
        canvas.drawCircle(const Offset(10.6, 10.6), .95, fill);
      case Glyph.pencil:
        canvas.drawPath(
          Path()
            ..moveTo(5, 19)
            ..lineTo(5.8, 15.2)
            ..lineTo(15.8, 5.2)
            ..cubicTo(16.8, 4.2, 18.4, 4.2, 19.4, 5.2)
            ..cubicTo(20.4, 6.2, 20.4, 7.8, 19.4, 8.8)
            ..lineTo(9.4, 18.8)
            ..close(),
          stroke,
        );
        canvas.drawLine(const Offset(14, 7), const Offset(17.6, 10.6), stroke);
      case Glyph.eraser:
        // Una goma inclinada: el cuerpo y la franja de la punta, y la raya
        // de suelo donde borra.
        canvas.drawPath(
          Path()
            ..moveTo(9.2, 18)
            ..lineTo(4.6, 13.4)
            ..cubicTo(4, 12.8, 4, 11.8, 4.6, 11.2)
            ..lineTo(12.4, 3.4)
            ..cubicTo(13, 2.8, 14, 2.8, 14.6, 3.4)
            ..lineTo(19.8, 8.6)
            ..cubicTo(20.4, 9.2, 20.4, 10.2, 19.8, 10.8)
            ..lineTo(12.6, 18)
            ..close(),
          stroke,
        );
        canvas.drawLine(const Offset(8.2, 7.6), const Offset(15.6, 15), stroke);
        canvas.drawLine(const Offset(9.2, 18), const Offset(20, 18), stroke);
      case Glyph.portrait:
        // Mini perfil: un marco redondeado con una persona dentro. Los hombros
        // se apoyan en el borde de abajo del marco en vez de atravesarlo.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(4, 3.6, 16, 16.8), const Radius.circular(4.4)),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 10), 2.9, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(7.2, 20.4)
            ..cubicTo(7.4, 16.8, 9.4, 15.4, 12, 15.4)
            ..cubicTo(14.6, 15.4, 16.6, 16.8, 16.8, 20.4),
          stroke,
        );
      case Glyph.trash:
        canvas.drawLine(const Offset(4.6, 6.8), const Offset(19.4, 6.8), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(9.4, 6.8)
            ..lineTo(9.8, 4.2)
            ..lineTo(14.2, 4.2)
            ..lineTo(14.6, 6.8),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6.4, 6.8)
            ..lineTo(7.4, 19.2)
            ..cubicTo(7.5, 19.9, 8, 20.4, 8.7, 20.4)
            ..lineTo(15.3, 20.4)
            ..cubicTo(16, 20.4, 16.5, 19.9, 16.6, 19.2)
            ..lineTo(17.6, 6.8),
          stroke,
        );
        canvas.drawLine(const Offset(10.4, 10.4), const Offset(10.6, 16.8), stroke);
        canvas.drawLine(const Offset(13.6, 10.4), const Offset(13.4, 16.8), stroke);
      case Glyph.wave:
        // Onda de sonido: escuchar la voz.
        canvas.drawPath(
          Path()
            ..moveTo(3.4, 12)
            ..quadraticBezierTo(5.4, 5.2, 7.4, 12)
            ..quadraticBezierTo(9.4, 18.8, 11.4, 12)
            ..quadraticBezierTo(13.2, 3.4, 15.2, 12)
            ..quadraticBezierTo(17.2, 16.6, 19, 12)
            ..quadraticBezierTo(19.8, 10.2, 20.6, 12),
          stroke,
        );
      case Glyph.friends:
        // Dos personas: la de delante entera, la de detras asoma por la
        // derecha. Cabezas y hombros no se tocan.
        canvas.drawCircle(const Offset(9, 9.4), 3.3, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(3.2, 20)
            ..cubicTo(3.2, 16.4, 5.8, 14.8, 9, 14.8)
            ..cubicTo(12.2, 14.8, 14.8, 16.4, 14.8, 20),
          stroke,
        );
        canvas.drawCircle(const Offset(16.6, 7.2), 2.6, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(15.2, 12.2)
            ..cubicTo(15.7, 12, 16.1, 12, 16.6, 12)
            ..cubicTo(19, 12, 20.8, 13.4, 20.8, 16.6),
          stroke,
        );
      case Glyph.personPlus:
        canvas.drawCircle(const Offset(9.4, 8.6), 3.5, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(3.4, 20)
            ..cubicTo(3.4, 16, 6.2, 14.4, 9.4, 14.4)
            ..cubicTo(12.6, 14.4, 15.4, 16, 15.4, 20),
          stroke,
        );
        canvas.drawLine(const Offset(18.4, 6.2), const Offset(18.4, 12.2), stroke);
        canvas.drawLine(const Offset(15.4, 9.2), const Offset(21.2, 9.2), stroke);
      case Glyph.speakerOff:
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
        canvas.drawLine(const Offset(15.6, 9.4), const Offset(20.4, 14.6), stroke);
        canvas.drawLine(const Offset(20.4, 9.4), const Offset(15.6, 14.6), stroke);
      case Glyph.download:
        canvas.drawLine(const Offset(12, 3.8), const Offset(12, 14), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(7.8, 10)
            ..lineTo(12, 14.2)
            ..lineTo(16.2, 10),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(4, 15)
            ..lineTo(4, 18.2)
            ..cubicTo(4, 19.4, 4.9, 20.4, 6.1, 20.4)
            ..lineTo(17.9, 20.4)
            ..cubicTo(19.1, 20.4, 20, 19.4, 20, 18.2)
            ..lineTo(20, 15),
          stroke,
        );
      case Glyph.paste:
        // Portapapeles: la pinza se une al tablero por sus extremos.
        canvas.drawPath(
          Path()
            ..moveTo(8.6, 5.4)
            ..lineTo(7.6, 5.4)
            ..cubicTo(6.2, 5.4, 5, 6.6, 5, 8)
            ..lineTo(5, 18.2)
            ..cubicTo(5, 19.6, 6.2, 20.8, 7.6, 20.8)
            ..lineTo(16.4, 20.8)
            ..cubicTo(17.8, 20.8, 19, 19.6, 19, 18.2)
            ..lineTo(19, 8)
            ..cubicTo(19, 6.6, 17.8, 5.4, 16.4, 5.4)
            ..lineTo(15.4, 5.4),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(8.6, 3.4, 6.8, 4), const Radius.circular(1.4)),
          stroke,
        );
        canvas.drawLine(const Offset(8.8, 12), const Offset(15.2, 12), stroke);
        canvas.drawLine(const Offset(8.8, 15.6), const Offset(13, 15.6), stroke);
      case Glyph.star:
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final angle = -math.pi / 2 + i * math.pi / 5;
          final radius = i.isEven ? 8.6 : 3.9;
          final point = Offset(12 + radius * math.cos(angle), 12.8 + radius * math.sin(angle));
          i == 0 ? star.moveTo(point.dx, point.dy) : star.lineTo(point.dx, point.dy);
        }
        star.close();
        canvas.drawPath(star, stroke);
      case Glyph.send:
        // Avion de papel.
        canvas.drawPath(
          Path()
            ..moveTo(3.6, 11.4)
            ..lineTo(20.2, 4)
            ..lineTo(14.6, 20.2)
            ..lineTo(11.2, 13)
            ..close(),
          stroke,
        );
        canvas.drawLine(const Offset(11.2, 13), const Offset(20.2, 4), stroke);
      case Glyph.news:
        // Tablon: el marco, el recuadro de la foto y tres renglones.
        canvas.drawRRect(
          RRect.fromLTRBR(3.2, 5, 20.8, 19, const Radius.circular(2.2)),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromLTRBR(5.8, 8, 11.4, 12.6, const Radius.circular(1)),
          stroke,
        );
        for (final y in const <double>[8.6, 10.8]) {
          canvas.drawLine(Offset(13.4, y), Offset(18.4, y), stroke);
        }
        for (final y in const <double>[15, 16.8]) {
          canvas.drawLine(Offset(5.8, y), Offset(18.4, y), stroke);
        }
      case Glyph.chat:
        // Bocadillo con el rabito abajo a la izquierda.
        canvas.drawPath(
          Path()
            ..moveTo(6.2, 4.4)
            ..lineTo(17.8, 4.4)
            ..arcToPoint(const Offset(20.8, 7.4),
                radius: const Radius.circular(3))
            ..lineTo(20.8, 13.6)
            ..arcToPoint(const Offset(17.8, 16.6),
                radius: const Radius.circular(3))
            ..lineTo(10.4, 16.6)
            ..lineTo(6.6, 20.4)
            ..lineTo(6.6, 16.6)
            ..arcToPoint(const Offset(3.2, 13.6),
                radius: const Radius.circular(3))
            ..lineTo(3.2, 7.4)
            ..arcToPoint(const Offset(6.2, 4.4),
                radius: const Radius.circular(3))
            ..close(),
          stroke,
        );
      case Glyph.bulb:
        // Bombilla: la idea. El casquillo son dos renglones cortos.
        canvas.drawCircle(const Offset(12, 9.6), 5.2, stroke);
        canvas.drawLine(const Offset(9.6, 14.2), const Offset(9.6, 16.4), stroke);
        canvas.drawLine(const Offset(14.4, 14.2), const Offset(14.4, 16.4), stroke);
        canvas.drawLine(const Offset(9.4, 17.2), const Offset(14.6, 17.2), stroke);
        canvas.drawLine(const Offset(10.4, 19.6), const Offset(13.6, 19.6), stroke);
      case Glyph.coin:
        // Moneda de canto: dos circulos concentricos y nada mas, para que se
        // lea a 16 pixeles en la barra de estado.
        canvas.drawCircle(const Offset(12, 12), 8.2, stroke);
        canvas.drawCircle(const Offset(12, 12), 4.4, stroke);
      case Glyph.mine:
        // La mina del buscaminas: un cuerpo redondo con pinchos que nacen en
        // su borde (como las patas del bicho) y una mecha que remata en una
        // chispa en forma de aspa.
        const centre = Offset(12, 13.4);
        const radius = 5.6;
        canvas.drawCircle(centre, radius, stroke);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final dir = Offset(math.cos(angle), math.sin(angle));
          canvas.drawLine(centre + dir * radius, centre + dir * (radius + 2.1), stroke);
        }
        const fuseAngle = -2.15;
        final fuseStart =
            centre + Offset(math.cos(fuseAngle), math.sin(fuseAngle)) * radius;
        final spark = fuseStart + const Offset(2.9, -4.1);
        canvas.drawPath(
          Path()
            ..moveTo(fuseStart.dx, fuseStart.dy)
            ..quadraticBezierTo(fuseStart.dx + 2.4, fuseStart.dy - 3.4, spark.dx, spark.dy),
          stroke,
        );
        canvas.drawLine(spark + const Offset(-1.3, -1.3), spark + const Offset(1.3, 1.3), stroke);
        canvas.drawLine(spark + const Offset(-1.3, 1.3), spark + const Offset(1.3, -1.3), stroke);
      case Glyph.blocks:
        // Una pieza T de Tsumiki: tres bloques arriba y uno debajo, en un
        // solo contorno redondeado.
        canvas.drawPath(
          Path()
            ..moveTo(3.4, 6.6)
            ..lineTo(20.6, 6.6)
            ..lineTo(20.6, 12.4)
            ..lineTo(14.9, 12.4)
            ..lineTo(14.9, 18.2)
            ..lineTo(9.1, 18.2)
            ..lineTo(9.1, 12.4)
            ..lineTo(3.4, 12.4)
            ..close(),
          stroke,
        );
      case Glyph.pause:
        // Dos barras con aire entre medias.
        canvas.drawLine(const Offset(8.6, 6), const Offset(8.6, 18), stroke);
        canvas.drawLine(const Offset(15.4, 6), const Offset(15.4, 18), stroke);
      case Glyph.kana:
        // La «ア» de katakana: el trazo de arriba con su gancho y, con aire
        // de por medio, la caida hacia la izquierda.
        canvas.drawPath(
          Path()
            ..moveTo(4.4, 5.6)
            ..lineTo(19.4, 5.6)
            ..quadraticBezierTo(18, 9.6, 14.2, 11.6),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(10.6, 10.4)
            ..quadraticBezierTo(10.8, 16.4, 5.6, 19.6),
          stroke,
        );
      case Glyph.yatai:
        // El puesto del Yatai: dos postes y un toldo a rayas en un solo
        // trazo, y el farolillo colgando por separado, con aire de por medio.
        canvas.drawPath(
          Path()
            ..moveTo(3.2, 17.2)
            ..lineTo(3.2, 6.4)
            ..lineTo(6.4, 9.6)
            ..lineTo(9.6, 6.4)
            ..lineTo(12, 9.6)
            ..lineTo(14.4, 6.4)
            ..lineTo(17.6, 9.6)
            ..lineTo(20.8, 6.4)
            ..lineTo(20.8, 17.2)
            ..lineTo(3.2, 17.2),
          stroke,
        );
        canvas.drawLine(const Offset(12, 9.9), const Offset(12, 10.4), stroke);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(12, 13.4), width: 5, height: 5.6),
          stroke,
        );
        canvas.drawLine(const Offset(10.1, 13.4), const Offset(13.9, 13.4), stroke);
      case Glyph.gift:
        // Un regalo envuelto: la caja, el lazo vertical que la cruza de canto
        // a canto y el moño arriba, sin tocarla.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              const Rect.fromLTWH(4, 10, 16, 10), const Radius.circular(2.4)),
          stroke,
        );
        canvas.drawLine(const Offset(12, 10), const Offset(12, 20), stroke);
        canvas.drawLine(const Offset(4, 15), const Offset(11, 15), stroke);
        canvas.drawLine(const Offset(13, 15), const Offset(20, 15), stroke);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(9, 7.4), width: 4, height: 3.6),
          stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(15, 7.4), width: 4, height: 3.6),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 7.8), 1, stroke);
      case Glyph.trophy:
        // Trofeo: la copa, sus dos asas naciendo del borde y el pie con la
        // base, todo con aire entre cada pieza salvo donde se tocan.
        canvas.drawPath(
          Path()
            ..moveTo(7.2, 4.6)
            ..lineTo(16.8, 4.6)
            ..lineTo(16.2, 11.2)
            ..cubicTo(16.2, 14.4, 13.9, 16.2, 12, 16.2)
            ..cubicTo(10.1, 16.2, 7.8, 14.4, 7.8, 11.2)
            ..close(),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(7.6, 6.6)
            ..cubicTo(3.6, 6.6, 3.6, 12, 7.8, 11.4),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(16.4, 6.6)
            ..cubicTo(20.4, 6.6, 20.4, 12, 16.2, 11.4),
          stroke,
        );
        canvas.drawLine(const Offset(12, 16.2), const Offset(12, 18.6), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(8.2, 19.6)
            ..lineTo(9.2, 18.6)
            ..lineTo(14.8, 18.6)
            ..lineTo(15.8, 19.6)
            ..close(),
          stroke,
        );
      case Glyph.flag:
        // El mastil de arriba abajo y el banderin, en un solo contorno que
        // nace y muere en el mismo mastil.
        canvas.drawLine(const Offset(6.4, 20.4), const Offset(6.4, 4.2), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(6.4, 5)
            ..lineTo(18, 5)
            ..lineTo(14, 9.2)
            ..lineTo(18, 13.4)
            ..lineTo(6.4, 13.4),
          stroke,
        );
    }

    canvas.restore();
    if (layered) canvas.restore();
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

  /// Engranaje en un solo contorno: los dientes son parte del borde, no
  /// lineas que atraviesan un aro.
  void _gear(Canvas canvas, Paint stroke, Paint fill) {
    const teeth = 8;
    const outer = 9.6;
    const inner = 7.3;
    const centre = Offset(12, 12);
    Offset at(double angle, double radius) =>
        centre + Offset(math.cos(angle), math.sin(angle)) * radius;

    final step = 2 * math.pi / teeth;
    final path = Path();
    for (var i = 0; i < teeth; i++) {
      final mid = -math.pi / 2 + i * step;
      // Diente: base ancha en el aro, punta algo mas estrecha.
      final baseA = mid - step * .26;
      final baseB = mid + step * .26;
      final tipA = mid - step * .17;
      final tipB = mid + step * .17;
      final start = at(baseA, inner);
      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.arcToPoint(start, radius: const Radius.circular(inner));
      }
      final p1 = at(tipA, outer);
      final p2 = at(tipB, outer);
      final p3 = at(baseB, inner);
      path
        ..lineTo(p1.dx, p1.dy)
        ..arcToPoint(p2, radius: const Radius.circular(outer))
        ..lineTo(p3.dx, p3.dy);
    }
    final first = at(-math.pi / 2 - step * .26, inner);
    path
      ..arcToPoint(first, radius: const Radius.circular(inner))
      ..close();
    canvas.drawPath(path, stroke);
    canvas.drawCircle(centre, 3, stroke);
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
