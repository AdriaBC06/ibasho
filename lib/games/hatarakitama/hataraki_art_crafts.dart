// Ibasho — Hatarakitama: dibujos de los oficios de la 0.8.0 (cerámica,
// tintes, construcción, escritura, brebajes, magia y estudio) y de lo que
// hacen.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_art.dart';

const Map<String, Color> _craftTones = {
  'wild_yomogi': Color(0xFF7FB069),
  'water_spring': Color(0xFF7EC8F0),
  'clay': Color(0xFFC98A64),
  'soot': Color(0xFF4A4550),
  'crop_ai': Color(0xFF3D5FA8),
  'pot_bowl': Color(0xFF8FB8A8),
  'pot_brick': Color(0xFFC0613F),
  'pot_flask': Color(0xFFD9A477),
  'pot_tile': Color(0xFF5E6B7A),
  'pot_teapot': Color(0xFF9E5A3C),
  'pot_planter': Color(0xFFD27F4E),
  'pot_vase': Color(0xFF6F8FD6),
  'pot_celadon': Color(0xFF9FD1BD),
  'dye_yellow': Color(0xFFFFCF33),
  'dye_black': Color(0xFF3A3642),
  'dye_brown': Color(0xFF8A5530),
  'dye_blue': Color(0xFF2F58B8),
  'dye_red': Color(0xFFE0394E),
  'dye_pink': Color(0xFFF58DB6),
  'dye_gold': Color(0xFFF2B81F),
  'cloth_blue': Color(0xFF3558A8),
  'cloth_red': Color(0xFFD9404F),
  'cloth_gold': Color(0xFFF2C44A),
  'build_beam': Color(0xFFD9A066),
  'build_frame': Color(0xFFC98655),
  'build_wall': Color(0xFFF2E6D0),
  'build_roof': Color(0xFF55657A),
  'build_shoji': Color(0xFFFBF6EA),
  'build_pillar': Color(0xFFD8384A),
  'build_ornament': Color(0xFFF7C948),
  'paper': Color(0xFFFBF7EC),
  'ink': Color(0xFF2B2A33),
  'book_notes': Color(0xFFE8D7A8),
  'book_basic': Color(0xFF5E8C6A),
  'book_tome': Color(0xFF3558A8),
  'book_arcane': Color(0xFF7A55C9),
  'map_trail': Color(0xFFF2DFB4),
  'map_chart': Color(0xFFD6E8F2),
  'map_star': Color(0xFF34406E),
  'potion_heal': Color(0xFFF2545F),
  'potion_sight': Color(0xFF52B8E8),
  'potion_luck': Color(0xFF7ACC5A),
  'potion_haste': Color(0xFFF5A23A),
  'potion_elixir': Color(0xFFC08CF2),
  'rune_spark': Color(0xFFEAF2FF),
  'rune_guard': Color(0xFFA56BE3),
  'rune_compass': Color(0xFF3F79E0),
  'rune_fortune': Color(0xFFE63E5A),
  'rune_titan': Color(0xFFF8EEF2),
  'rune_star': Color(0xFFA696F7),
  'bait_worm': Color(0xFFE88A8A),
  'bait_lure': Color(0xFF52B8E8),
  'fert_compost': Color(0xFF7A5A3E),
  'fert_rich': Color(0xFF5E8C4E),
  'fuse_basic': Color(0xFFE0554A),
  'fuse_star': Color(0xFF8A7AF0),
  'gear_ai_happi': Color(0xFF2F4F9E),
  'gear_beni_cloak': Color(0xFFD8384A),
  'gear_kin_kimono': Color(0xFFF2B81F),
};

