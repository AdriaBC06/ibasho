// Ibasho — Hatarakitama: los edificios del pueblo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_art.dart';

/// Un edificio del pueblo, con un cartel de lo que se hace en él. Sin
/// hacer, sale el solar con la cuerda y las estacas.
class HatarakiBuildingIcon extends StatelessWidget {
  const HatarakiBuildingIcon(
    this.building, {
    super.key,
    this.size = 48,
    this.built = true,
  });

  final HBuilding building;
  final double size;
  final bool built;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BuildingPainter(building, built)),
  );
}

class _BuildingPainter extends CustomPainter {
  _BuildingPainter(this.building, this.built);

  final HBuilding building;
  final bool built;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    paintHatarakiBuilding(canvas, building, built: built);
  }

  @override
  bool shouldRepaint(_BuildingPainter old) =>
      old.building != building || old.built != built;
}

/// Tejado, paredes y cartel de cada edificio.
const Map<HBuilding, (Color, Color, String)> _townLooks = {
  HBuilding.workshop: (Color(0xFF8E5B36), Color(0xFFF3E3C8), 'bar_iron'),
  HBuilding.kiln: (Color(0xFFC0613F), Color(0xFFE8C9A6), 'pot_vase'),
  HBuilding.dock: (Color(0xFF4F86B0), Color(0xFFE0AA70), 'fish_saba'),
  HBuilding.greenhouse: (Color(0xFFBFE6F5), Color(0xFFEAF6EE), 'crop_ichigo'),
  HBuilding.library: (Color(0xFF3F618C), Color(0xFFF6F0E2), 'book_basic'),
  HBuilding.tower: (Color(0xFF7E62C9), Color(0xFFEDE6F7), 'rune_spark'),
  HBuilding.inn: (Color(0xFFC8323E), Color(0xFFFAF1E4), 'tea_sencha'),
  HBuilding.shop: (Color(0xFF5DB15E), Color(0xFFFFF6E0), 'seed_rice'),
  HBuilding.market: (Color(0xFFE0864F), Color(0xFFF7EBD9), 'fish_tai'),
  HBuilding.board: (Color(0xFF8E5B36), Color(0xFFE8C9A6), 'parcel'),
};

