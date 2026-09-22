// Ibasho — iconos ilustrados: el Yatai, los juegos, el gacha y la moneda.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';

/// Las ilustraciones a color del entorno.
///
/// Los canales del sistema llevan un [Glyph] de linea blanca; lo que se
/// compra o se juega (el Yatai, cada juego, el gacha) lleva una pieza pintada,
/// como los iconos de la 3DS o los canales de la Wii: volumen, brillo y un
/// filo del mismo tono oscurecido, nunca negro.
///
/// Todas se dibujan sobre una caja de 100x100 y se escalan. Los colores son
/// los suyos, no el acento: un icono ilustrado se ve igual con cualquier
/// acento, como el regalo.
enum ArtIcon { yatai, minesweeper, gacha, coin, medalBronze, medalSilver, medalGold, calendar }

class ArtIconView extends StatelessWidget {
  const ArtIconView(this.icon, {super.key, this.size = 64});

  final ArtIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: ArtPainter(icon)),
      );
}

class ArtPainter extends CustomPainter {
  const ArtPainter(this.icon);

  final ArtIcon icon;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * s) / 2, (size.height - 100 * s) / 2);
    canvas.scale(s);
    switch (icon) {
      case ArtIcon.yatai:
        paintYatai(canvas);
      case ArtIcon.minesweeper:
        paintMinesweeper(canvas);
      case ArtIcon.gacha:
        paintGacha(canvas);
      case ArtIcon.coin:
        paintCoin(canvas, const Offset(50, 50), 40);
      case ArtIcon.medalBronze:
        paintMedal(canvas, Art.bronze);
      case ArtIcon.medalSilver:
        paintMedal(canvas, Art.silver);
      case ArtIcon.medalGold:
        paintMedal(canvas, Art.gold);
      case ArtIcon.calendar:
        paintCalendar(canvas);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ArtPainter old) => old.icon != icon;
}

/// Colores propios de las ilustraciones. Viven aqui y no en [T] porque solo
/// los usan estas piezas pintadas; ningun control del entorno los toca.
abstract final class Art {
  static const Color woodLight = Color(0xFFF2C98E);
  static const Color wood = Color(0xFFD99A5B);
  static const Color woodDark = Color(0xFF9A5E2E);
  static const Color awningRed = Color(0xFFF2636E);
  static const Color awningRedDark = Color(0xFFC23B4B);
  static const Color awningCream = Color(0xFFFFF7EC);
  static const Color lantern = Color(0xFFFF7A59);
  static const Color lanternGlow = Color(0x66FFB35C);
  static const Color lanternCap = Color(0xFF3A4750);

  static const Color bombTop = Color(0xFF5B6B79);
  static const Color bomb = Color(0xFF2E3943);
  static const Color bombEdge = Color(0xFF161D23);
  static const Color fuse = Color(0xFFCFB38A);
  static const Color spark = Color(0xFFFFD25A);
  static const Color sparkHot = Color(0xFFFF8A3D);
  static const Color flagRed = Color(0xFFF2545F);
  static const Color flagRedDark = Color(0xFFB8303D);
  static const Color pole = Color(0xFF8E9AA6);

  static const Color gachaBody = Color(0xFFF2636E);
  static const Color gachaBodyDark = Color(0xFFB9303F);
  static const Color glass = Color(0x55CFEFFF);
  static const Color glassEdge = Color(0xFF8FC9E6);
  static const Color chrome = Color(0xFFF4F7FA);
  static const Color chromeDark = Color(0xFFA9B6C1);

  static const Color gold = Color(0xFFFFCB45);
  static const Color goldDark = Color(0xFFC98A12);
  static const Color silver = Color(0xFFDCE4EB);
  static const Color silverDark = Color(0xFF8A99A6);
  static const Color bronze = Color(0xFFF0A866);
  static const Color bronzeDark = Color(0xFFA85F25);
  static const Color ribbonBlue = Color(0xFF5BC8F5);
  static const Color ribbonBlueDark = Color(0xFF2A8FC4);

