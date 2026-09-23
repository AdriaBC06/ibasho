// Ibasho — ilustraciones del gacha: los tickets, las bolas de cada rareza,
// los emblemas y el Catalogo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/gacha.dart';
import '../../theme/type.dart';
import 'channel_art.dart';

/// Los colores de cada rareza. Son suyos, como los de cualquier ilustracion:
/// no siguen al acento, para que un SSR se vea igual en toda cuenta.
abstract final class RarityArt {
  static const Color n = Color(0xFFB9C6D2);
  static const Color r = Color(0xFF74DDA2);
  static const Color sr = Color(0xFF5BC8F5);
  static const Color ssr = Color(0xFFB08BE0);
  static const Color ur = Color(0xFFFFCB45);

  /// La oculta: no es un color, es un arcoiris. El primero vale de base para
  /// lo que necesite uno solo.
  static const List<Color> mu = <Color>[
    Color(0xFFF47AA6),
    Color(0xFFB08BE0),
    Color(0xFF5BC8F5),
    Color(0xFF74DDA2),
    Color(0xFFFFCB45),
  ];

  static Color of(Rarity rarity) => switch (rarity) {
        Rarity.n => n,
        Rarity.r => r,
        Rarity.sr => sr,
        Rarity.ssr => ssr,
        Rarity.ur => ur,
        Rarity.mu => mu.first,
      };

  /// Los dos colores del degradado de una cinta o una bola.
  static List<Color> sweep(Rarity rarity) => rarity == Rarity.mu
      ? mu
      : <Color>[Art.light(of(rarity), .4), of(rarity), Art.deep(of(rarity), .25)];

  /// Cuanto brilla: de lo comun a lo que merece destellos.
  static bool shines(Rarity rarity) => rarity.index >= Rarity.ssr.index;
}

// --- Los tickets ----------------------------------------------------------------

/// Un ticket de feria sobre 100x100: papel con muescas a los lados, una banda
/// con la estrella y el borde troquelado. El normal es rojo con la banda
/// amarilla (ガチャ券); el dorado va entero en oro con destellos (金券).
void paintTicket(Canvas canvas, {required bool gold}) {
  paintGroundShadow(canvas, const Offset(50, 86), 62);

  const body = Rect.fromLTWH(11, 26, 78, 48);
  final base = gold ? Art.gold : const Color(0xFFF2636E);
  final band = gold ? const Color(0xFFFFF0B8) : const Color(0xFFFFD25A);

  // El papel, con una muesca redonda a cada lado.
  final paper = Path()
    ..addRRect(RRect.fromRectAndRadius(body, const Radius.circular(9)))
    ..addOval(Rect.fromCircle(center: const Offset(11, 50), radius: 7))
    ..addOval(Rect.fromCircle(center: const Offset(89, 50), radius: 7))
    ..fillType = PathFillType.evenOdd;
  paintPlastic(canvas, paper, base, edge: 2.2);

  // La banda de la izquierda, donde va la estrella, separada por el
  // troquelado.
  canvas.save();
  canvas.clipPath(paper);
  final strip = Path()..addRect(const Rect.fromLTWH(11, 26, 27, 48));
  paintPlastic(canvas, strip, band, edge: 0, shine: .6);
  canvas.restore();
  for (var y = 31.0; y < 72; y += 6.5) {
    canvas.drawCircle(Offset(38, y), 1.1, Paint()..color = Art.deep(base, .3));
  }

  // La estrella de la banda y las dos rayas del texto.
  paintStar(canvas, const Offset(24.5, 50), 8.5, gold ? Art.goldDark : const Color(0xFFE5484D));
  for (final y in <double>[43.0, 52.0, 61.0]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(46, y, y == 61 ? 20 : 32, 5), const Radius.circular(2.5)),
      Paint()..color = Color.fromRGBO(255, 255, 255, gold ? .85 : .7),
    );
  }

  if (gold) {
    paintTwinkle(canvas, const Offset(80, 24), 9, const Color(0xFFFFF6D0));
    paintTwinkle(canvas, const Offset(22, 78), 6, const Color(0xCCFFF6D0));
  }
}