/// Pinta [b] en el lienzo de 100×100.
void paintHatarakiBuilding(Canvas c, HBuilding b, {bool built = true}) {
  paintGroundShadow(c, const Offset(50, 90), 76);
  final (roof, wall, sign) = _townLooks[b]!;
  if (!built) {
    _plot(c, roof);
    return;
  }
  switch (b) {
    case HBuilding.tower:
      paintPlastic(c, _rrect(34, 36, 32, 52, 4), wall, edge: 2);
      paintPlastic(
        c,
        _poly(const [Offset(28, 40), Offset(50, 6), Offset(72, 40)]),
        roof,
        edge: 2,
      );
      paintPlastic(c, _circle(50, 52, 6), const Color(0xFFFFE08A), edge: 1.2);
      paintPlastic(
        c,
        _rrect(43, 70, 14, 18, 6),
        Art.deep(roof, .35),
        edge: 1.2,
      );
      paintTwinkle(c, const Offset(78, 16), 6, const Color(0xFFFFE08A));
      return;
    case HBuilding.dock:
      paintPlastic(
        c,
        _rrect(4, 70, 92, 18, 8),
        const Color(0xFF7FC4E8),
        edge: 1.4,
      );
      for (final x in const [20.0, 48.0, 76.0]) {
        paintPlastic(
          c,
          _rrect(x - 3, 58, 6, 28, 2),
          Art.deep(wall, .35),
          edge: 1,
        );
      }
      paintPlastic(c, _rrect(8, 54, 84, 10, 3), wall, edge: 1.8);
      _house(c, roof, const Color(0xFFF3E3C8), 26, 16, 48, 40);
      _signOn(c, sign, 50, 40);
      return;
    case HBuilding.greenhouse:
      paintPlastic(c, _rrect(12, 50, 76, 38, 4), wall, edge: 2, shine: .5);
      paintPlastic(
        c,
        Path()
          ..moveTo(8, 52)
          ..quadraticBezierTo(50, 4, 92, 52)
          ..close(),
        roof,
        edge: 2,
        shine: .6,
      );
      final frame = _line(const Color(0xFFFFFFFF), 2);
      c
        ..drawLine(const Offset(50, 28), const Offset(50, 88), frame)
        ..drawLine(const Offset(30, 36), const Offset(30, 88), frame)
        ..drawLine(const Offset(70, 36), const Offset(70, 88), frame);
      for (final x in const [22.0, 40.0, 60.0, 78.0]) {
        _leafShape(c, Offset(x, 86), Offset(x - 6, 70), _leaf);
      }
      _signOn(c, sign, 50, 62);
      return;
    case HBuilding.market:
      // Lonja: tejado abierto sobre postes y cajas debajo.
      for (final x in const [16.0, 84.0]) {
        paintPlastic(c, _rrect(x - 3, 34, 6, 54, 2), _handle, edge: 1);
      }
      paintPlastic(
        c,
        _poly(const [
          Offset(4, 38),
          Offset(24, 14),
          Offset(76, 14),
          Offset(96, 38),
        ]),
        roof,
        edge: 2,
      );
      paintPlastic(
        c,
        _rrect(22, 64, 26, 22, 3),
        _tones['plank_sugi']!,
        edge: 1.4,
      );
      paintPlastic(
        c,
        _rrect(52, 64, 26, 22, 3),
        _tones['plank_sugi']!,
        edge: 1.4,
      );
      _scaled(c, 35, 62, .28, () => _shape(c, 'fish_saba'));
      _scaled(c, 65, 62, .28, () => _shape(c, 'crop_ichigo'));
      _signOn(c, sign, 50, 30);
      return;
    case HBuilding.shop:
      _house(c, roof, wall, 14, 24, 72, 64);
      // Toldo a rayas sobre el mostrador.
      for (var i = 0; i < 6; i++) {
        paintPlastic(
          c,
          _rrect(16 + i * 11.3, 50, 11.3, 10, 2),
          i.isEven ? roof : const Color(0xFFFFFFFF),
          edge: .8,
        );
      }
      _signOn(c, sign, 50, 36);
      return;
    case HBuilding.inn:
      _house(c, roof, wall, 10, 30, 80, 58);
      paintPlastic(
        c,
        _oval(82, 50, 10, 14),
        const Color(0xFFFF6B5A),
        edge: 1.2,
      );
      _signOn(c, sign, 50, 52);
      return;
    case HBuilding.kiln:
      paintPlastic(c, _rrect(64, 14, 12, 40, 3), Art.deep(roof, .2), edge: 1.4);
      paintPlastic(
        c,
        Path()
          ..moveTo(10, 88)
          ..quadraticBezierTo(12, 26, 50, 26)
          ..quadraticBezierTo(88, 26, 90, 88)
          ..close(),
        roof,
        edge: 2,
      );
      paintPlastic(
        c,
        _rrect(38, 62, 24, 26, 12),
        const Color(0xFF3A2A24),
        edge: 1,
      );
      paintPlastic(c, _oval(50, 78, 14, 10), const Color(0xFFFF9A3D), edge: .8);
      _steam(c, 70, 10);
      _signOn(c, sign, 50, 44);
      return;
    case HBuilding.board:
      // Tablón: dos postes, un tejadillo y papeles clavados.
      for (final x in const [18.0, 82.0]) {
        paintPlastic(c, _rrect(x - 4, 22, 8, 66, 2), _handle, edge: 1.2);
      }
      paintPlastic(c, _rrect(14, 34, 72, 42, 4), wall, edge: 2);
      paintPlastic(
        c,
        _poly(const [
          Offset(6, 30),
          Offset(20, 12),
          Offset(80, 12),
          Offset(94, 30),
        ]),
        roof,
        edge: 2,
      );
      const notes = [
        (26.0, 40.0, -.08, Color(0xFFFFFBF2)),
        (48.0, 38.0, .06, Color(0xFFFFE9A8)),
        (66.0, 44.0, -.05, Color(0xFFFFFBF2)),
      ];
      for (final (x, y, turn, tone) in notes) {
        _turned(c, x + 7, y + 10, turn, () {
          paintPlastic(c, _rrect(x, y, 15, 20, 1.5), tone, edge: 1);
          final ink = _line(const Color(0xFFB9A58A), 1.4);
          for (var k = 0; k < 3; k++) {
            c.drawLine(
              Offset(x + 3, y + 8 + k * 4),
              Offset(x + 12, y + 8 + k * 4),
              ink,
            );
          }
        });
        paintPlastic(c, _circle(x + 7.5, y + 2, 2.2), const Color(0xFFE0493E));
      }
      _signOn(c, sign, 50, 70);
      return;
    case HBuilding.workshop || HBuilding.library:
      _house(c, roof, wall, 12, 26, 76, 62);
      _signOn(c, sign, 50, 52);
      return;
  }
}

