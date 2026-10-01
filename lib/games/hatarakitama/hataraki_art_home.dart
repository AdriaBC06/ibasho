// Ibasho — Hatarakitama: las casas, los muebles y los planos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_art.dart';

const Map<String, Color> _furnitureTones = {
  'fu_stool': Color(0xFFD99A5B),
  'fu_zabuton': Color(0xFFE07A5F),
  'fu_sign': Color(0xFFE8B878),
  'fu_chabudai': Color(0xFFB9824E),
  'fu_bonsai': Color(0xFF5DB15E),
  'fu_futon': Color(0xFFE8A04C),
  'fu_andon': Color(0xFFFBDCA0),
  'fu_boat': Color(0xFFD99A5B),
  'fu_aquarium': Color(0xFF7EC8F0),
  'fu_rug_wave': Color(0xFF3558A8),
  'fu_hammock': Color(0xFF4F86D9),
  'fu_seachart': Color(0xFFD6E8F2),
  'fu_shell_lamp': Color(0xFFF7C4C0),
  'fu_scroll': Color(0xFFFBF7EC),
  'fu_rug_red': Color(0xFFD9404F),
  'fu_tansu': Color(0xFFB5634B),
  'fu_celadon': Color(0xFF9FD1BD),
  'fu_silk_futon': Color(0xFFE884B0),
  'fu_maneki': Color(0xFFFFFBF4),
  'fu_lantern': Color(0xFFB9A4F2),
  'fu_crystal': Color(0xFFA56BE3),
  'fu_bookcase': Color(0xFF5B3F7A),
  'fu_orrery': Color(0xFFF7C948),
  'fu_candles': Color(0xFFF4ECFF),
  'fu_flowerbowl': Color(0xFF8FB8A8),
  'fu_noren': Color(0xFFF58DB6),
  'fu_blossom_lamp': Color(0xFFF7B6C8),
  'fu_ikebana': Color(0xFF6F8FD6),
  'fu_flowerstand': Color(0xFFD27F4E),
};

const Color _glow = Color(0xFFFFE08A);
const Color _white = Color(0xFFFFFFFF);
const Color _cream = Color(0xFFFFF6E4);

/// Un resplandor suave detrás de lo que da luz.
void _halo(Canvas c, double x, double y, double r, Color color) {
  c.drawCircle(
    Offset(x, y),
    r,
    Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: .55), color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r)),
  );
}