/// Pinta los objetos nuevos. Devuelve false si [id] no es uno de ellos.
bool _craft(Canvas c, String id, Color color) {
  switch (id.split('_').first) {
    case 'clay':
      _clay(c, color);
    case 'soot':
      _soot(c, color);
    case 'water':
      _drop(c, color);
    case 'pot':
      _pottery(c, id, color);
    case 'dye':
      _dyeJar(c, color);
    case 'build':
      _building(c, id, color);
    case 'paper':
      _paper(c, color);
    case 'ink':
      _ink(c, color);
    case 'book':
      _book(c, id, color);
    case 'map':
      _map(c, id, color);
    case 'potion':
      _potion(c, id, color);
    case 'rune':
      _rune(c, id, color);
    case 'bait':
      id == 'bait_worm' ? _worms(c, color) : _lure(c, color);
    case 'fert':
      _sack(c, color, rich: id == 'fert_rich');
    case 'fuse':
      _fuse(c, color, star: id == 'fuse_star');
    default:
      if (id == 'wild_yomogi') {
        _yomogi(c, color);
      } else if (id == 'crop_ai') {
        _ai(c, color);
      } else if (id.startsWith('cloth_')) {
        _cloth(c, color, silk: id == 'cloth_gold');
        _clothPattern(c, id);
      } else {
        return false;
      }
  }
  return true;
}

// --- Materiales --------------------------------------------------------------

void _clay(Canvas c, Color color) {
  final lump = Path()
    ..moveTo(18, 70)
    ..quadraticBezierTo(14, 44, 36, 38)
    ..quadraticBezierTo(46, 22, 64, 32)
    ..quadraticBezierTo(86, 36, 84, 62)
    ..quadraticBezierTo(84, 80, 50, 80)
    ..quadraticBezierTo(22, 82, 18, 70)
    ..close();
  paintPlastic(c, lump, color, edge: 2);
  // Las marcas de los dedos.
  final press = _line(Art.deep(color, .22), 2.4);
  for (final (x, y) in const [(38.0, 52.0), (50.0, 48.0), (62.0, 52.0)]) {
    c.drawArc(
      Rect.fromCenter(center: Offset(x, y), width: 9, height: 12),
      .4,
      2.4,
      false,
      press,
    );
  }
}

void _soot(Canvas c, Color color) {
  final pile = Path()
    ..moveTo(14, 78)
    ..quadraticBezierTo(30, 42, 50, 40)
    ..quadraticBezierTo(72, 42, 86, 78)
    ..close();
  paintPlastic(c, pile, color, edge: 2, shine: .3);
  for (final (x, y, r) in const [
    (26.0, 30.0, 3.0),
    (70.0, 26.0, 2.4),
    (58.0, 18.0, 2.0),
    (38.0, 22.0, 1.8),
  ]) {
    c.drawCircle(Offset(x, y), r, _fill(Art.light(color, .2)));
  }
}

void _drop(Canvas c, Color color) {
  paintPlastic(c, _oval(50, 82, 60, 12), Art.light(color, .4), edge: 1.4);
  final drop = Path()
    ..moveTo(50, 12)
    ..quadraticBezierTo(76, 46, 74, 58)
    ..quadraticBezierTo(72, 80, 50, 80)
    ..quadraticBezierTo(28, 80, 26, 58)
    ..quadraticBezierTo(24, 46, 50, 12)
    ..close();
  paintPlastic(c, drop, color, edge: 2, shine: .7);
  _gleam(c, 40, 50, 5);
}

void _yomogi(Canvas c, Color color) {
  c.drawLine(const Offset(50, 86), const Offset(50, 22), _line(_leafDark, 3));
  for (final (y, dir) in const [
    (70.0, -1.0),
    (62.0, 1.0),
    (50.0, -1.0),
    (42.0, 1.0),
    (30.0, -1.0),
  ]) {
    _leafShape(c, Offset(50, y), Offset(50 + dir * 30, y - 12), color, .35);
    _leafShape(
      c,
      Offset(50 + dir * 14, y - 5),
      Offset(50 + dir * 22, y - 18),
      Art.light(color, .15),
      .3,
    );
  }
  _leafShape(c, const Offset(50, 24), const Offset(50, 8), color, .4);
}