/// Paredes, tejado a dos aguas y puerta, dentro de la caja dada.
void _house(
  Canvas c,
  Color roof,
  Color wall,
  double x,
  double y,
  double w,
  double h,
) {
  final top = y + h * .32;
  paintPlastic(c, _rrect(x + 4, top, w - 8, y + h - top, 3), wall, edge: 1.8);
  paintPlastic(
    c,
    Path()
      ..moveTo(x - 4, top + 4)
      ..quadraticBezierTo(x + w * .3, top - 2, x + w / 2, y)
      ..quadraticBezierTo(x + w * .7, top - 2, x + w + 4, top + 4)
      ..close(),
    roof,
    edge: 2,
  );
  final dw = w * .2;
  paintPlastic(
    c,
    _rrect(x + w * .72 - dw / 2, y + h - h * .3, dw, h * .3, 2),
    Art.deep(wall, .45),
    edge: 1,
  );
}

/// Un cartel redondo con el dibujo de lo que se hace dentro.
void _signOn(Canvas c, String item, double x, double y) {
  paintPlastic(c, _circle(x, y, 11), const Color(0xFFFFFBF2), edge: 1.4);
  _scaled(c, x, y, .19, () => _shape(c, item));
}

/// El solar sin edificio: estacas, cuerda y un montón de tablas.
void _plot(Canvas c, Color tint) {
  paintPlastic(c, _oval(50, 78, 80, 20), const Color(0xFFD9C29A), edge: 1.2);
  final rope = _line(Art.deep(tint, .1), 1.6);
  c
    ..drawLine(const Offset(18, 70), const Offset(82, 70), rope)
    ..drawLine(const Offset(18, 70), const Offset(18, 60), rope)
    ..drawLine(const Offset(82, 70), const Offset(82, 60), rope);
  for (final x in const [18.0, 82.0]) {
    paintPlastic(c, _rrect(x - 3, 56, 6, 26, 2), _handle, edge: 1);
  }
  _scaled(c, 50, 70, .4, () => _shape(c, 'build_beam'));
}

// --- En el mapa del pueblo -------------------------------------------------------

/// Ancho y alto del lienzo de una parcela del mapa: el edificio (100×100)
/// en medio y, alrededor, lo que va ganando con cada nivel.
const double hLotWidth = 140;
const double hLotHeight = 120;

/// Un edificio en su parcela, con los detalles de su [level]: suelo que
/// pasa de tierra a grava y a losas, macetas, un farol de piedra, un árbol
/// y, a nivel 5, su estandarte.
class HatarakiTownLot extends StatelessWidget {
  const HatarakiTownLot(
    this.building, {
    super.key,
    required this.level,
    this.width = hLotWidth,
    this.built,
  });

  final HBuilding building;
  final int level;
  final double width;

  /// Si se dibuja hecho aunque el nivel sea 0 (la posada con habitaciones).
  final bool? built;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * hLotHeight / hLotWidth,
    child: CustomPaint(
      painter: _LotPainter(building, level, built ?? level > 0),
    ),
  );
}

class _LotPainter extends CustomPainter {
  _LotPainter(this.building, this.level, this.built);

  final HBuilding building;
  final int level;
  final bool built;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / hLotWidth, size.height / hLotHeight);
    paintHatarakiLot(canvas, building, level, built: built);
  }

  @override
  bool shouldRepaint(_LotPainter old) =>
      old.building != building || old.level != level || old.built != built;
}