/// Pinta un mueble. Todos caben en el lienzo de 100×100, de pie sobre el
/// suelo (hacia y = 88).
void _furniture(Canvas c, String id, Color color) {
  final deep = Art.deep(color, .35);
  switch (id) {
    case 'fu_stool':
      paintPlastic(c, _rrect(46, 50, 8, 30, 3), Art.deep(color, .25), edge: 1);
      for (final x in const [27.0, 66.0]) {
        paintPlastic(c, _rrect(x, 50, 8, 36, 3), color, edge: 1.2);
      }
      c.drawLine(const Offset(31, 70), const Offset(70, 70), _line(deep, 2.4));
      paintPlastic(c, _oval(50, 48, 64, 18), Art.light(color, .2), edge: 1.6);
      _gleam(c, 40, 44);
    case 'fu_zabuton':
      paintPlastic(c, _rrect(12, 52, 76, 32, 16), color, edge: 1.8);
      final seam = _line(deep, 1.4);
      c
        ..drawLine(const Offset(22, 60), const Offset(78, 60), seam)
        ..drawLine(const Offset(22, 76), const Offset(78, 76), seam);
      paintPlastic(c, _circle(50, 68, 4), deep, edge: .8);
      for (final (x, y) in const [(14.0, 54.0), (86.0, 54.0)]) {
        paintPlastic(c, _circle(x, y, 3.5), const Color(0xFFF7C948), edge: .8);
      }
      _gleam(c, 34, 57);
    case 'fu_sign':
      paintPlastic(c, _rrect(46, 48, 8, 40, 3), _handle, edge: 1.2);
      paintPlastic(c, _rrect(14, 20, 72, 36, 6), color, edge: 1.8);
      final ink = _line(const Color(0xFF2B2A33), 3);
      c
        ..drawLine(const Offset(28, 32), const Offset(40, 32), ink)
        ..drawLine(const Offset(34, 28), const Offset(34, 46), ink)
        ..drawLine(const Offset(52, 30), const Offset(70, 30), ink)
        ..drawLine(const Offset(56, 38), const Offset(68, 44), ink);
      c
        ..drawCircle(const Offset(22, 26), 2, _fill(deep))
        ..drawCircle(const Offset(78, 26), 2, _fill(deep));
    case 'fu_chabudai':
      for (final x in const [24.0, 70.0]) {
        paintPlastic(c, _rrect(x, 54, 7, 30, 3), deep, edge: 1);
      }
      paintPlastic(c, _oval(50, 54, 90, 18), deep, edge: 1.2, shine: 0);
      paintPlastic(c, _oval(50, 50, 88, 26), color, edge: 1.8);
      paintPlastic(c, _rrect(56, 36, 12, 12, 4), _china, edge: 1);
      c.drawLine(const Offset(58, 40), const Offset(66, 40), _line(_leaf, 2));
      _gleam(c, 34, 44);
    case 'fu_bonsai':
      final trunk = Path()
        ..moveTo(48, 70)
        ..quadraticBezierTo(40, 56, 52, 46)
        ..quadraticBezierTo(62, 38, 54, 30);
      c.drawPath(trunk, _line(const Color(0xFF7A5230), 7));
      for (final (x, y, w) in const [
        (36.0, 40.0, 30.0),
        (62.0, 30.0, 30.0),
        (50.0, 22.0, 26.0),
      ]) {
        paintPlastic(c, _oval(x, y, w, w * .55), color, edge: 1.4);
      }
      paintPlastic(c, _rrect(24, 66, 52, 16, 5), const Color(0xFF5E6B7A));
      c.drawLine(const Offset(26, 70), const Offset(74, 70), _line(_stone, 2));
    case 'fu_futon' || 'fu_silk_futon':
      final silk = id == 'fu_silk_futon';
      paintPlastic(c, _rrect(10, 52, 80, 30, 10), _cream, edge: 1.6);
      paintPlastic(c, _rrect(14, 40, 26, 16, 8), _white, edge: 1.2);
      paintPlastic(c, _rrect(34, 50, 56, 32, 10), color, edge: 1.8);
      final pattern = _line(
        silk ? const Color(0xFFF7C948) : Art.light(color, .4),
        2,
      );
      for (final x in const [48.0, 62.0, 76.0]) {
        c.drawLine(Offset(x, 54), Offset(x, 78), pattern);
      }
      if (silk) {
        _blossom(c, 62, 66, 7, const Color(0xFFFFFFFF));
        paintTwinkle(c, const Offset(84, 42), 4, const Color(0xFFF7C948));
      }
    case 'fu_andon':
      _halo(c, 50, 50, 42, _glow);
      paintPlastic(c, _rrect(30, 24, 40, 56, 5), color, edge: 1.4, shine: .6);
      final frame = _line(_handle, 3);
      c
        ..drawLine(const Offset(30, 24), const Offset(30, 86), frame)
        ..drawLine(const Offset(70, 24), const Offset(70, 86), frame)
        ..drawLine(const Offset(28, 24), const Offset(72, 24), frame)
        ..drawLine(const Offset(28, 80), const Offset(72, 80), frame)
        ..drawLine(
          const Offset(30, 52),
          const Offset(70, 52),
          _line(_handle, 1.4),
        );
      c.drawCircle(const Offset(50, 60), 6, _fill(_glow.withValues(alpha: .8)));
    case 'fu_boat':
      paintPlastic(c, _rrect(30, 76, 40, 8, 3), Art.deep(color, .45), edge: 1);
      c.drawLine(const Offset(50, 16), const Offset(50, 62), _line(deep, 3));
      paintPlastic(
        c,
        _poly(const [Offset(53, 18), Offset(80, 54), Offset(53, 54)]),
        const Color(0xFFFFFFFF),
        edge: 1.2,
      );
      c.drawLine(
        const Offset(55, 44),
        const Offset(72, 44),
        _line(const Color(0xFF4F86D9), 3),
      );
      paintPlastic(
        c,
        _poly(const [
          Offset(12, 58),
          Offset(88, 58),
          Offset(74, 76),
          Offset(26, 76),
        ]),
        color,
        edge: 1.8,
      );
      c.drawLine(const Offset(18, 64), const Offset(82, 64), _line(deep, 1.6));
    case 'fu_aquarium':
      paintPlastic(c, _rrect(34, 78, 32, 8, 3), _handle, edge: 1);
      final bowl = _circle(50, 52, 30);
      c.drawPath(bowl, _fill(const Color(0x55CFEFFF)));
      c
        ..save()
        ..clipPath(bowl)
        ..drawRect(
          const Rect.fromLTWH(18, 44, 64, 40),
          _fill(color.withValues(alpha: .7)),
        )
        ..restore();
      _leafShape(c, const Offset(40, 80), const Offset(36, 56), _leaf, .3);
      _scaled(c, 56, 60, .32, () => _shape(c, 'fish_kinkoi'));
      c
        ..drawPath(bowl, _line(const Color(0xFF8FC9E6), 2))
        ..drawOval(
          Rect.fromCenter(center: const Offset(50, 24), width: 36, height: 8),
          _line(const Color(0xFF8FC9E6), 2),
        );
      _gleam(c, 36, 38, 4);
    case 'fu_rug_wave' || 'fu_rug_red':
      final rug = _poly(const [
        Offset(22, 46),
        Offset(78, 46),
        Offset(94, 82),
        Offset(6, 82),
      ]);
      paintPlastic(c, rug, color, edge: 1.6, shine: .3);
      c
        ..save()
        ..clipPath(rug);
      if (id == 'fu_rug_wave') {
        final wave = _line(Art.light(color, .6), 2);
        for (var row = 0; row < 4; row++) {
          for (var i = -1; i < 7; i++) {
            final x = i * 16.0 + (row.isOdd ? 8 : 0);
            final y = 54.0 + row * 9;
            c.drawArc(
              Rect.fromCircle(center: Offset(x, y), radius: 7),
              math.pi,
              math.pi,
              false,
              wave,
            );
          }
        }
      } else {
        for (final (x, y) in const [(50.0, 64.0), (28.0, 64.0), (72.0, 64.0)]) {
          paintPlastic(
            c,
            _poly([
              Offset(x, y - 8),
              Offset(x + 8, y),
              Offset(x, y + 8),
              Offset(x - 8, y),
            ]),
            const Color(0xFFF7C948),
            edge: .8,
            shine: .3,
          );
        }
      }
      c.restore();
      c.drawPath(
        rug,
        _line(id == 'fu_rug_red' ? const Color(0xFFF7C948) : _cream, 2.4),
      );
    case 'fu_hammock':
      for (final x in const [8.0, 86.0]) {
        paintPlastic(c, _rrect(x, 24, 7, 62, 3), _handle, edge: 1.2);
      }
      final cloth = Path()
        ..moveTo(15, 36)
        ..quadraticBezierTo(50, 88, 86, 36)
        ..quadraticBezierTo(50, 70, 15, 36)
        ..close();
      paintPlastic(c, cloth, color, edge: 1.6);
      c.drawPath(
        Path()
          ..moveTo(22, 44)
          ..quadraticBezierTo(50, 80, 78, 44),
        _line(const Color(0xFFFFFFFF), 2.4),
      );
    case 'fu_seachart':
      for (final (a, b) in const [
        (Offset(30, 60), Offset(22, 88)),
        (Offset(70, 60), Offset(78, 88)),
      ]) {
        c.drawLine(a, b, _line(_handle, 4));
      }
      paintPlastic(c, _rrect(14, 14, 72, 56, 4), const Color(0xFF8A5530));
      paintPlastic(c, _rrect(20, 20, 60, 44, 2), color, edge: 1, shine: .4);
      c.drawPath(
        Path()
          ..moveTo(26, 54)
          ..quadraticBezierTo(40, 30, 56, 44)
          ..quadraticBezierTo(66, 52, 74, 28),
        _line(const Color(0xFFE0394E), 1.6),
      );
      paintTwinkle(c, const Offset(64, 50), 7, const Color(0xFF3558A8));
      paintPlastic(c, _oval(34, 34, 14, 9), const Color(0xFFD9C29A), edge: .8);
    case 'fu_shell_lamp':
      _halo(c, 50, 38, 36, const Color(0xFFFFC7C0));
      c.drawLine(const Offset(50, 56), const Offset(50, 78), _line(_metal, 3));
      paintPlastic(c, _oval(50, 82, 34, 10), const Color(0xFFB7BEC7));
      _scaled(c, 50, 42, .62, () => _shape(c, 'rare_shell'));
    case 'fu_scroll':
      paintPlastic(c, _rrect(28, 14, 44, 66, 2), const Color(0xFF3558A8));
      paintPlastic(c, _rrect(33, 20, 34, 52, 1), color, edge: .8, shine: .2);
      final ink = _line(const Color(0xFF2B2A33), 1.8);
      c
        ..drawPath(
          Path()
            ..moveTo(36, 56)
            ..lineTo(46, 40)
            ..lineTo(52, 48)
            ..lineTo(58, 36)
            ..lineTo(64, 56),
          ink,
        )
        ..drawCircle(const Offset(58, 28), 4, _fill(const Color(0xFFE0394E)));
      paintPlastic(c, _rrect(24, 10, 52, 6, 3), const Color(0xFF3A2A20));
      paintPlastic(c, _rrect(22, 78, 56, 7, 3.5), const Color(0xFF3A2A20));
    case 'fu_tansu':
      paintPlastic(c, _rrect(12, 24, 76, 60, 4), color, edge: 1.8);
      final line = _line(deep, 1.6);
      for (final y in const [44.0, 64.0]) {
        c.drawLine(Offset(14, y), Offset(86, y), line);
      }
      c.drawLine(const Offset(50, 24), const Offset(50, 44), line);
      for (final (x, y) in const [
        (31.0, 34.0),
        (69.0, 34.0),
        (50.0, 54.0),
        (50.0, 74.0),
      ]) {
        paintPlastic(
          c,
          _rrect(x - 7, y - 3, 14, 6, 3),
          const Color(0xFF3A3642),
        );
      }
      for (final x in const [16.0, 76.0]) {
        paintPlastic(c, _rrect(x, 82, 8, 6, 2), deep, edge: .8);
      }
    case 'fu_celadon':
      paintPlastic(c, _rrect(28, 78, 44, 9, 3), const Color(0xFF3A2A20));
      final urn = Path()
        ..moveTo(40, 20)
        ..quadraticBezierTo(14, 44, 32, 78)
        ..lineTo(68, 78)
        ..quadraticBezierTo(86, 44, 60, 20)
        ..close();
      paintPlastic(c, urn, color, edge: 1.8);
      paintPlastic(c, _rrect(38, 14, 24, 8, 3), Art.deep(color, .15));
      paintPlastic(c, _circle(50, 11, 4), Art.deep(color, .15), edge: .8);
      final glaze = _line(Art.light(color, .5), 1.6);
      for (final y in const [44.0, 56.0]) {
        c.drawArc(
          Rect.fromCenter(center: Offset(50, y), width: 40, height: 10),
          0,
          math.pi,
          false,
          glaze,
        );
      }
      _gleam(c, 34, 36, 4);
    case 'fu_maneki':
      paintPlastic(c, _oval(50, 68, 48, 36), color, edge: 1.6);
      paintPlastic(c, _circle(50, 40, 20), color, edge: 1.6);
      for (final s in const [-1.0, 1.0]) {
        paintPlastic(
          c,
          _poly([
            Offset(50 + s * 18, 34),
            Offset(50 + s * 16, 18),
            Offset(50 + s * 6, 24),
          ]),
          color,
          edge: 1.2,
        );
      }
      paintPlastic(c, _oval(74, 40, 12, 18), color, edge: 1.2);
      c.drawLine(
        const Offset(36, 56),
        const Offset(64, 56),
        _line(_lacquer, 4),
      );
      paintPlastic(c, _circle(50, 60, 5), const Color(0xFFF7C948), edge: .8);
      final face = _fill(const Color(0xFF2B2A33));
      c
        ..drawCircle(const Offset(43, 40), 2, face)
        ..drawCircle(const Offset(57, 40), 2, face)
        ..drawCircle(const Offset(50, 45), 1.5, _fill(const Color(0xFFE88A8A)));
      paintPlastic(c, _circle(62, 30, 4), const Color(0xFFF2A0B0), edge: 0);
    case 'fu_lantern':
      _halo(c, 50, 48, 40, color);
      paintPlastic(c, _oval(50, 48, 44, 50), color, edge: 1.6, shine: .6);
      final rib = _line(Art.deep(color, .25), 1.4);
      for (final w in const [14.0, 30.0]) {
        c.drawOval(
          Rect.fromCenter(center: const Offset(50, 48), width: w, height: 50),
          rib,
        );
      }
      paintPlastic(c, _rrect(38, 20, 24, 6, 2), const Color(0xFF3A4750));
      paintPlastic(c, _rrect(38, 70, 24, 6, 2), const Color(0xFF3A4750));
      paintTwinkle(c, const Offset(50, 48), 8, const Color(0xFFFFFFFF));
      paintTwinkle(c, const Offset(80, 22), 4, _glow);
      paintTwinkle(c, const Offset(20, 76), 3, _glow);
    case 'fu_crystal':
      paintPlastic(
        c,
        _poly(const [
          Offset(32, 84),
          Offset(68, 84),
          Offset(60, 68),
          Offset(40, 68),
        ]),
        Art.silver,
        edge: 1.2,
      );
      _halo(c, 50, 44, 36, color);
      paintPlastic(c, _circle(50, 44, 24), color, edge: 1.6, shine: .8);
      c.drawPath(
        Path()
          ..moveTo(40, 50)
          ..quadraticBezierTo(50, 30, 60, 46),
        _line(Art.light(color, .6), 2),
      );
      paintTwinkle(c, const Offset(56, 38), 5, const Color(0xFFFFFFFF));
    case 'fu_bookcase':
      paintPlastic(c, _rrect(10, 14, 80, 72, 4), color, edge: 1.8);
      final shelf = Art.deep(color, .3);
      for (final y in const [22.0, 48.0]) {
        c.drawRect(Rect.fromLTWH(16, y, 68, 22), _fill(shelf));
      }
      const spines = [
        Color(0xFF7A55C9),
        Color(0xFF3558A8),
        Color(0xFF5E8C6A),
        Color(0xFFE0394E),
        Color(0xFFF2B81F),
      ];
      for (var row = 0; row < 2; row++) {
        for (var i = 0; i < 6; i++) {
          final x = 18.0 + i * 10 + row * 4;
          final h = 16.0 + (i * 7 + row * 3) % 5;
          paintPlastic(
            c,
            _rrect(x, 44 + row * 26 - h, 8, h, 1.5),
            spines[(i + row * 2) % spines.length],
            edge: .8,
            shine: .3,
          );
        }
      }
      paintTwinkle(c, const Offset(80, 16), 5, _glow);
    case 'fu_orrery':
      paintPlastic(c, _rrect(32, 78, 36, 9, 3), Art.goldDark);
      c.drawLine(
        const Offset(50, 50),
        const Offset(50, 80),
        _line(Art.goldDark, 3),
      );
      final ring = _line(color, 2);
      c
        ..drawOval(
          Rect.fromCenter(center: const Offset(50, 46), width: 84, height: 30),
          ring,
        )
        ..drawOval(
          Rect.fromCenter(center: const Offset(50, 46), width: 52, height: 18),
          ring,
        );
      _halo(c, 50, 46, 22, _glow);
      paintPlastic(c, _circle(50, 46, 10), color, edge: 1.2);
      paintPlastic(c, _circle(10, 48, 6), const Color(0xFF52B8E8), edge: 1);
      paintPlastic(c, _circle(72, 38, 5), const Color(0xFFE0394E), edge: 1);
      paintPlastic(c, _circle(64, 60, 4.5), const Color(0xFFA696F7), edge: 1);
      paintTwinkle(c, const Offset(26, 18), 4, _glow);
    case 'fu_candles':
      paintPlastic(c, _oval(50, 82, 70, 12), Art.silver, edge: 1.2);
      for (final (x, h) in const [(30.0, 26.0), (50.0, 40.0), (70.0, 20.0)]) {
        _halo(c, x, 76 - h - 8, 12, _glow);
        paintPlastic(c, _rrect(x - 7, 78 - h, 14, h, 4), color, edge: 1.2);
        paintPlastic(
          c,
          _oval(x, 72 - h, 7, 12),
          const Color(0xFFF5A23A),
          edge: 0,
          shine: .5,
        );
      }
      final moon = Path()
        ..addOval(Rect.fromCircle(center: const Offset(50, 60), radius: 5))
        ..addOval(Rect.fromCircle(center: const Offset(52.5, 58), radius: 4.2))
        ..fillType = PathFillType.evenOdd;
      c.drawPath(moon, _fill(const Color(0xFFA696F7)));
    case 'fu_flowerbowl':
      for (final (x, y) in const [(34.0, 40.0), (50.0, 32.0), (66.0, 42.0)]) {
        _leafShape(c, Offset(x, 62), Offset(x + 8, y + 8), _leaf, .35);
        _blossom(c, x, y, 9, const Color(0xFFFFD84D));
      }
      _scaled(c, 50, 74, .8, () => _pottery(c, 'pot_bowl', color));
    case 'fu_noren':
      for (final x in const [10.0, 84.0]) {
        paintPlastic(c, _rrect(x, 12, 6, 76, 3), _handle, edge: 1);
      }
      paintPlastic(c, _rrect(8, 12, 84, 6, 3), Art.deep(_handle, .2));
      for (final x in const [18.0, 51.0]) {
        paintPlastic(c, _rrect(x, 18, 31, 48, 2), color, edge: 1.4, shine: .4);
      }
      _blossom(c, 34, 42, 8, const Color(0xFFFFFFFF));
      _blossom(c, 66, 50, 6, const Color(0xFFFFFFFF));
    case 'fu_blossom_lamp':
      c.drawLine(const Offset(50, 48), const Offset(50, 80), _line(_handle, 3));
      paintPlastic(c, _oval(50, 82, 30, 9), Art.deep(_handle, .2));
      _halo(c, 50, 36, 34, color);
      _blossom(c, 50, 36, 26, color);
      paintTwinkle(c, const Offset(78, 20), 4, _glow);
    case 'fu_ikebana':
      c.drawLine(
        const Offset(50, 46),
        const Offset(30, 14),
        _line(const Color(0xFF7A5230), 2.6),
      );
      c.drawLine(
        const Offset(52, 46),
        const Offset(72, 22),
        _line(const Color(0xFF7A5230), 2),
      );
      _leafShape(c, const Offset(50, 46), const Offset(78, 36), _leaf, .3);
      _blossom(c, 30, 16, 7, _sakura);
      _blossom(c, 72, 22, 9, const Color(0xFFF58DB6));
      _blossom(c, 44, 30, 6, _sakura);
      _scaled(c, 50, 66, .78, () => _pottery(c, 'pot_vase', color));
    case 'fu_flowerstand':
      final wood = _line(_handle, 3.2);
      c
        ..drawLine(const Offset(20, 86), const Offset(38, 30), wood)
        ..drawLine(const Offset(80, 86), const Offset(62, 30), wood)
        ..drawLine(const Offset(26, 66), const Offset(74, 66), wood)
        ..drawLine(const Offset(33, 46), const Offset(67, 46), wood);
      for (final (x, y, flower) in const [
        (34.0, 64.0, Color(0xFFF58DB6)),
        (66.0, 64.0, Color(0xFFFFD84D)),
        (50.0, 44.0, Color(0xFFE0394E)),
      ]) {
        _blossom(c, x, y - 16, 7, flower);
        paintPlastic(c, _rrect(x - 8, y - 10, 16, 12, 3), color, edge: 1);
      }
    default:
      paintPlastic(c, _rrect(20, 30, 60, 54, 8), color);
  }
}