void _ai(Canvas c, Color color) {
  // Tallos de añil con sus hojas y las espigas rosas.
  final stem = _line(const Color(0xFF8A4F6E), 2.4);
  for (final (x, top) in const [(36.0, 26.0), (52.0, 18.0), (66.0, 28.0)]) {
    c.drawLine(Offset(x, 86), Offset(x, top), stem);
    for (var y = top + 18; y < 80; y += 16) {
      _leafShape(c, Offset(x, y), Offset(x - 14, y - 6), color, .45);
      _leafShape(c, Offset(x, y + 6), Offset(x + 14, y), color, .45);
    }
    for (var i = 0; i < 4; i++) {
      paintPlastic(
        c,
        _circle(x, top - i * 4.0, 2.6),
        const Color(0xFFF28DB2),
        edge: .8,
        shine: .2,
      );
    }
  }
}

void _clothPattern(Canvas c, String id) {
  final ink = _line(T.shellTop.withValues(alpha: .85), 1.6);
  if (id == 'cloth_blue') {
    // Olas (seigaiha) sobre el añil.
    for (final (x, y) in const [(30.0, 64.0), (46.0, 70.0), (62.0, 64.0)]) {
      for (final r in const [8.0, 5.0]) {
        c.drawArc(
          Rect.fromCircle(center: Offset(x, y), radius: r),
          math.pi,
          math.pi,
          false,
          ink,
        );
      }
    }
  } else if (id == 'cloth_red') {
    for (final (x, y) in const [
      (28.0, 62.0),
      (42.0, 70.0),
      (56.0, 64.0),
      (70.0, 60.0),
      (34.0, 32.0),
      (58.0, 30.0),
    ]) {
      c.drawCircle(Offset(x, y), 2.2, _fill(T.shellTop));
    }
  }
}

// --- Cerámica --------------------------------------------------------------------

void _pottery(Canvas c, String id, Color color) {
  switch (id) {
    case 'pot_bowl':
      _bowl(c, color, () {});
      c.drawLine(
        const Offset(20, 62),
        const Offset(80, 62),
        _line(Art.light(color, .45), 2),
      );
    case 'pot_brick':
      for (final (x, y) in const [(14.0, 60.0), (50.0, 60.0), (32.0, 36.0)]) {
        paintPlastic(c, _rrect(x, y, 36, 22, 3), color, edge: 1.8, shine: .3);
        c.drawLine(
          Offset(x + 4, y + 16),
          Offset(x + 32, y + 16),
          _line(Art.deep(color, .18), 1),
        );
      }
    case 'pot_flask':
      paintPlastic(c, _rrect(42, 14, 16, 10, 3), _handle, edge: 1.4);
      paintPlastic(c, _rrect(40, 22, 20, 18, 4), color, edge: 1.8);
      paintPlastic(c, _circle(50, 60, 26), color, edge: 2);
      c.drawLine(
        const Offset(26, 60),
        const Offset(74, 60),
        _line(Art.deep(color, .2), 2),
      );
    case 'pot_tile':
      // Tejas kawara en fila, unas encima de otras.
      for (var i = 0; i < 3; i++) {
        final x = 16.0 + i * 22;
        final tile = Path()
          ..moveTo(x, 80)
          ..lineTo(x, 36)
          ..quadraticBezierTo(x + 13, 22, x + 26, 36)
          ..lineTo(x + 26, 80)
          ..close();
        paintPlastic(c, tile, Art.deep(color, i * .06), edge: 1.8);
        paintPlastic(
          c,
          _oval(x + 13, 80, 26, 10),
          Art.deep(color, .25),
          edge: 1.2,
        );
      }
    case 'pot_teapot':
      // Kyusu: el asa de lado.
      paintPlastic(
        c,
        _poly(const [
          Offset(70, 56),
          Offset(92, 40),
          Offset(95, 46),
          Offset(74, 64),
        ]),
        Art.deep(color, .1),
        edge: 1.6,
      );
      final spout = Path()
        ..moveTo(28, 62)
        ..quadraticBezierTo(14, 58, 10, 44)
        ..lineTo(17, 42)
        ..quadraticBezierTo(20, 52, 30, 54)
        ..close();
      paintPlastic(c, spout, color, edge: 1.6);
      paintPlastic(c, _oval(50, 62, 50, 38), color, edge: 2);
      paintPlastic(c, _oval(50, 44, 28, 8), Art.deep(color, .15), edge: 1.4);
      paintPlastic(c, _circle(50, 40, 3.5), Art.deep(color, .3), edge: 1);
    case 'pot_planter':
      final pot = Path()
        ..moveTo(24, 50)
        ..lineTo(76, 50)
        ..lineTo(68, 84)
        ..lineTo(32, 84)
        ..close();
      c.drawLine(
        const Offset(50, 50),
        const Offset(50, 24),
        _line(_leafDark, 3),
      );
      _leafShape(c, const Offset(50, 34), const Offset(30, 18), _leaf, .5);
      _leafShape(c, const Offset(50, 30), const Offset(70, 14), _leaf, .5);
      paintPlastic(c, pot, color, edge: 2);
      paintPlastic(
        c,
        _rrect(20, 44, 60, 12, 4),
        Art.deep(color, .1),
        edge: 1.8,
      );
    case 'pot_vase' || 'pot_celadon':
      final vase = Path()
        ..moveTo(42, 16)
        ..lineTo(58, 16)
        ..quadraticBezierTo(56, 30, 64, 40)
        ..quadraticBezierTo(80, 58, 66, 84)
        ..lineTo(34, 84)
        ..quadraticBezierTo(20, 58, 36, 40)
        ..quadraticBezierTo(44, 30, 42, 16)
        ..close();
      paintPlastic(c, vase, color, edge: 2, shine: .7);
      if (id == 'pot_celadon') {
        final crackle = _line(Art.deep(color, .25), .9);
        c
          ..drawLine(const Offset(38, 52), const Offset(48, 60), crackle)
          ..drawLine(const Offset(48, 60), const Offset(44, 72), crackle)
          ..drawLine(const Offset(58, 48), const Offset(64, 62), crackle)
          ..drawLine(const Offset(64, 62), const Offset(56, 74), crackle);
      } else {
        _blossom(c, 50, 62, 7, T.shellTop);
        c.drawLine(
          const Offset(30, 72),
          const Offset(70, 72),
          _line(T.shellTop, 1.6),
        );
      }
  }
}