  static const List<Color> capsules = <Color>[
    Color(0xFF5BC8F5),
    Color(0xFFFFD25A),
    Color(0xFF74DDA2),
    Color(0xFFF47AA6),
    Color(0xFFB08BE0),
    Color(0xFFF79A68),
  ];

  /// Oscurece hacia el azul noche de la casa, nunca hacia el negro.
  static Color deep(Color c, [double t = .4]) => Color.lerp(c, T.dusk, t)!;

  /// Aclara hacia el blanco.
  static Color light(Color c, [double t = .45]) => Color.lerp(c, T.shellTop, t)!;
}

// --- Utilidades de pintura ------------------------------------------------------

Paint _vertical(Rect r, List<Color> colors, [List<double>? stops]) => Paint()
  ..shader = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: colors,
    stops: stops,
  ).createShader(r);

Paint _edge(Color c, [double w = 2.4]) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round
  ..color = c;

/// Una pieza de plastico: degradado claro-base-oscuro, brillo en la parte de
/// arriba recortado por la forma y filo oscurecido.
void paintPlastic(Canvas canvas, Path path, Color base, {double edge = 2.4, double shine = 1}) {
  final r = path.getBounds();
  canvas.drawPath(path, _vertical(r, [Art.light(base, .35), base, Art.deep(base, .18)], const [0, .55, 1]));
  if (shine > 0) {
    canvas.save();
    canvas.clipPath(path);
    final h = Rect.fromLTWH(r.left + r.width * .08, r.top + r.height * .04, r.width * .84, r.height * .42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(h, Radius.circular(h.height / 2)),
      _vertical(h, [
        Color.fromRGBO(255, 255, 255, .7 * shine),
        Color.fromRGBO(255, 255, 255, .05 * shine),
      ]),
    );
    canvas.restore();
  }
  if (edge > 0) canvas.drawPath(path, _edge(Art.deep(base, .45), edge));
}