// --- La casa y el plano -----------------------------------------------------------

/// La casa de un Tama (o el solar, si aún no la tiene).
class HatarakiHomeIcon extends StatelessWidget {
  const HatarakiHomeIcon({super.key, this.size = 48, this.built = true});

  final double size;
  final bool built;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _HomePainter(built)),
  );
}

class _HomePainter extends CustomPainter {
  _HomePainter(this.built);

  final bool built;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    paintGroundShadow(canvas, const Offset(50, 90), 70);
    if (!built) {
      _plot(canvas, const Color(0xFFE884B0));
      return;
    }
    _house(canvas, const Color(0xFFE0864F), _cream, 14, 18, 72, 70);
    // Una ventana redonda con luz y un corazón en el tejado.
    paintPlastic(canvas, _circle(36, 64, 8), _glow, edge: 1.2);
    final heart = Path()
      ..moveTo(50, 44)
      ..cubicTo(38, 36, 42, 24, 50, 30)
      ..cubicTo(58, 24, 62, 36, 50, 44)
      ..close();
    paintPlastic(canvas, heart, const Color(0xFFF2545F), edge: 1);
  }

  @override
  bool shouldRepaint(_HomePainter old) => old.built != built;
}

/// El plano de un mueble: papel azul con su cuadrícula y el mueble encima.
class HatarakiPlanIcon extends StatelessWidget {
  const HatarakiPlanIcon(this.item, {super.key, this.size = 48});