void _dyeJar(Canvas c, Color color) {
  const jar = Color(0xFF7A6A5E);
  paintPlastic(c, _oval(50, 36, 64, 18), Art.deep(jar, .2), edge: 1.6);
  paintPlastic(c, _oval(50, 37, 54, 12), color, edge: 1, shine: .6);
  final body = Path()
    ..moveTo(18, 38)
    ..quadraticBezierTo(14, 72, 30, 84)
    ..lineTo(70, 84)
    ..quadraticBezierTo(86, 72, 82, 38)
    ..quadraticBezierTo(50, 48, 18, 38)
    ..close();
  paintPlastic(c, body, jar, edge: 2);
  // El tinte que chorrea por el borde.
  final drip = Path()
    ..moveTo(26, 42)
    ..quadraticBezierTo(24, 56, 29, 58)
    ..quadraticBezierTo(33, 56, 32, 44)
    ..close();
  paintPlastic(c, drip, color, edge: .8);
  c.drawLine(
    const Offset(20, 64),
    const Offset(80, 64),
    _line(Art.light(jar, .25), 2),
  );
}

// --- Construcción -------------------------------------------------------------------

void _building(Canvas c, String id, Color color) {
  switch (id) {
    case 'build_beam':
      _turned(c, 50, 52, -.3, () {
        paintPlastic(c, _rrect(10, 40, 80, 22, 3), color, edge: 2);
        paintPlastic(
          c,
          _rrect(66, 40, 10, 11, 1),
          Art.deep(color, .3),
          edge: 1,
        );
        for (final y in const [47.0, 55.0]) {
          c.drawLine(
            Offset(14, y),
            Offset(62, y),
            _line(Art.deep(color, .15), 1),
          );
        }
      });
    case 'build_frame':
      final wood = _line(Art.deep(color, .35), 12);
      final face = _line(color, 9);
      for (final p in [wood, face]) {
        c.drawRect(const Rect.fromLTRB(22, 22, 78, 78), p);
        c.drawLine(const Offset(22, 78), const Offset(78, 22), p);
      }
      for (final (x, y) in const [
        (22.0, 22.0),
        (78.0, 22.0),
        (22.0, 78.0),
        (78.0, 78.0),
      ]) {
        paintPlastic(c, _rrect(x - 7, y - 7, 14, 14, 2), _metal, edge: 1.2);
      }
    case 'build_wall':
      paintPlastic(
        c,
        _rrect(12, 28, 76, 54, 3),
        const Color(0xFFC0613F),
        edge: 2,
      );
      final mortar = _line(const Color(0xFFE9D8C4), 1.6);
      for (var row = 0; row < 4; row++) {
        final y = 42.0 + row * 13;
        c.drawLine(Offset(12, y), Offset(88, y), mortar);
        for (var x = 20.0 + (row.isEven ? 0 : 9); x < 88; x += 18) {
          c.drawLine(Offset(x, y - 13), Offset(x, y), mortar);
        }
      }
      paintPlastic(c, _rrect(8, 20, 84, 12, 4), color, edge: 1.8);
    case 'build_roof':
      final roof = Path()
        ..moveTo(6, 72)
        ..quadraticBezierTo(30, 60, 50, 22)
        ..quadraticBezierTo(70, 60, 94, 72)
        ..close();
      paintPlastic(c, roof, color, edge: 2);
      final rows = _line(Art.light(color, .2), 1.6);
      for (final t in const [.35, .6, .85]) {
        c.drawLine(
          Offset(50 - 42 * t, 26 + 44 * t),
          Offset(50 + 42 * t, 26 + 44 * t),
          rows,
        );
      }
      paintPlastic(
        c,
        _rrect(20, 72, 60, 10, 2),
        _tones['plank_kaede']!,
        edge: 1.6,
      );
    case 'build_shoji':
      paintPlastic(c, _rrect(20, 12, 60, 78, 3), _handle, edge: 2);
      paintPlastic(c, _rrect(26, 18, 48, 66, 1), color, edge: 1, shine: .2);
      final lattice = _line(Art.deep(_handle, .1), 2);
      for (var x = 38.0; x < 74; x += 12) {
        c.drawLine(Offset(x, 18), Offset(x, 84), lattice);
      }
      for (var y = 29.0; y < 84; y += 11) {
        c.drawLine(Offset(26, y), Offset(74, y), lattice);
      }
    case 'build_pillar':
      paintPlastic(c, _rrect(34, 20, 32, 62, 4), color, edge: 2, shine: .6);
      for (final y in const [14.0, 78.0]) {
        paintPlastic(c, _rrect(28, y, 44, 10, 3), Art.gold, edge: 1.6);
      }
      paintPlastic(c, _rrect(34, 44, 32, 6, 1), Art.gold, edge: 1);
    default:
      // Shachihoko: el pez dorado de los tejados, con la cola arriba.
      _turned(c, 50, 54, -1.1, () => _fish(c, color, h: 34, spiky: true));
      paintTwinkle(c, const Offset(78, 24), 6, Art.spark);
  }
}