/// Una estrella de cinco puntas, rellena de plastico.
void paintStar(Canvas canvas, Offset c, double r, Color color) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final angle = -math.pi / 2 + i * math.pi / 5;
    final radius = i.isEven ? r : r * .45;
    final p = Offset(c.dx + math.cos(angle) * radius, c.dy + math.sin(angle) * radius);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  path.close();
  paintPlastic(canvas, path, color, edge: 1.4);
}

// --- El pinball -----------------------------------------------------------------

/// El icono del pinball: una mesa de plastico con su cupula, un bumper, dos
/// flippers y una bola del gacha rodando.
void paintPinballIcon(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(50, 92), 70);
  const frameColor = Color(0xFF6A94F0);

  // El marco, con la cupula arriba.
  final frame = Path()
    ..moveTo(18, 88)
    ..lineTo(18, 34)
    ..arcToPoint(const Offset(82, 34), radius: const Radius.circular(32))
    ..lineTo(82, 88)
    ..close();
  paintPlastic(canvas, frame, frameColor, edge: 2.2);

  // El campo, blanco.
  final field = Path()
    ..moveTo(25, 84)
    ..lineTo(25, 35)
    ..arcToPoint(const Offset(75, 35), radius: const Radius.circular(25))
    ..lineTo(75, 84)
    ..close();
  canvas.drawPath(
    field,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFFFFFFFF), Color(0xFFDDE9F4)],
      ).createShader(const Rect.fromLTWH(25, 10, 50, 74)),
  );

  // El bumper con su estrella y un agujero de color.
  final bumper = Path()..addOval(Rect.fromCircle(center: const Offset(44, 40), radius: 9));
  paintPlastic(canvas, bumper, const Color(0xFFF47AA6), edge: 1.6);
  paintStar(canvas, const Offset(44, 40), 4.2, const Color(0xFFFFF3C4));
  canvas.drawCircle(const Offset(63, 30), 5, Paint()..color = Art.deep(const Color(0xFFB08BE0), .6));
  canvas.drawCircle(
    const Offset(63, 30),
    5,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFB08BE0),
  );

  // Los flippers.
  for (final left in <bool>[true, false]) {
    final flipper = Path()
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, -3.5, 17, 7), const Radius.circular(3.5)));
    canvas.save();
    canvas.translate(left ? 33 : 67, 74);
    canvas.rotate(left ? .45 : math.pi - .45);
    paintPlastic(canvas, flipper, const Color(0xFFFFFFFF), edge: 1.6);
    canvas.restore();
  }

  // La bola.
  paintGachaBall(canvas, const Offset(58, 58), 7.5, Rarity.ssr, shadow: 0);
  paintTwinkle(canvas, const Offset(80, 16), 7, const Color(0xCCFFFFFF));
}

// --- El pachinko ----------------------------------------------------------------