/// Pinta [b] a nivel [level] en el lienzo de [hLotWidth]×[hLotHeight].
void paintHatarakiLot(Canvas c, HBuilding b, int level, {bool built = true}) {
  final (roof, _, _) = _townLooks[b]!;
  if (built) {
    // El suelo de delante: tierra, grava (nivel 3) y losas (nivel 5).
    final ground = level >= 5
        ? const Color(0xFFD6CFC4)
        : level >= 3
        ? const Color(0xFFE2DACB)
        : const Color(0xFFE3CFA6);
    paintPlastic(c, _oval(70, 102, 128, 30), ground, edge: 1.2, shine: .3);
    if (level >= 5) {
      final joint = _line(Art.deep(ground, .25), 1);
      for (final x in const [38.0, 58.0, 82.0, 102.0]) {
        c.drawLine(Offset(x, 92), Offset(x + 4, 113), joint);
      }
      c.drawLine(const Offset(14, 102), const Offset(126, 102), joint);
    } else if (level >= 3) {
      final pebble = Paint()..color = Art.deep(ground, .18);
      for (final (x, y) in const [
        (22.0, 104.0),
        (40.0, 110.0),
        (60.0, 96.0),
        (84.0, 111.0),
        (104.0, 97.0),
        (118.0, 106.0),
        (50.0, 106.0),
        (94.0, 104.0),
      ]) {
        c.drawCircle(Offset(x, y), 1.4, pebble);
      }
    }
    // Detrás del edificio: el árbol (nivel 4) y el estandarte (nivel 5).
    if (level >= 4) _lotTree(c, 12, 62);
    if (level >= 5) _lotBanner(c, 128, roof);
  } else {
    paintPlastic(
      c,
      _oval(70, 102, 110, 22),
      const Color(0xFFCFE3B0),
      edge: .8,
      shine: 0,
    );
  }
  c
    ..save()
    ..translate(20, 10);
  paintHatarakiBuilding(c, b, built: built);
  c.restore();
  if (!built) return;
  // Delante: macetas (nivel 2), farol (nivel 3) y un arbusto (nivel 4).
  if (level >= 2) _lotPot(c, 12, 100, roof);
  if (level >= 3) _lotLantern(c, 126, 104);
  if (level >= 4) {
    paintPlastic(c, _oval(30, 112, 20, 12), _leafDark, edge: 1, shine: .4);
    paintPlastic(c, _oval(36, 109, 14, 10), _leaf, edge: .8, shine: .6);
  }
  if (level >= 5) {
    paintTwinkle(c, const Offset(8, 30), 5, const Color(0xFFFFE08A));
    paintTwinkle(c, const Offset(116, 8), 4, const Color(0xFFFFE08A));
  }
}

/// Una maceta con flores del color del tejado.
void _lotPot(Canvas c, double x, double y, Color tint) {
  _leafShape(c, Offset(x, y - 8), Offset(x - 6, y - 20), _leaf);
  _leafShape(c, Offset(x, y - 8), Offset(x + 6, y - 19), _leaf);
  for (final (dx, dy) in const [(-5.0, -21.0), (5.0, -22.0), (0.0, -26.0)]) {
    paintPlastic(
      c,
      _circle(x + dx, y + dy, 3.6),
      Art.light(tint, .25),
      edge: .8,
    );
    c.drawCircle(
      Offset(x + dx, y + dy),
      1.2,
      Paint()..color = const Color(0xFFFFE08A),
    );
  }
  paintPlastic(
    c,
    _poly([
      Offset(x - 8, y - 10),
      Offset(x + 8, y - 10),
      Offset(x + 6, y + 4),
      Offset(x - 6, y + 4),
    ]),
    const Color(0xFFC0613F),
    edge: 1.2,
  );
}

/// Un farol de piedra con la luz encendida.
void _lotLantern(Canvas c, double x, double y) {
  const stone = Color(0xFFB9B4AA);
  paintPlastic(c, _rrect(x - 7, y - 4, 14, 6, 2), stone, edge: 1);
  paintPlastic(c, _rrect(x - 2.5, y - 16, 5, 13, 1.5), stone, edge: 1);
  paintPlastic(c, _rrect(x - 6, y - 28, 12, 12, 2), stone, edge: 1);
  paintPlastic(
    c,
    _rrect(x - 3, y - 25, 6, 6, 1),
    const Color(0xFFFFD36B),
    edge: .6,
  );
  paintPlastic(
    c,
    _poly([Offset(x - 11, y - 28), Offset(x, y - 36), Offset(x + 11, y - 28)]),
    stone,
    edge: 1,
  );
}