// --- Escritura -----------------------------------------------------------------------

void _paper(Canvas c, Color color) {
  for (var i = 0; i < 3; i++) {
    _turned(c, 50, 54, -.12 + i * .1, () {
      paintPlastic(
        c,
        _rrect(22, 24 + i * 2.0, 56, 60, 2),
        Art.deep(color, .08 - i * .03),
        edge: 1.6,
        shine: .2,
      );
    });
  }
  final fiber = _line(Art.deep(color, .12), .8);
  c
    ..drawLine(const Offset(32, 44), const Offset(50, 46), fiber)
    ..drawLine(const Offset(44, 60), const Offset(66, 58), fiber);
}

void _ink(Canvas c, Color color) {
  // Suzuri (la piedra) con la barra de sumi apoyada.
  paintPlastic(c, _rrect(14, 52, 72, 30, 8), const Color(0xFF55525E), edge: 2);
  paintPlastic(c, _oval(38, 66, 36, 14), color, edge: 1, shine: .7);
  _turned(c, 62, 40, .55, () {
    paintPlastic(c, _rrect(54, 10, 16, 58, 3), color, edge: 1.8);
    c.drawLine(
      const Offset(58, 22),
      const Offset(58, 40),
      _line(Art.gold, 1.6),
    );
  });
}