/// Sombra de contacto: una elipse difuminada bajo la pieza.
void paintGroundShadow(Canvas canvas, Offset centre, double width, [double alpha = .22]) {
  canvas.drawOval(
    Rect.fromCenter(center: centre, width: width, height: width * .22),
    Paint()
      ..color = T.dusk.withValues(alpha: alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
  );
}

/// Destello de cuatro puntas.
void paintTwinkle(Canvas canvas, Offset c, double r, Color color) {
  final p = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(p, Paint()..color = color);
}

Path _star(Offset c, double outer, double inner, [int points = 5, double rot = -math.pi / 2]) {
  final p = Path();
  for (var i = 0; i < points * 2; i++) {
    final r = i.isEven ? outer : inner;
    final a = rot + i * math.pi / points;
    final q = c + Offset(math.cos(a), math.sin(a)) * r;
    i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
  }
  return p..close();
}

// --- El Yatai -------------------------------------------------------------------

/// Un puesto de feria de frente: toldo a rayas con festón, dos postes, el
/// mostrador de madera con dango y caramelos encima y un farolillo encendido.
void paintYatai(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(50, 90), 84);

  // Postes, por detras del toldo y del mostrador.
  for (final x in [19.0, 81.0]) {
    final post = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 3.2, 30, 6.4, 40), const Radius.circular(2)));
    paintPlastic(canvas, post, Art.wood, edge: 1.6, shine: 0);
  }

  // Fondo del puesto: una cortina noren entre los postes.
  final noren = Path()
    ..moveTo(22, 40)
    ..lineTo(78, 40)
    ..lineTo(78, 58)
    ..lineTo(22, 58)
    ..close();
  canvas.drawPath(noren, _vertical(noren.getBounds(), [const Color(0xFF3F6FA8), const Color(0xFF2D5486)]));
  for (final x in [36.0, 50.0, 64.0]) {
    canvas.drawLine(Offset(x, 44), Offset(x, 58), _edge(const Color(0xFF24466F), 1.4));
  }
  // El emblema del noren: un circulo claro.
  canvas.drawCircle(const Offset(50, 47.5), 4.2, Paint()..color = const Color(0xCCFFF7EC));

  // El toldo: un trapecio a rayas con el borde de abajo en festones.
  const top = 14.0;
  const bottom = 34.0;
  final awning = Path()..moveTo(18, top);
  awning
    ..lineTo(82, top)
    ..lineTo(92, bottom);
  const scallops = 6;
  const sw = 84 / scallops;
  // Los festones, de derecha a izquierda: cada arco cuelga hacia abajo.
  for (var i = scallops - 1; i >= 0; i--) {
    awning.arcToPoint(Offset(8 + sw * i, bottom), radius: const Radius.circular(sw / 2));
  }
  awning
    ..lineTo(18, top)
    ..close();
  final ab = awning.getBounds().inflate(6);
  canvas.save();
  canvas.clipPath(awning);
  canvas.drawRect(ab, Paint()..color = Art.awningCream);
  for (var i = 0; i < scallops; i++) {
    if (i.isOdd) continue;
    // Cada franja roja sigue la inclinacion del trapecio.
    final xb0 = 8 + sw * i;
    final xb1 = xb0 + sw;
    final xt0 = 18 + (64 / scallops) * i;
    final xt1 = xt0 + 64 / scallops;
    canvas.drawPath(
      Path()
        ..moveTo(xt0, top - 2)
        ..lineTo(xt1, top - 2)
        ..lineTo(xb1, bottom + 8)
        ..lineTo(xb0, bottom + 8)
        ..close(),
      Paint()..color = Art.awningRed,
    );
  }
  // Sombreado y brillo del toldo.
  canvas.drawRect(
    ab,
    _vertical(ab, [const Color(0x55FFFFFF), const Color(0x00FFFFFF), const Color(0x22000000)], const [0, .45, 1]),
  );
  canvas.restore();
  canvas.drawPath(awning, _edge(Art.awningRedDark, 2.2));
  // Remate del tejado.
  final ridge = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(15, 9.5, 70, 6.5), const Radius.circular(3.2)));
  paintPlastic(canvas, ridge, Art.woodDark, edge: 1.6);

  // Mostrador.
  final counter = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 62, 80, 24), const Radius.circular(6)));
  paintPlastic(canvas, counter, Art.wood, edge: 2.2, shine: .6);
  final plank = _edge(Art.deep(Art.wood, .22), 1.2);
  canvas.drawLine(const Offset(14, 75), const Offset(86, 75), plank);
  canvas.drawLine(const Offset(38, 75), const Offset(38, 85), plank);
  canvas.drawLine(const Offset(64, 66), const Offset(64, 75), plank);
  // Tablero del mostrador, mas claro.
  final lip = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(7, 58, 86, 7), const Radius.circular(3.5)));
  paintPlastic(canvas, lip, Art.woodLight, edge: 1.8);

  // Encima: una brocheta de dango y un tarro de caramelos.
  canvas.drawLine(const Offset(30, 58), const Offset(38, 42), _edge(Art.woodDark, 1.6));
  for (final (c, col) in [
    (const Offset(36.8, 44.6), T.foodDangoPink),
    (const Offset(34.2, 49.6), T.foodDangoWhite),
    (const Offset(31.8, 54.4), T.foodDangoGreen),
  ]) {
    paintPlastic(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: 3.6)), col, edge: 1.1);
  }
  final jar = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(56, 45, 14, 13.5), const Radius.circular(4)));
  canvas.drawPath(jar, Paint()..color = const Color(0x66DFF4FF));
  for (final (c, col) in [
    (const Offset(60, 54.5), Art.capsules[1]),
    (const Offset(65.5, 54.8), Art.capsules[3]),
    (const Offset(62.6, 50.2), Art.capsules[0]),
  ]) {
    canvas.drawCircle(c, 2.6, Paint()..color = col);
  }
  canvas.drawPath(jar, _edge(Art.glassEdge, 1.3));
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(57.5, 42.4, 11, 3.4), const Radius.circular(1.7)),
      Paint()..color = Art.awningRed);

  // El farolillo, colgando del poste derecho, con su halo.
  canvas.drawCircle(const Offset(81, 45), 11, Paint()
    ..color = Art.lanternGlow
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  canvas.drawLine(const Offset(81, 34), const Offset(81, 37.5), _edge(Art.lanternCap, 1.3));
  final lantern = Path()..addOval(Rect.fromCenter(center: const Offset(81, 45), width: 12, height: 14));
  paintPlastic(canvas, lantern, Art.lantern, edge: 1.4);
  for (final dy in [-3.0, 0.0, 3.0]) {
    canvas.drawLine(Offset(76, 45 + dy), Offset(86, 45 + dy), _edge(Art.deep(Art.lantern, .25), .8));
  }
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(81, 38.4), width: 7, height: 2.2), const Radius.circular(1)),
      Paint()..color = Art.lanternCap);
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(81, 51.6), width: 7, height: 2.2), const Radius.circular(1)),
      Paint()..color = Art.lanternCap);
}