/// El icono del pachinko: un mueble vertical de plastico con el cristal
/// redondo, clavos de laton, el tulipan rojo en medio y bolas cayendo.
void paintPachinkoIcon(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(50, 93), 66);
  const cabinet = Color(0xFFF2A24A);

  final body = Path()
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(20, 10, 60, 80), const Radius.circular(14)));
  paintPlastic(canvas, body, cabinet, edge: 2.2);

  // El cristal, redondo arriba.
  final glass = Path()
    ..moveTo(27, 78)
    ..lineTo(27, 38)
    ..arcToPoint(const Offset(73, 38), radius: const Radius.circular(23))
    ..lineTo(73, 78)
    ..close();
  canvas.drawPath(
    glass,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Color(0xFFFFFFFF), Color(0xFFE2ECF6)],
      ).createShader(const Rect.fromLTWH(27, 15, 46, 63)),
  );

  // Los clavos, al tresbolillo.
  final pin = Paint()..color = const Color(0xFFB9975A);
  for (var row = 0; row < 5; row++) {
    for (var col = 0; col < 5; col++) {
      final x = 33 + col * 9.0 + (row.isOdd ? 4.5 : 0);
      final y = 30 + row * 8.0;
      if (x > 70) continue;
      canvas.drawCircle(Offset(x, y), 1.3, pin);
    }
  }

  // El tulipan rojo.
  final tulip = Path()
    ..moveTo(43, 66)
    ..quadraticBezierTo(41, 59, 45, 57)
    ..lineTo(48, 63)
    ..lineTo(52, 63)
    ..lineTo(55, 57)
    ..quadraticBezierTo(59, 59, 57, 66)
    ..close();
  paintPlastic(canvas, tulip, const Color(0xFFF0506E), edge: 1.2);

  // La salida y el platillo de bolas.
  canvas.drawOval(const Rect.fromLTWH(44, 73, 12, 4), Paint()..color = const Color(0x552A3040));
  final tray = Path()
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(26, 82, 48, 9), const Radius.circular(4.5)));
  paintPlastic(canvas, tray, const Color(0xFFFFFFFF), edge: 1.4);

  paintGachaBall(canvas, const Offset(40, 50), 4.4, Rarity.n, shadow: 0, twinkle: false);
  paintGachaBall(canvas, const Offset(60, 42), 4.4, Rarity.sr, shadow: 0, twinkle: false);
  paintGachaBall(canvas, const Offset(50, 60), 4.6, Rarity.ssr, shadow: 0);
  paintTwinkle(canvas, const Offset(80, 14), 7, const Color(0xCCFFFFFF));
}

// --- Las bolas ------------------------------------------------------------------

/// Una bola del gacha de la rareza que sea: cristal con el color dentro,
/// reflejo arriba y canto oscuro. La oculta lleva el arcoiris girando.
/// Con [spin] la banda gira y lleva una muesca (la bola rodando del
/// pinball); sin [twinkle] no sale el destello de las raras.
void paintGachaBall(
  Canvas canvas,
  Offset c,
  double r,
  Rarity rarity, {
  double shadow = .22,
  double? spin,
  bool twinkle = true,
}) {
  if (shadow > 0) paintGroundShadow(canvas, c.translate(0, r * 1.05), r * 1.9, shadow);
  final rect = Rect.fromCircle(center: c, radius: r);
  final colors = RarityArt.sweep(rarity);

  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = rarity == Rarity.mu
          ? SweepGradient(colors: <Color>[...colors, colors.first], transform: GradientRotation(-math.pi / 2))
              .createShader(rect)
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ).createShader(rect),
  );

  // La banda del medio, como una capsula de gachapon. Gira con [spin]; el
  // reflejo no, porque la luz viene siempre de arriba a la izquierda.
  final turn = spin ?? 0;
  final band = Offset(math.cos(turn), math.sin(turn)) * (r * .96);
  final bandPaint = Paint()
    ..strokeWidth = r * .13
    ..strokeCap = StrokeCap.round
    ..color = Art.deep(colors.first, .4).withValues(alpha: .55);
  canvas.drawLine(c - band, c + band, bandPaint);
  if (spin != null) {
    // Una muesca en una mitad, para que se vea hacia donde rueda.
    final notch = Offset(-math.sin(turn), math.cos(turn)) * (r * .5);
    canvas.drawCircle(c + notch, r * .12, Paint()..color = bandPaint.color);
  }

  // Reflejo y canto.
  canvas.drawOval(
    Rect.fromCenter(center: c.translate(-r * .3, -r * .45), width: r * .8, height: r * .42),
    Paint()..color = const Color(0xCCFFFFFF),
  );
  canvas.drawCircle(c, r, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = r * .1
    ..color = Art.deep(colors.first, .45));

  if (twinkle && RarityArt.shines(rarity)) {
    paintTwinkle(canvas, c.translate(r * .75, -r * .8), r * .42, const Color(0xEEFFFFFF));
  }
}

/// Una bola en su propio widget, para ponerla en una fila.
class GachaBallView extends StatelessWidget {
  const GachaBallView(this.rarity, {super.key, this.size = 48, this.shadow = true});

  final Rarity rarity;
  final double size;
  final bool shadow;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BallPainter(rarity, shadow)),
      );
}