void _book(Canvas c, String id, Color color) {
  final thick = switch (id) {
    'book_notes' => 6.0,
    'book_basic' => 10.0,
    'book_tome' => 14.0,
    _ => 16.0,
  };
  paintPlastic(
    c,
    _rrect(24, 22 + thick, 56, 58, 3),
    _rice,
    edge: 1.6,
    shine: 0,
  );
  paintPlastic(c, _rrect(20, 16, 60, 64, 3), color, edge: 2);
  // Encuadernación japonesa: el cosido en el lomo.
  final thread = _line(Art.light(color, .6), 1.6);
  for (final y in const [24.0, 38.0, 52.0, 66.0]) {
    c
      ..drawLine(Offset(20, y), Offset(30, y), thread)
      ..drawCircle(Offset(30, y), 1.4, _fill(Art.light(color, .6)));
  }
  paintPlastic(c, _rrect(56, 22, 14, 36, 1), T.shellTop, edge: 1, shine: 0);
  if (id == 'book_arcane') {
    paintTwinkle(c, const Offset(63, 70), 6, Art.spark);
  }
}

void _map(Canvas c, String id, Color color) {
  final paper = Path()
    ..moveTo(14, 30)
    ..lineTo(38, 24)
    ..lineTo(62, 32)
    ..lineTo(86, 26)
    ..lineTo(86, 76)
    ..lineTo(62, 82)
    ..lineTo(38, 74)
    ..lineTo(14, 80)
    ..close();
  paintPlastic(c, paper, color, edge: 2);
  final ink = id == 'map_star' ? Art.spark : const Color(0xFF8A5E3E);
  c.drawPath(
    Path()
      ..moveTo(22, 70)
      ..quadraticBezierTo(34, 44, 50, 56)
      ..quadraticBezierTo(62, 64, 74, 40),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = ink,
  );
  final x = _line(const Color(0xFFE8475F), 2.6);
  c
    ..drawLine(const Offset(70, 36), const Offset(78, 44), x)
    ..drawLine(const Offset(78, 36), const Offset(70, 44), x);
  if (id == 'map_star') {
    paintTwinkle(c, const Offset(30, 38), 4, Art.spark);
    paintTwinkle(c, const Offset(56, 42), 3, T.shellTop);
  } else if (id == 'map_chart') {
    final wave = _line(const Color(0xFF52A0D9), 1.4);
    for (final y in const [40.0, 66.0]) {
      c.drawPath(
        Path()
          ..moveTo(20, y)
          ..quadraticBezierTo(26, y - 4, 32, y)
          ..quadraticBezierTo(38, y + 4, 44, y),
        wave,
      );
    }
  }
}

// --- Brebajes y magia -------------------------------------------------------------------

void _potion(Canvas c, String id, Color color) {
  const glass = Color(0xFFE6F4FA);
  paintPlastic(c, _rrect(42, 12, 16, 10, 3), _handle, edge: 1.4);
  paintPlastic(c, _rrect(41, 20, 18, 16, 3), glass, edge: 1.6, shine: .4);
  paintPlastic(c, _circle(50, 60, 27), glass, edge: 2, shine: .2);
  final liquid = Path()
    ..addArc(
      Rect.fromCircle(center: const Offset(50, 60), radius: 23),
      -.25,
      math.pi + .5,
    )
    ..close();
  paintPlastic(c, liquid, color, edge: 0, shine: .5);
  c.drawCircle(const Offset(44, 62), 3, _fill(Art.light(color, .5)));
  c.drawCircle(const Offset(56, 70), 2, _fill(Art.light(color, .5)));
  _gleam(c, 38, 48, 5);
  if (id == 'potion_elixir') {
    paintTwinkle(c, const Offset(78, 30), 6, Art.spark);
  }
}