// --- El buscaminas ----------------------------------------------------------------

/// La mina simpatica del buscaminas: una bola lacada con pinchos redondos, la
/// mecha encendida y carita; delante, una banderita clavada en una baldosa.
void paintMinesweeper(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(46, 88), 64);
  paintBomb(canvas, const Offset(44, 54), 27, face: true, spark: 1);
  // Baldosa con la bandera, delante a la derecha.
  final tile = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(62, 68, 28, 22), const Radius.circular(6)));
  paintPlastic(canvas, tile, T.shellBottom, edge: 1.8);
  paintFlag(canvas, const Offset(73, 80), 26, wave: 0);
}

/// La mina: se usa en el icono y en el tablero. [spark] enciende la chispa.
void paintBomb(Canvas canvas, Offset c, double r, {bool face = false, double spark = 0, double glow = 0}) {
  if (glow > 0) {
    canvas.drawCircle(c, r * 1.6, Paint()
      ..color = Art.sparkHot.withValues(alpha: .35 * glow)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .5));
  }
  // Pinchos: bultos redondos que asoman del cuerpo.
  for (var i = 0; i < 8; i++) {
    final a = i * math.pi / 4 + math.pi / 8;
    final dir = Offset(math.cos(a), math.sin(a));
    final knob = Path()..addOval(Rect.fromCircle(center: c + dir * r * .98, radius: r * .2));
    paintPlastic(canvas, knob, Art.bombTop, edge: r * .05, shine: .4);
  }
  final body = Path()..addOval(Rect.fromCircle(center: c, radius: r));
  final br = body.getBounds();
  canvas.drawPath(
    body,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-.35, -.45),
        radius: .95,
        colors: [Art.bombTop, Art.bomb, Art.bombEdge],
        stops: const [0, .6, 1],
      ).createShader(br),
  );
  // Brillo especular grande y uno pequeño.
  canvas.save();
  canvas.clipPath(body);
  final hl = Rect.fromCenter(center: c + Offset(-r * .28, -r * .42), width: r * .95, height: r * .55);
  canvas.drawOval(hl, _vertical(hl, [const Color(0xCCFFFFFF), const Color(0x10FFFFFF)]));
  canvas.restore();
  canvas.drawCircle(c + Offset(r * .45, -r * .1), r * .07, Paint()..color = const Color(0x88FFFFFF));
  canvas.drawPath(body, _edge(Art.bombEdge, r * .07));

  // Boquilla y mecha.
  final neck = c + Offset(r * .5, -r * .78);
  final cap = Path()
    ..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: neck, width: r * .5, height: r * .34), Radius.circular(r * .1)));
  canvas.save();
  canvas.translate(neck.dx, neck.dy);
  canvas.rotate(.55);
  canvas.translate(-neck.dx, -neck.dy);
  paintPlastic(canvas, cap, Art.pole, edge: r * .05);
  canvas.restore();
  final fuseEnd = neck + Offset(r * .45, -r * .5);
  canvas.drawPath(
    Path()
      ..moveTo(neck.dx + r * .08, neck.dy - r * .1)
      ..quadraticBezierTo(neck.dx + r * .12, neck.dy - r * .6, fuseEnd.dx, fuseEnd.dy),
    _edge(Art.fuse, r * .1),
  );
  if (spark > 0) {
    canvas.drawCircle(fuseEnd, r * .34 * spark, Paint()
      ..color = Art.sparkHot.withValues(alpha: .45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .14));
    canvas.drawPath(_star(fuseEnd, r * .3 * spark, r * .12 * spark, 6), Paint()..color = Art.spark);
    canvas.drawCircle(fuseEnd, r * .07 * spark, Paint()..color = T.shellTop);
  }

  if (face) {
    final ink = Paint()..color = T.shellTop;
    final eyeY = c.dy + r * .05;
    for (final dx in [-r * .3, r * .22]) {
      final eye = Rect.fromCenter(center: Offset(c.dx + dx, eyeY), width: r * .2, height: r * .28);
      canvas.drawOval(eye, ink);
    }
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r * .14, eyeY + r * .26)
        ..quadraticBezierTo(c.dx - r * .04, eyeY + r * .36, c.dx + r * .06, eyeY + r * .26),
      _edge(T.shellTop, r * .06),
    );
    final blush = Paint()..color = T.tamaBlush.withValues(alpha: .55);
    canvas.drawOval(Rect.fromCenter(center: Offset(c.dx - r * .54, eyeY + r * .22), width: r * .22, height: r * .12), blush);
    canvas.drawOval(Rect.fromCenter(center: Offset(c.dx + r * .46, eyeY + r * .22), width: r * .22, height: r * .12), blush);
  }
}