class _BallPainter extends CustomPainter {
  const _BallPainter(this.rarity, this.shadow);

  final Rarity rarity;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    paintGachaBall(canvas, Offset(size.width / 2, size.height / 2), r * .88, rarity,
        shadow: shadow ? .2 : 0);
  }

  @override
  bool shouldRepaint(_BallPainter old) => old.rarity != rarity || old.shadow != shadow;
}

// --- El emblema de cada rareza --------------------------------------------------

/// La cinta con la sigla de una rareza (N, R, SR, SSR, UR y el infinito de la
/// oculta). Es plastico tintado con su color, no acento: una rareza se lee
/// igual en cualquier cuenta.
class RarityBadge extends StatelessWidget {
  const RarityBadge(this.rarity, {super.key, this.height = 26, this.faded = false});

  final Rarity rarity;
  final double height;

  /// Apagada: la rareza que se ensena como opcion sin elegir.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final colors = RarityArt.sweep(rarity);
    return Opacity(
      opacity: faded ? .45 : 1,
      child: CustomPaint(
        painter: _BadgePainter(rarity),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: height * .46),
            child: Center(
              widthFactor: 1,
              child: Text(
                rarity.label,
                style: Ty.numeral(height * (rarity == Rarity.mu ? .62 : .5), weight: FontWeight.w700)
                    .copyWith(color: Art.deep(colors.first, .62)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter(this.rarity);

  final Rarity rarity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = RarityArt.sweep(rarity);
    final body = RRect.fromRectAndRadius(rect, Radius.circular(size.height * .32));
    canvas.drawRRect(
      body,
      Paint()
        ..shader = rarity == Rarity.mu
            ? LinearGradient(colors: colors).createShader(rect)
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ).createShader(rect),
    );
    // Brillo de plastico arriba.
    canvas.save();
    canvas.clipRRect(body);
    final gloss = Rect.fromLTWH(0, 0, size.width, size.height * .5);
    canvas.drawRect(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const <Color>[Color(0x99FFFFFF), Color(0x11FFFFFF)],
        ).createShader(gloss),
    );
    canvas.restore();
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * .07
        ..color = Art.deep(colors.first, .45),
    );
  }

  @override
  bool shouldRepaint(_BadgePainter old) => old.rarity != rarity;
}

// --- El Catalogo y sus categorias -----------------------------------------------

/// El Catalogo: un album abierto con sus pestanas de colores y una estrella
/// marcada en la pagina, que es el deseo.
void paintCatalog(Canvas canvas) {
  paintGroundShadow(canvas, const Offset(50, 88), 70);

  // Tapa.
  final cover = Path()
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(12, 22, 76, 62), const Radius.circular(8)));
  paintPlastic(canvas, cover, const Color(0xFF6A94F0), edge: 2.2);

  // Paginas.
  final pages = Path()
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(18, 28, 64, 50), const Radius.circular(5)));
  paintPlastic(canvas, pages, Art.paper, edge: 1.6, shine: .5);

  // El lomo, en medio.
  canvas.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(47.5, 28, 5, 50), const Radius.circular(2.5)),
    Paint()..color = Art.deep(const Color(0xFF6A94F0), .25),
  );

  // Renglones a la izquierda y el premio marcado a la derecha.
  for (var i = 0; i < 4; i++) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(24, 36 + i * 9, 19, 4), const Radius.circular(2)),
      Paint()..color = const Color(0x33324A63),
    );
  }
  paintGachaBall(canvas, const Offset(66, 45), 9, Rarity.ssr, shadow: 0);
  paintStar(canvas, const Offset(66, 67), 8, Art.gold);

  // Pestanas de las categorias, asomando arriba.
  const tabs = <(double, Color)>[
    (26, Color(0xFFF2636E)),
    (44, Color(0xFF74DDA2)),
    (62, Color(0xFFFFCB45)),
  ];
  for (final (x, color) in tabs) {
    final tab = Path()
      ..addRRect(RRect.fromRectAndCorners(
        Rect.fromLTWH(x, 15, 14, 12),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      ));
    paintPlastic(canvas, tab, color, edge: 1.4, shine: .8);
  }
}