/// Un árbol redondo detrás del edificio.
void _lotTree(Canvas c, double x, double y) {
  paintPlastic(c, _rrect(x - 3, y, 6, 36, 2), _handle, edge: 1);
  paintPlastic(c, _circle(x, y - 6, 14), _leafDark, edge: 1.4);
  paintPlastic(c, _circle(x + 5, y - 12, 9), _leaf, edge: 1, shine: .7);
}

/// El estandarte del nivel más alto, con el borde dorado.
void _lotBanner(Canvas c, double x, Color tint) {
  paintPlastic(c, _rrect(x - 1.8, 18, 3.6, 76, 1.5), _handle, edge: .8);
  paintPlastic(
    c,
    _rrect(x - 16, 22, 14, 44, 1.5),
    const Color(0xFFFFD36B),
    edge: 1,
  );
  paintPlastic(c, _rrect(x - 14, 24, 10, 40, 1), tint, edge: .8);
  paintPlastic(c, _circle(x - 9, 38, 3), const Color(0xFFFFFBF2), edge: .6);
  paintPlastic(c, _circle(x, 17, 2.6), const Color(0xFFFFD36B), edge: .6);
}

/// El suelo del mapa del pueblo: hierba, el río de abajo, los caminos
/// ([roads], de parcela en parcela) y unos pocos árboles en [trees].
void paintHatarakiTownGround(
  Canvas c,
  Size size, {
  required List<(Offset, Offset)> roads,
  required List<Offset> trees,
  required double river,
  required double scale,
}) {
  final w = size.width;
  final h = size.height;
  c.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFFCFE8B4), Color(0xFFB9DC9C)],
      ).createShader(Offset.zero & size),
  );
  // Matas de hierba sueltas, siempre en el mismo sitio.
  final tuft = _line(const Color(0xFF9CC77E), 1.4 * scale);
  for (var i = 0; i < 46; i++) {
    final x = ((i * 97) % 101) / 101 * w;
    final y = ((i * 61) % 89) / 89 * river;
    c
      ..drawLine(Offset(x, y), Offset(x - 2 * scale, y - 5 * scale), tuft)
      ..drawLine(Offset(x, y), Offset(x + 2 * scale, y - 5 * scale), tuft);
  }
  // El río, con la orilla ondulada.
  final water = Path()..moveTo(0, river);
  for (var x = 0.0; x <= w; x += 8) {
    water.lineTo(x, river + 4 * scale * math.sin(x / (26 * scale)));
  }
  water
    ..lineTo(w, h)
    ..lineTo(0, h)
    ..close();
  c.drawPath(water, Paint()..color = const Color(0xFFE8D8B0));
  c
    ..save()
    ..translate(0, 5 * scale);
  c.drawPath(
    water,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF8FCBEA), Color(0xFF5FA8D6)],
      ).createShader(Rect.fromLTWH(0, river, w, h - river)),
  );
  c.restore();
  final ripple = _line(const Color(0xAAFFFFFF), 1.6 * scale);
  for (var i = 0; i < 7; i++) {
    final x = (i * .15 + .04) * w;
    final y = river + (14 + (i % 3) * 9) * scale;
    if (y > h - 4) continue;
    c.drawLine(Offset(x, y), Offset(x + 14 * scale, y), ripple);
  }
  // Los caminos: el borde y, encima, la tierra.
  final edge = _line(const Color(0xFFD2B98C), 17 * scale);
  final dirt = _line(const Color(0xFFEBDDBA), 13 * scale);
  for (final paint in [edge, dirt]) {
    for (final (a, b) in roads) {
      c.drawLine(a, b, paint);
    }
  }
  for (final t in trees) {
    c
      ..save()
      ..translate(t.dx, t.dy)
      ..scale(scale * .8)
      ..translate(-12, -98);
    paintGroundShadow(c, const Offset(12, 98), 34);
    _lotTree(c, 12, 62);
    c.restore();
  }
}