  final String item;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _PlanPainter(item)),
  );
}

class _PlanPainter extends CustomPainter {
  _PlanPainter(this.item);

  final String item;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    paintGroundShadow(canvas, const Offset(50, 90), 70);
    const blue = Color(0xFF3F79E0);
    paintPlastic(canvas, _rrect(10, 12, 80, 74, 6), blue, edge: 1.6, shine: .4);
    final grid = _line(const Color(0x55FFFFFF), 1);
    for (var i = 1; i < 6; i++) {
      canvas
        ..drawLine(Offset(10 + i * 13.3, 14), Offset(10 + i * 13.3, 84), grid)
        ..drawLine(Offset(12, 12 + i * 12.3), Offset(88, 12 + i * 12.3), grid);
    }
    paintPlastic(
      canvas,
      _poly(const [Offset(72, 86), Offset(90, 86), Offset(90, 68)]),
      Art.light(blue, .4),
      edge: .8,
    );
    _scaled(canvas, 50, 50, .62, () => _shape(canvas, item));
  }

  @override
  bool shouldRepaint(_PlanPainter old) => old.item != item;
}

// --- La habitación --------------------------------------------------------------

/// Dónde va el suelo de la habitación en [size] y lo que mide una casilla:
/// el suelo es cuadrado y encima lleva una franja de pared.
(Rect, double) hRoomLayout(Size size) {
  const wall = .22;
  final side = math.min(size.width, size.height / (1 + wall));
  final top = (size.height - side * (1 + wall)) / 2;
  final floor = Rect.fromLTWH(
    (size.width - side) / 2,
    top + side * wall,
    side,
    side,
  );
  return (floor, side / hRoomSize);
}