/// Una bandera clavada: mastil de metal con pomo, banderin rojo con brillo y
/// una pequeña base. [base] es el pie del mastil y [h] la altura total.
/// [wave] (-1 a 1) ondea el banderin.
void paintFlag(Canvas canvas, Offset base, double h, {double wave = 0, bool muted = false}) {
  final u = h / 26;
  final red = muted ? Art.deep(Art.flagRed, .1) : Art.flagRed;
  // Peana.
  final foot = Path()..addOval(Rect.fromCenter(center: base, width: 12 * u, height: 4.4 * u));
  paintPlastic(canvas, foot, Art.chromeDark, edge: .9 * u, shine: .6);
  // Mastil.
  final top = base.translate(-2.2 * u, -22 * u);
  canvas.drawLine(base.translate(0, -1 * u), top, _edge(Art.deep(Art.pole, .35), 2.4 * u));
  canvas.drawLine(base.translate(-.4 * u, -1.5 * u), top.translate(-.3 * u, 1 * u), _edge(Art.chrome, .8 * u));
  // Banderin: triangulo con el borde exterior curvado segun el viento.
  final w = 14 * u;
  final flag = Path()
    ..moveTo(top.dx + .4 * u, top.dy + 1 * u)
    ..quadraticBezierTo(top.dx + w * .5, top.dy + (1.8 + wave * 2.2) * u, top.dx + w, top.dy + 6 * u)
    ..quadraticBezierTo(top.dx + w * .5, top.dy + (9.4 - wave * 2.2) * u, top.dx + .8 * u, top.dy + 11.5 * u)
    ..close();
  paintPlastic(canvas, flag, red, edge: 1.1 * u, shine: .9);
  // Pomo del mastil.
  paintPlastic(canvas, Path()..addOval(Rect.fromCircle(center: top, radius: 1.9 * u)), Art.gold, edge: .7 * u);
}

// --- El gacha -------------------------------------------------------------------