/// El icono de una categoria de premios, sobre 100x100. Anadir una categoria
/// nueva es anadir aqui su dibujo.
void paintCategory(Canvas canvas, GachaCategory category) {
  switch (category) {
    case GachaCategory.hats:
      paintGroundShadow(canvas, const Offset(50, 76), 62);
      final brim = Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(14, 58, 72, 14), const Radius.circular(7)));
      paintPlastic(canvas, brim, const Color(0xFF5BC8F5), edge: 2);
      final crown = Path()
        ..addRRect(RRect.fromRectAndCorners(
          const Rect.fromLTWH(30, 26, 40, 34),
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
        ));
      paintPlastic(canvas, crown, const Color(0xFF6A94F0), edge: 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(28, 48, 44, 9), const Radius.circular(4.5)),
        Paint()..color = Art.gold,
      );
    case GachaCategory.accessories:
      paintGroundShadow(canvas, const Offset(50, 78), 58);
      // Un lazo.
      for (final side in <double>[-1, 1]) {
        final loop = Path()
          ..addOval(Rect.fromCenter(
            center: Offset(50 + side * 20, 50),
            width: 32,
            height: 26,
          ));
        paintPlastic(canvas, loop, const Color(0xFFF47AA6), edge: 2);
      }
      final knot = Path()..addOval(Rect.fromCircle(center: const Offset(50, 50), radius: 10));
      paintPlastic(canvas, knot, const Color(0xFFE5484D), edge: 1.8);
      paintTwinkle(canvas, const Offset(74, 30), 8, const Color(0xCCFFFFFF));
    case GachaCategory.backdrops:
      paintGroundShadow(canvas, const Offset(50, 82), 66);
      final frame = Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(16, 24, 68, 54), const Radius.circular(9)));
      paintPlastic(canvas, frame, const Color(0xFFB08BE0), edge: 2.2);
      final inner = RRect.fromRectAndRadius(const Rect.fromLTWH(23, 31, 54, 40), const Radius.circular(6));
      canvas.drawRRect(
        inner,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF9AD8FF), Color(0xFFFFE6A8)],
          ).createShader(inner.outerRect),
      );
      canvas.drawCircle(const Offset(63, 42), 6, Paint()..color = const Color(0xFFFFF3C4));
    case GachaCategory.music:
      paintGroundShadow(canvas, const Offset(50, 80), 56);
      final stem = Path()
        ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(56, 22, 7, 44), const Radius.circular(3.5)));
      final flag = Path()
        ..moveTo(63, 22)
        ..quadraticBezierTo(84, 27, 78, 44)
        ..quadraticBezierTo(76, 33, 63, 34)
        ..close();
      paintPlastic(canvas, flag, const Color(0xFFFFCB45), edge: 1.8);
      paintPlastic(canvas, stem, const Color(0xFF6A94F0), edge: 1.6);
      final head = Path()
        ..addOval(Rect.fromCenter(center: const Offset(46, 66), width: 28, height: 21));
      paintPlastic(canvas, head, const Color(0xFF5BC8F5), edge: 2);
  }
}

/// El color de cada categoria, el de su dibujo: pinta sus dianas y el aro
/// de su agujero en el pinball.
Color categoryColor(GachaCategory category) => switch (category) {
      GachaCategory.hats => const Color(0xFF6A94F0),
      GachaCategory.accessories => const Color(0xFFF47AA6),
      GachaCategory.backdrops => const Color(0xFFB08BE0),
      GachaCategory.music => const Color(0xFFFFB02E),
    };

/// El icono de una categoria, listo para poner en una baldosa.
class CategoryArtView extends StatelessWidget {
  const CategoryArtView(this.category, {super.key, this.size = 64});

  final GachaCategory category;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CategoryPainter(category)),
      );
}

class _CategoryPainter extends CustomPainter {
  const _CategoryPainter(this.category);

  final GachaCategory category;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * s) / 2, (size.height - 100 * s) / 2);
    canvas.scale(s);
    paintCategory(canvas, category);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CategoryPainter old) => old.category != category;
}