/// Los muebles que se pintan planos, vistos desde arriba.
const Set<String> _flatFurniture = {
  'fu_rug_wave',
  'fu_rug_red',
  'fu_futon',
  'fu_silk_futon',
};

/// Pinta una habitación: pared, suelo y muebles de atrás hacia delante. El
/// elegido va rodeado de [accent]; con [grid], se ven las casillas.
class HatarakiRoomPainter extends CustomPainter {
  HatarakiRoomPainter(
    this.house, {
    this.selected,
    this.accent = const Color(0xFFE0864F),
    this.grid = false,
  }) : _key = [
         house.floor,
         house.wall,
         for (final p in house.items) '${p.id}${p.x}${p.y}${p.r}',
       ].join('|');

  final HHouse house;
  final int? selected;
  final Color accent;
  final bool grid;
  final String _key;

  @override
  void paint(Canvas canvas, Size size) {
    final (floor, cell) = hRoomLayout(size);
    final wallRect = Rect.fromLTRB(
      floor.left,
      floor.top - floor.width * .22,
      floor.right,
      floor.top,
    );
    final room = RRect.fromRectAndRadius(
      Rect.fromLTRB(floor.left, wallRect.top, floor.right, floor.bottom),
      Radius.circular(cell * .35),
    );
    canvas
      ..drawRRect(
        room.shift(Offset(0, cell * .12)),
        _fill(const Color(0x33000000)),
      )
      ..save()
      ..clipRRect(room);
    _paintWall(canvas, wallRect, house.wall);
    _paintFloor(canvas, floor, cell, house.floor);
    canvas.drawLine(
      floor.topLeft,
      floor.topRight,
      _line(const Color(0x66000000), cell * .08),
    );
    if (grid) {
      final line = _line(const Color(0x33FFFFFF), 1);
      for (var i = 1; i < hRoomSize; i++) {
        canvas
          ..drawLine(
            Offset(floor.left + i * cell, floor.top),
            Offset(floor.left + i * cell, floor.bottom),
            line,
          )
          ..drawLine(
            Offset(floor.left, floor.top + i * cell),
            Offset(floor.right, floor.top + i * cell),
            line,
          );
      }
    }
    // Primero lo plano; luego, de atrás hacia delante.
    final order = [for (var i = 0; i < house.items.length; i++) i]
      ..sort((a, b) {
        final pa = house.items[a], pb = house.items[b];
        final fa = _flatFurniture.contains(pa.id) ? 0 : 1;
        final fb = _flatFurniture.contains(pb.id) ? 0 : 1;
        if (fa != fb) return fa - fb;
        return (pa.y + pa.size.$2).compareTo(pb.y + pb.size.$2);
      });
    for (final i in order) {
      final p = house.items[i];
      final (w, h) = p.size;
      final r = Rect.fromLTWH(
        floor.left + p.x * cell,
        floor.top + p.y * cell,
        w * cell,
        h * cell,
      );
      if (i == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(1), Radius.circular(cell * .2)),
          _fill(accent.withValues(alpha: .28)),
        );
      }
      if (_flatFurniture.contains(p.id)) {
        _paintFlat(canvas, p, r);
      } else {
        _paintStanding(canvas, p, r, cell);
      }
      if (i == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(r.deflate(1), Radius.circular(cell * .2)),
          _line(accent, 2.4),
        );
      }
    }
    canvas.restore();
  }

  /// Un mueble de pie: su dibujo, apoyado en el borde de abajo de sus
  /// casillas y más alto que ellas si hace falta. Girado, se ve del otro
  /// lado.
  void _paintStanding(Canvas c, HPlaced p, Rect r, double cell) {
    // Lo dibujado ocupa del 10 al 90 del lienzo: así llena sus casillas.
    final k = math.min(r.width * 1.2, r.height * 2) / 100;
    c
      ..save()
      ..translate(r.center.dx, r.bottom + cell * .02)
      ..scale(p.r.isOdd ? -k : k, k)
      ..translate(-50, -90);
    paintGroundShadow(c, const Offset(50, 88), 60, .18);
    _shape(c, p.id);
    c.restore();
  }

  /// Alfombras y futones, vistos desde arriba.
  void _paintFlat(Canvas c, HPlaced p, Rect r) {
    final color = hatarakiItemColor(p.id);
    final inner = r.deflate(r.shortestSide * .06);
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          inner,
          Radius.circular(inner.shortestSide * .18),
        ),
      );
    if (p.id.startsWith('fu_rug')) {
      paintPlastic(c, body, color, edge: 1.4, shine: .2);
      final trim = p.id == 'fu_rug_red' ? const Color(0xFFF7C948) : _cream;
      c.drawRRect(
        RRect.fromRectAndRadius(
          inner.deflate(inner.shortestSide * .1),
          Radius.circular(inner.shortestSide * .1),
        ),
        _line(trim, 2),
      );
      if (p.id == 'fu_rug_red') {
        final s = inner.shortestSide * .16;
        paintPlastic(
          c,
          _poly([
            inner.center.translate(0, -s),
            inner.center.translate(s, 0),
            inner.center.translate(0, s),
            inner.center.translate(-s, 0),
          ]),
          trim,
          edge: .8,
          shine: .3,
        );
      } else {
        final wave = _line(Art.light(color, .6), 1.6);
        final rad = inner.shortestSide * .1;
        for (
          var y = inner.top + rad * 3;
          y < inner.bottom - rad;
          y += rad * 2
        ) {
          for (
            var x = inner.left + rad * 2;
            x < inner.right - rad;
            x += rad * 2.4
          ) {
            c.drawArc(
              Rect.fromCircle(center: Offset(x, y), radius: rad),
              math.pi,
              math.pi,
              false,
              wave,
            );
          }
        }
      }
      return;
    }
    // Futón: colchón, colcha y la almohada en la cabecera.
    paintPlastic(c, body, _cream, edge: 1.2, shine: .3);
    final long = inner.height >= inner.width;
    final flip = p.r >= 2;
    final pillowSide = inner.shortestSide * .7;
    final pillow = long
        ? Rect.fromCenter(
            center: Offset(
              inner.center.dx,
              flip
                  ? inner.bottom - pillowSide * .45
                  : inner.top + pillowSide * .45,
            ),
            width: pillowSide,
            height: pillowSide * .55,
          )
        : Rect.fromCenter(
            center: Offset(
              flip
                  ? inner.right - pillowSide * .45
                  : inner.left + pillowSide * .45,
              inner.center.dy,
            ),
            width: pillowSide * .55,
            height: pillowSide,
          );
    final quilt = long
        ? (flip
              ? Rect.fromLTRB(
                  inner.left,
                  inner.top,
                  inner.right,
                  pillow.top - 2,
                )
              : Rect.fromLTRB(
                  inner.left,
                  pillow.bottom + 2,
                  inner.right,
                  inner.bottom,
                ))
        : (flip
              ? Rect.fromLTRB(
                  inner.left,
                  inner.top,
                  pillow.left - 2,
                  inner.bottom,
                )
              : Rect.fromLTRB(
                  pillow.right + 2,
                  inner.top,
                  inner.right,
                  inner.bottom,
                ));
    paintPlastic(
      c,
      Path()..addRRect(
        RRect.fromRectAndRadius(pillow, Radius.circular(pillowSide * .2)),
      ),
      _white,
      edge: 1,
    );
    paintPlastic(
      c,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          quilt,
          Radius.circular(inner.shortestSide * .15),
        ),
      ),
      color,
      edge: 1.4,
      shine: .4,
    );
    if (p.id == 'fu_silk_futon') {
      _blossom(
        c,
        quilt.center.dx,
        quilt.center.dy,
        quilt.shortestSide * .2,
        _white,
      );
    }
  }

  @override
  bool shouldRepaint(HatarakiRoomPainter old) =>
      old._key != _key ||
      old.selected != selected ||
      old.accent != accent ||
      old.grid != grid;
}