/// Una maquina de capsulas: cupula de cristal llena de capsulas de dos
/// colores, cuerpo rojo lacado, la rueda plateada y la boca de salida.
void paintGacha(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(50, 93), 66);

  // Patas.
  for (final x in [28.0, 72.0]) {
    paintPlastic(canvas, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 5, 84, 10, 8), const Radius.circular(3))),
        Art.gachaBodyDark, edge: 1.4, shine: 0);
  }
  // Cuerpo.
  final body = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 50, 60, 38), const Radius.circular(9)));
  paintPlastic(canvas, body, Art.gachaBody, edge: 2.2);
  // Anillo de la cupula.
  final ring = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16, 45, 68, 9), const Radius.circular(4.5)));
  paintPlastic(canvas, ring, Art.chrome, edge: 1.8);

  // Cupula de cristal con las capsulas dentro.
  const domeC = Offset(50, 29);
  const domeR = 25.0;
  final dome = Path()
    ..addArc(Rect.fromCircle(center: domeC, radius: domeR), math.pi * .98, math.pi * 1.04)
    ..lineTo(domeC.dx + domeR * .98, 46)
    ..lineTo(domeC.dx - domeR * .98, 46)
    ..close();
  canvas.save();
  canvas.clipPath(dome);
  canvas.drawPath(dome, Paint()..color = const Color(0xFFE9F7FF));
  const caps = <(double, double, int, double)>[
    (36, 39, 0, .4),
    (50, 41, 1, -.3),
    (64, 39, 2, .9),
    (43, 30, 3, 1.4),
    (58, 29, 4, -.8),
    (50, 19, 5, .2),
    (33, 25, 1, -1.2),
    (67, 24, 0, 2.1),
  ];
  for (final (x, y, ci, rot) in caps) {
    paintCapsule(canvas, Offset(x, y), 6.4, Art.capsules[ci], rot);
  }
  // Reflejos del cristal.
  canvas.drawPath(dome, _vertical(dome.getBounds(), [const Color(0x00FFFFFF), const Color(0x33BFE6FA)]));
  canvas.drawArc(Rect.fromCircle(center: domeC, radius: domeR - 5), math.pi * 1.12, math.pi * .32, false,
      _edge(const Color(0xDDFFFFFF), 3.4));
  canvas.drawCircle(const Offset(66, 16), 2, Paint()..color = const Color(0xCCFFFFFF));
  canvas.restore();
  canvas.drawPath(dome, _edge(Art.glassEdge, 2));
  // Tapa de la cupula.
  paintPlastic(canvas, Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(42, 1.5, 16, 6), const Radius.circular(3))),
      Art.gachaBody, edge: 1.4);

  // Rueda plateada.
  const knobC = Offset(38, 67);
  paintPlastic(canvas, Path()..addOval(Rect.fromCircle(center: knobC, radius: 10.5)), Art.chrome, edge: 1.8);
  final handle = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: knobC, width: 17, height: 5), const Radius.circular(2.5)));
  canvas.save();
  canvas.translate(knobC.dx, knobC.dy);
  canvas.rotate(-.5);
  canvas.translate(-knobC.dx, -knobC.dy);
  paintPlastic(canvas, handle, Art.chromeDark, edge: 1.2);
  canvas.restore();
  // Ranura de la moneda y boca de salida.
  canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(60, 57, 11, 3), const Radius.circular(1.5)), Paint()..color = Art.gachaBodyDark);
  final chute = RRect.fromRectAndRadius(const Rect.fromLTWH(56, 66, 19, 14), const Radius.circular(5));
  canvas.drawRRect(chute, _vertical(chute.outerRect, [Art.deep(Art.gachaBody, .55), Art.deep(Art.gachaBody, .3)]));
  canvas.drawRRect(chute, _edge(Art.deep(Art.gachaBody, .5), 1.4));
  paintCapsule(canvas, const Offset(65.5, 75), 5.2, Art.capsules[2], .3);
}

/// Una capsula de dos mitades: la de arriba de color, la de abajo blanca.
void paintCapsule(Canvas canvas, Offset c, double r, Color color, [double rotation = 0]) {
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(rotation);
  final rect = Rect.fromCircle(center: Offset.zero, radius: r);
  final top = Path()
    ..addArc(rect, math.pi, math.pi)
    ..close();
  final bottom = Path()
    ..addArc(rect, 0, math.pi)
    ..close();
  canvas.drawPath(bottom, _vertical(rect, [T.shellTop, T.shellBottom]));
  canvas.drawPath(top, _vertical(rect, [Art.light(color, .3), color]));
  canvas.drawLine(Offset(-r, 0), Offset(r, 0), _edge(Art.deep(color, .35), r * .12));
  canvas.drawOval(Rect.fromCenter(center: Offset(-r * .3, -r * .5), width: r * .7, height: r * .34), Paint()..color = const Color(0xAAFFFFFF));
  canvas.drawCircle(Offset.zero, r, _edge(Art.deep(color, .45), r * .14));
  canvas.restore();
}