void _rune(Canvas c, String id, Color color) {
  // Una tablilla de piedra con la gema engastada y su trazo.
  const stone = Color(0xFF8C8698);
  final tablet = Path()
    ..moveTo(50, 12)
    ..lineTo(82, 30)
    ..lineTo(82, 70)
    ..lineTo(50, 88)
    ..lineTo(18, 70)
    ..lineTo(18, 30)
    ..close();
  paintPlastic(c, tablet, stone, edge: 2);
  final glow = _line(Art.light(color, .2), 2.4);
  c
    ..drawLine(const Offset(50, 22), const Offset(50, 36), glow)
    ..drawLine(const Offset(50, 64), const Offset(50, 78), glow)
    ..drawLine(const Offset(28, 38), const Offset(38, 44), glow)
    ..drawLine(const Offset(72, 62), const Offset(62, 56), glow);
  _brilliant(c, color, 50, 52, .5);
  if (id == 'rune_star' || id == 'rune_titan') {
    paintTwinkle(c, const Offset(80, 18), 6, Art.spark);
  }
}

// --- Cebos, abonos y mechas ---------------------------------------------------------

void _worms(Canvas c, Color color) {
  paintPlastic(c, _rrect(22, 44, 56, 40, 6), _metal, edge: 2);
  paintPlastic(c, _oval(50, 44, 56, 14), const Color(0xFF6B4A32), edge: 1.4);
  final worm = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round
    ..color = color;
  c
    ..drawPath(
      Path()
        ..moveTo(36, 44)
        ..quadraticBezierTo(30, 26, 42, 24)
        ..quadraticBezierTo(50, 24, 48, 34),
      worm,
    )
    ..drawPath(
      Path()
        ..moveTo(58, 46)
        ..quadraticBezierTo(66, 30, 72, 36),
      worm,
    );
  c.drawLine(
    const Offset(24, 64),
    const Offset(76, 64),
    _line(Art.deep(_metal, .2), 1.4),
  );
}

void _lure(Canvas c, Color color) {
  c.drawLine(const Offset(80, 14), const Offset(70, 36), _line(T.inkSoft, 1.2));
  _turned(c, 50, 54, -.35, () => _fish(c, color, h: 30));
  final hook = _line(_metal, 2.4);
  c.drawPath(
    Path()
      ..moveTo(34, 70)
      ..lineTo(34, 82)
      ..quadraticBezierTo(34, 88, 28, 86)
      ..lineTo(28, 82),
    hook,
  );
}

void _sack(Canvas c, Color color, {required bool rich}) {
  const burlap = Color(0xFFD9BC8A);
  final sack = Path()
    ..moveTo(34, 30)
    ..quadraticBezierTo(14, 50, 20, 76)
    ..quadraticBezierTo(24, 86, 50, 86)
    ..quadraticBezierTo(76, 86, 80, 76)
    ..quadraticBezierTo(86, 50, 66, 30)
    ..close();
  paintPlastic(c, sack, burlap, edge: 2);
  paintPlastic(c, _oval(50, 26, 40, 14), color, edge: 1.4, shine: .3);
  c.drawLine(
    const Offset(34, 32),
    const Offset(66, 32),
    _line(Art.deep(burlap, .4), 3),
  );
  _leafShape(c, const Offset(50, 64), const Offset(38, 50), _leaf, .5);
  _leafShape(c, const Offset(50, 64), const Offset(62, 50), _leaf, .5);
  if (rich) paintTwinkle(c, const Offset(76, 20), 6, Art.spark);
}