/// La pared de cada estilo.
void _paintWall(Canvas c, Rect r, HStyle style) {
  switch (style) {
    case HStyle.rustic:
      c.drawRect(r, _fill(const Color(0xFFEDE0C4)));
      final beam = _fill(const Color(0xFF9A5E2E));
      for (final f in const [0.0, .5, 1.0]) {
        c.drawRect(
          Rect.fromCenter(
            center: Offset(r.left + r.width * f, r.center.dy),
            width: r.width * .04,
            height: r.height,
          ),
          beam,
        );
      }
      c.drawRect(
        Rect.fromLTWH(r.left, r.top + r.height * .18, r.width, r.height * .06),
        beam,
      );
    case HStyle.marine:
      c.drawRect(r, _fill(const Color(0xFFF4FAFD)));
      final stripe = _fill(const Color(0xFF7FB3E0));
      for (var i = 0; i < 4; i++) {
        c.drawRect(
          Rect.fromLTWH(
            r.left,
            r.top + r.height * (i * .25 + .05),
            r.width,
            r.height * .1,
          ),
          stripe,
        );
      }
      final port = Offset(r.left + r.width * .75, r.center.dy);
      c
        ..drawCircle(port, r.height * .3, _fill(const Color(0xFFB7BEC7)))
        ..drawCircle(port, r.height * .22, _fill(const Color(0xFF7EC8F0)));
    case HStyle.elegant:
      c.drawRect(r, _fill(const Color(0xFFFBF6EA)));
      final lattice = _line(
        const Color(0xFF5A3A28),
        math.max(1, r.height * .04),
      );
      for (var i = 0; i <= 12; i++) {
        final x = r.left + r.width * i / 12;
        c.drawLine(Offset(x, r.top), Offset(x, r.bottom), lattice);
      }
      for (final f in const [.33, .66]) {
        final y = r.top + r.height * f;
        c.drawLine(Offset(r.left, y), Offset(r.right, y), lattice);
      }
    case HStyle.magic:
      c.drawRect(r, _fill(const Color(0xFF3C3A6E)));
      for (var i = 0; i < 9; i++) {
        final x = r.left + r.width * ((i * .37 + .05) % 1);
        final y = r.top + r.height * ((i * .53 + .2) % 1);
        paintTwinkle(c, Offset(x, y), r.height * .08, _glow);
      }
      final moon = Offset(r.left + r.width * .2, r.center.dy);
      c
        ..drawCircle(moon, r.height * .28, _fill(const Color(0xFFFFF1C2)))
        ..drawCircle(
          moon.translate(r.height * .12, -r.height * .06),
          r.height * .24,
          _fill(const Color(0xFF3C3A6E)),
        );
    case HStyle.floral:
      c.drawRect(r, _fill(const Color(0xFFFBE3EA)));
      for (var i = 0; i < 8; i++) {
        final x = r.left + r.width * (i + .5) / 8;
        final y = r.top + r.height * (i.isEven ? .35 : .7);
        _blossom(c, x, y, r.height * .14, const Color(0xFFF58DB6));
      }
  }
}