// --- Moneda, medallas y calendario ----------------------------------------------

/// La moneda de Ibasho: oro con canto, un borde de puntitos y una estrella en
/// relieve.
void paintCoin(Canvas canvas, Offset c, double r) {
  final rim = Path()..addOval(Rect.fromCircle(center: c.translate(0, r * .06), radius: r));
  canvas.drawPath(rim, Paint()..color = Art.goldDark);
  final face = Path()..addOval(Rect.fromCircle(center: c, radius: r * .96));
  paintPlastic(canvas, face, Art.gold, edge: r * .06, shine: .8);
  canvas.drawCircle(c, r * .72, _edge(Art.deep(Art.gold, .22), r * .06));
  final star = _star(c.translate(0, r * .03), r * .44, r * .2);
  canvas.drawPath(star.shift(Offset(0, r * .04)), Paint()..color = Art.deep(Art.gold, .3));
  canvas.drawPath(star, _vertical(star.getBounds(), [const Color(0xFFFFF1B8), Art.gold]));
}

void paintMedal(Canvas canvas, Color metal) {
  final dark = metal == Art.gold
      ? Art.goldDark
      : metal == Art.silver
          ? Art.silverDark
          : Art.bronzeDark;
  // Cinta en V.
  for (final side in [-1.0, 1.0]) {
    final ribbon = Path()
      ..moveTo(50 + side * 4, 8)
      ..lineTo(50 + side * 22, 8)
      ..lineTo(50 + side * 10, 46)
      ..lineTo(50 - side * 4, 42)
      ..close();
    paintPlastic(canvas, ribbon, side < 0 ? Art.ribbonBlue : Art.ribbonBlueDark, edge: 1.6, shine: .4);
  }
  const c = Offset(50, 62);
  canvas.drawCircle(c.translate(0, 2), 29, Paint()..color = dark);
  paintPlastic(canvas, Path()..addOval(Rect.fromCircle(center: c, radius: 28)), metal, edge: 1.8);
  canvas.drawCircle(c, 20, _edge(Art.deep(metal, .2), 2));
  final star = _star(c, 13, 6);
  canvas.drawPath(star.shift(const Offset(0, 1.4)), Paint()..color = Art.deep(metal, .32));
  canvas.drawPath(star, _vertical(star.getBounds(), [Art.light(metal, .6), metal]));
}

/// Un calendario de mesa con la hoja del dia y un punto rojo: el tablero del
/// dia.
void paintCalendar(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(50, 92), 70);
  final page = Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16, 18, 68, 70), const Radius.circular(12)));
  paintPlastic(canvas, page, T.shellTop, edge: 2);
  final head = Path()
    ..addRRect(RRect.fromRectAndCorners(const Rect.fromLTWH(16, 18, 68, 20),
        topLeft: const Radius.circular(12), topRight: const Radius.circular(12)));
  paintPlastic(canvas, head, Art.awningRed, edge: 2);
  for (final x in [34.0, 66.0]) {
    paintPlastic(canvas, Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 3, 10, 6, 14), const Radius.circular(3))),
        Art.chromeDark, edge: 1.2);
  }
  // Rejilla de dias; el de hoy, marcado.
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 4; col++) {
      final r = Rect.fromLTWH(24 + col * 14, 45 + row * 13, 10, 9);
      final today = row == 1 && col == 2;
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2.5)),
          Paint()..color = today ? Art.ribbonBlue : T.wellTop);
    }
  }
  paintTwinkle(canvas, const Offset(73, 55), 5, Art.gold);
}