void _fuse(Canvas c, Color color, {required bool star}) {
  _turned(c, 50, 56, -.35, () {
    paintPlastic(c, _rrect(30, 34, 40, 50, 8), color, edge: 2);
    paintPlastic(c, _rrect(30, 50, 40, 8, 0), T.shellTop, edge: 0, shine: 0);
  });
  c.drawPath(
    Path()
      ..moveTo(56, 30)
      ..quadraticBezierTo(62, 14, 74, 18),
    _line(Art.fuse, 2.4),
  );
  paintTwinkle(
    c,
    const Offset(76, 16),
    star ? 8 : 6,
    star ? Art.spark : Art.sparkHot,
  );
}

// --- Oficios ----------------------------------------------------------------------------

/// Los iconos de los oficios nuevos.
void _paintCraftSkill(Canvas c, HSkill skill) {
  switch (skill) {
    case HSkill.pottery:
      // Torno con una vasija a medio hacer.
      paintPlastic(c, _oval(50, 78, 72, 16), const Color(0xFF6E5440), edge: 2);
      paintPlastic(
        c,
        _oval(50, 72, 64, 14),
        const Color(0xFF8E6E52),
        edge: 1.6,
      );
      _scaled(
        c,
        50,
        46,
        .7,
        () => _pottery(c, 'pot_vase', _craftTones['clay']!),
      );
    case HSkill.dyeing:
      _dyeJar(c, _craftTones['dye_blue']!);
      _turned(c, 66, 30, .5, () {
        paintPlastic(c, _rrect(62, 4, 8, 40, 3), _handle, edge: 1.4);
      });
    case HSkill.construction:
      _scaled(
        c,
        50,
        58,
        .8,
        () => _building(c, 'build_roof', _craftTones['build_roof']!),
      );
      _turned(c, 70, 30, -.6, () {
        paintPlastic(c, _rrect(67, 26, 6, 34, 3), _handle, edge: 1.2);
        paintPlastic(c, _rrect(58, 18, 24, 11, 3), _metal, edge: 1.6);
      });
    case HSkill.writing:
      _paper(c, _craftTones['paper']!);
      c.drawPath(
        Path()
          ..moveTo(36, 40)
          ..quadraticBezierTo(46, 36, 44, 50)
          ..quadraticBezierTo(42, 62, 56, 60),
        _line(_craftTones['ink']!, 3.4),
      );
      _turned(c, 70, 40, .6, () {
        paintPlastic(
          c,
          _rrect(67, 4, 7, 44, 3),
          const Color(0xFFC9A061),
          edge: 1.2,
        );
        paintPlastic(
          c,
          _poly(const [Offset(67, 48), Offset(74, 48), Offset(70.5, 60)]),
          _craftTones['ink']!,
          edge: 1,
        );
      });
    case HSkill.brewing:
      // Un caldero pequeño y un frasco al lado.
      _steam(c, 40, 22);
      paintPlastic(c, _oval(40, 58, 56, 44), const Color(0xFF3F4652), edge: 2);
      paintPlastic(
        c,
        _oval(40, 42, 50, 12),
        _craftTones['potion_luck']!,
        edge: 1,
        shine: .6,
      );
      _scaled(
        c,
        76,
        66,
        .45,
        () => _potion(c, 'potion_heal', _craftTones['potion_heal']!),
      );
    case HSkill.magic:
      // Varita con su estrella y chispas.
      _turned(c, 50, 54, .7, () {
        paintPlastic(
          c,
          _rrect(46, 30, 8, 58, 4),
          const Color(0xFF5A4A7A),
          edge: 1.6,
        );
      });
      paintTwinkle(c, const Offset(34, 34), 18, Art.spark);
      paintTwinkle(c, const Offset(70, 24), 6, _craftTones['rune_star']!);
      paintTwinkle(c, const Offset(20, 64), 5, T.shellTop);
    case HSkill.study:
      _book(c, 'book_tome', _craftTones['book_tome']!);
      c.drawCircle(
        const Offset(72, 26),
        10,
        _line(const Color(0xFF8A5E3E), 2.6),
      );
      c.drawCircle(const Offset(72, 26), 8, _fill(const Color(0x66CFEFFF)));
    default:
      paintPlastic(c, _circle(50, 54, 20), T.shellTop);
  }
}