/// El suelo de cada estilo, con la rejilla de [cell].
void _paintFloor(Canvas c, Rect r, double cell, HStyle style) {
  switch (style) {
    case HStyle.rustic:
      // Tatamis de 2×1, desplazados una casilla en cada fila.
      c.drawRect(r, _fill(const Color(0xFFD9D39C)));
      final heri = _line(const Color(0xFF4F6B3A), math.max(1.5, cell * .07));
      final weave = _line(const Color(0x22000000), 1);
      for (var y = 0; y < hRoomSize; y++) {
        for (var k = 0; k < 4; k++) {
          c.drawLine(
            Offset(r.left, r.top + (y + k / 4) * cell),
            Offset(r.right, r.top + (y + k / 4) * cell),
            weave,
          );
        }
        for (var x = y.isOdd ? 1 : 0; x <= hRoomSize; x += 2) {
          c.drawLine(
            Offset(r.left + x * cell, r.top + y * cell),
            Offset(r.left + x * cell, r.top + (y + 1) * cell),
            heri,
          );
        }
        c.drawLine(
          Offset(r.left, r.top + y * cell),
          Offset(r.right, r.top + y * cell),
          heri,
        );
      }
    case HStyle.marine:
      for (var i = 0; i < hRoomSize * 2; i++) {
        c.drawRect(
          Rect.fromLTWH(r.left, r.top + i * cell / 2, r.width, cell / 2),
          _fill(i.isEven ? const Color(0xFFE3EEF2) : const Color(0xFFD3E4EC)),
        );
        final seam = r.left + ((i * 2.3) % hRoomSize) * cell;
        c.drawLine(
          Offset(seam, r.top + i * cell / 2),
          Offset(seam, r.top + (i + 1) * cell / 2),
          _line(const Color(0x33000000), 1),
        );
      }
    case HStyle.elegant:
      for (var y = 0; y < hRoomSize; y++) {
        for (var x = 0; x < hRoomSize; x++) {
          c.drawRect(
            Rect.fromLTWH(r.left + x * cell, r.top + y * cell, cell, cell),
            _fill(
              (x + y).isEven
                  ? const Color(0xFFA0603E)
                  : const Color(0xFF8A4F32),
            ),
          );
          final a = Offset(r.left + x * cell, r.top + y * cell);
          final grain = _line(const Color(0x22FFFFFF), 1);
          for (var k = 1; k < 3; k++) {
            if ((x + y).isEven) {
              c.drawLine(
                a.translate(k * cell / 3, 0),
                a.translate(k * cell / 3, cell),
                grain,
              );
            } else {
              c.drawLine(
                a.translate(0, k * cell / 3),
                a.translate(cell, k * cell / 3),
                grain,
              );
            }
          }
        }
      }
    case HStyle.magic:
      c.drawRect(r, _fill(const Color(0xFF45417A)));
      c.drawCircle(
        r.center,
        r.width * .34,
        _line(const Color(0x55B9A4F2), math.max(1.5, cell * .06)),
      );
      c.drawCircle(
        r.center,
        r.width * .26,
        _line(const Color(0x33B9A4F2), math.max(1, cell * .04)),
      );
      for (var i = 0; i < 14; i++) {
        final x = r.left + r.width * ((i * .41 + .07) % 1);
        final y = r.top + r.height * ((i * .67 + .13) % 1);
        c.drawCircle(Offset(x, y), cell * .04, _fill(const Color(0xAAFFE08A)));
      }
    case HStyle.floral:
      for (var y = 0; y < hRoomSize; y++) {
        for (var x = 0; x < hRoomSize; x++) {
          c.drawRect(
            Rect.fromLTWH(r.left + x * cell, r.top + y * cell, cell, cell),
            _fill(
              (x + y).isEven
                  ? const Color(0xFFF9E8EC)
                  : const Color(0xFFF1D6DE),
            ),
          );
        }
      }
      for (var y = 1; y < hRoomSize; y += 2) {
        for (var x = 1; x < hRoomSize; x += 2) {
          _blossom(
            c,
            r.left + x * cell,
            r.top + y * cell,
            cell * .14,
            const Color(0xFFF7B6C8),
          );
        }
      }
  }
}
