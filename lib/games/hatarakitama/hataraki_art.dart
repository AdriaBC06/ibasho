// Ibasho — Hatarakitama: ilustraciones de objetos, oficios y sitios.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';
import '../../ui/widgets/channel_art.dart';
import 'hataraki_data.dart';
import 'hataraki_home.dart';
import 'hataraki_map.dart';
import 'hataraki_town.dart';

part 'hataraki_art_crafts.dart';
part 'hataraki_art_home.dart';
part 'hataraki_art_map.dart';
part 'hataraki_art_town.dart';

/// Un objeto pintado a mano: cada uno tiene su dibujo (la caña de bambú no es
/// un tronco de otro color, ni el salmón una sardina rosa). Todo sobre un
/// lienzo de 100×100, con plástico y sombra de contacto como las demás
/// ilustraciones de la casa.
class HatarakiItemIcon extends StatelessWidget {
  const HatarakiItemIcon(this.item, {super.key, this.size = 48});

  final String item;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _ItemPainter(item)),
  );
}

/// El icono de un oficio: una escena pequeña con su herramienta.
class HatarakiSkillIcon extends StatelessWidget {
  const HatarakiSkillIcon(this.skill, {super.key, this.size = 48});

  final HSkill skill;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _SkillPainter(skill)),
  );
}

/// El icono de un sitio de expedición: un paisaje en una medalla redonda.
class HatarakiZoneIcon extends StatelessWidget {
  const HatarakiZoneIcon(this.zone, {super.key, this.size = 48});

  final String zone;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _ZonePainter(zone)),
  );
}

// --- Colores ----------------------------------------------------------------

/// El color principal de cada objeto.
const Map<String, Color> _tones = {
  'log_sugi': Color(0xFFA8713F),
  'log_matsu': Color(0xFF8E5B36),
  'log_take': Color(0xFF8CC063),
  'log_kaede': Color(0xFFB0643E),
  'log_sakura': Color(0xFF9C5A4E),
  'log_ichou': Color(0xFFB08A55),
  'log_kusu': Color(0xFF6E5440),
  'log_shinboku': Color(0xFFD9B878),
  'fish_iwashi': Color(0xFF7D9CB8),
  'fish_aji': Color(0xFF9DB08A),
  'fish_saba': Color(0xFF4F86B0),
  'fish_tai': Color(0xFFF07C7C),
  'fish_sake': Color(0xFFF0987A),
  'fish_unagi': Color(0xFF6B6A4A),
  'fish_maguro': Color(0xFF3F618C),
  'fish_kinkoi': Color(0xFFF5B83D),
  'ore_copper': Color(0xFFE0864F),
  'ore_tin': Color(0xFFC9D1DA),
  'ore_iron': Color(0xFF9A6F63),
  'ore_silver': Color(0xFFE1E8F0),
  'ore_gold': Color(0xFFF7CB45),
  'ore_jade': Color(0xFF5CC495),
  'ore_moon': Color(0xFFB8CCFA),
  'ore_star': Color(0xFF9A86F5),
  'bar_bronze': Color(0xFFD18A4C),
  'bar_iron': Color(0xFF9EA6AE),
  'bar_silver': Color(0xFFE2E8EF),
  'bar_gold': Color(0xFFF7C948),
  'bar_star': Color(0xFFA696F7),
  'gem_quartz': Color(0xFFEAF2FF),
  'gem_amethyst': Color(0xFFA56BE3),
  'gem_sapphire': Color(0xFF3F79E0),
  'gem_ruby': Color(0xFFE63E5A),
  'gem_pearl': Color(0xFFF8EEF2),
  'crop_rice': Color(0xFFF2CD5C),
  'crop_daikon': Color(0xFFF7F6EE),
  'crop_cotton': Color(0xFFFFFFFF),
  'crop_soy': Color(0xFF94C95A),
  'crop_tea': Color(0xFF5DB15E),
  'crop_ichigo': Color(0xFFEF4B63),
  'crop_imo': Color(0xFFA9496F),
  'crop_momo': Color(0xFFFFAE94),
  'wild_tanpopo': Color(0xFFFFD43F),
  'wild_shiitake': Color(0xFF8E5B3C),
  'wild_takenoko': Color(0xFFC9A061),
  'wild_kuri': Color(0xFF8A4F2E),
  'wild_yuzu': Color(0xFFF7D13F),
  'wild_matsutake': Color(0xFFB88B5E),
  'wild_hasu': Color(0xFFF59CC0),
  'wild_kinmokusei': Color(0xFFF79A3A),
  'plank_sugi': Color(0xFFE0AA70),
  'plank_kaede': Color(0xFFE0875A),
  'plank_sakura': Color(0xFFEFB3B8),
  'cloth_cotton': Color(0xFFF6F2E8),
  'cloth_silk': Color(0xFFF2B8DA),
  'rare_feather': Color(0xFFF5F8FC),
  'rare_shell': Color(0xFFFFC7B5),
  'rare_amber': Color(0xFFF2A23A),
  'rare_ember': Color(0xFFFF6B3D),
  'rare_cloud': Color(0xFFEAF4FF),
  'rare_moondust': Color(0xFFC9B8FF),
  'silk_thread': Color(0xFFF5C4E2),
  'parcel': Color(0xFF6C8FD6),
  'food_onigiri': Color(0xFFFAF7EE),
  'food_iwashi': Color(0xFF8FA8BF),
  'food_miso': Color(0xFFC9914A),
  'food_aji': Color(0xFFE8B45A),
  'food_saba': Color(0xFF7FA3C2),
  'food_taimeshi': Color(0xFFF08C84),
  'food_yakiimo': Color(0xFFF5C84A),
  'food_unadon': Color(0xFFA0602F),
  'food_sushi': Color(0xFFF0736B),
  'food_feast': Color(0xFFD9434F),
  'tea_tanpopo': Color(0xFFF2D05A),
  'tea_sencha': Color(0xFFB5D65E),
  'tea_genmai': Color(0xFFD9BC7E),
  'tea_yuzu': Color(0xFFF5D55A),
  'tea_hoji': Color(0xFFA8683E),
  'tea_matcha': Color(0xFF7CC25E),
  'tea_hasu': Color(0xFFF2B0CC),
  'tea_kinmoku': Color(0xFFF5A94F),
  'gear_bronze_pick': Color(0xFFD18A4C),
  'gear_iron_pick': Color(0xFF9EA6AE),
  'gear_silver_pick': Color(0xFFE2E8EF),
  'gear_gold_pick': Color(0xFFF7C948),
  'gear_star_pick': Color(0xFFA696F7),
  'gear_scarf': Color(0xFFEF5F5F),
  'gear_happi': Color(0xFF4F86D9),
  'gear_cloak': Color(0xFF5FA872),
  'gear_kimono': Color(0xFFE884B0),
  'gear_cloudrobe': Color(0xFFCFE4FF),
  'gear_basket': Color(0xFFD9AE66),
  'gear_backpack': Color(0xFFE0844A),
  'gear_chest': Color(0xFFA8683E),
  'gear_sakurabox': Color(0xFFF2B8C4),
  'gear_shrine': Color(0xFFE5483C),
  'gear_quartz_charm': Color(0xFFEAF2FF),
  'gear_amethyst_ring': Color(0xFFA56BE3),
  'gear_sapphire_charm': Color(0xFF3F79E0),
  'gear_ruby_ring': Color(0xFFE63E5A),
  'gear_pearl_crown': Color(0xFFF8EEF2),
};

const Color _leaf = Color(0xFF5DB15E);
const Color _leafDark = Color(0xFF3E8C4E);
const Color _china = Color(0xFFF1EEF6);
const Color _handle = Color(0xFFB9824E);
const Color _metal = Color(0xFFB7BEC7);
const Color _rice = Color(0xFFFAF7EE);
const Color _nori = Color(0xFF34503F);
const Color _stone = Color(0xFF9A928C);
const Color _heartwood = Color(0xFFF3D6A4);
const Color _lacquer = Color(0xFFC8323E);
const Color _plate = Color(0xFFEAF1F7);
const Color _sakura = Color(0xFFF7B6C8);

Color hatarakiItemColor(String id) {
  if (id.startsWith('seed_')) {
    return _tones['crop_${id.substring(5)}'] ?? T.shellTop;
  }
  return _tones[id] ?? _craftTones[id] ?? _furnitureTones[id] ?? T.shellTop;
}

// --- Utilidades ---------------------------------------------------------------

Path _circle(double x, double y, double r) =>
    Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));

Path _oval(double x, double y, double w, double h) =>
    Path()..addOval(Rect.fromCenter(center: Offset(x, y), width: w, height: h));

Path _rrect(double l, double t, double w, double h, double r) => Path()
  ..addRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r)),
  );

Path _poly(List<Offset> points) => Path()..addPolygon(points, true);

Paint _line(Color c, double w) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = c;

Paint _fill(Color c) => Paint()..color = c;

/// Un brillo pequeño, como una gota de luz sobre el plástico.
void _gleam(Canvas c, double x, double y, [double r = 3.2]) {
  c.drawOval(
    Rect.fromCenter(center: Offset(x, y), width: r * 1.6, height: r),
    _fill(T.shellTop.withValues(alpha: .85)),
  );
}

/// Dibuja [draw] girado [angle] alrededor de ([x], [y]).
void _turned(Canvas c, double x, double y, double angle, VoidCallback draw) {
  c
    ..save()
    ..translate(x, y)
    ..rotate(angle)
    ..translate(-x, -y);
  draw();
  c.restore();
}

/// Dibuja [draw] a escala [k] alrededor de ([x], [y]).
void _scaled(Canvas c, double x, double y, double k, VoidCallback draw) {
  c
    ..save()
    ..translate(x, y)
    ..scale(k)
    ..translate(-x, -y);
  draw();
  c.restore();
}

/// Una hoja en punta, de [from] hacia [to].
void _leafShape(
  Canvas c,
  Offset from,
  Offset to,
  Color color, [
  double w = .5,
]) {
  final d = to - from;
  final n = Offset(-d.dy, d.dx) * w;
  final mid = from + d * .5;
  final leaf = Path()
    ..moveTo(from.dx, from.dy)
    ..quadraticBezierTo(mid.dx + n.dx, mid.dy + n.dy, to.dx, to.dy)
    ..quadraticBezierTo(mid.dx - n.dx, mid.dy - n.dy, from.dx, from.dy)
    ..close();
  paintPlastic(c, leaf, color, edge: 1.4, shine: .5);
  c.drawLine(from, from + d * .8, _line(Art.deep(color, .25), 1));
}

/// Una flor de cinco pétalos redondos.
void _blossom(Canvas c, double x, double y, double r, Color color) {
  for (var i = 0; i < 5; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / 5;
    paintPlastic(
      c,
      _circle(x + math.cos(a) * r * .62, y + math.sin(a) * r * .62, r * .5),
      color,
      edge: 1,
      shine: .4,
    );
  }
  c.drawCircle(Offset(x, y), r * .28, _fill(const Color(0xFFF7C948)));
}

// --- Madera -------------------------------------------------------------------

/// Tronco tumbado: corteza con vetas, el corte claro con anillos y una ramita
/// que dice de qué árbol es.
void _log(Canvas c, String id, Color bark) {
  paintPlastic(c, _rrect(10, 44, 70, 32, 15), bark, edge: 2);
  final vein = _line(Art.deep(bark, .3), 1.6);
  for (final x in const [24.0, 38.0, 52.0, 64.0]) {
    c.drawPath(
      Path()
        ..moveTo(x, 50)
        ..quadraticBezierTo(x + 3, 58, x - 1, 70),
      vein,
    );
  }
  final face = Rect.fromCenter(
    center: const Offset(78, 60),
    width: 22,
    height: 32,
  );
  final wood = Color.lerp(_heartwood, bark, .15)!;
  paintPlastic(c, Path()..addOval(face), wood, edge: 2, shine: .5);
  final ring = _line(Art.deep(wood, .28), 1.4);
  c.drawOval(Rect.fromCenter(center: face.center, width: 14, height: 21), ring);
  c.drawOval(Rect.fromCenter(center: face.center, width: 6, height: 10), ring);
  // La ramita de encima.
  switch (id) {
    case 'log_sakura':
      c.drawLine(const Offset(30, 46), const Offset(40, 30), _line(bark, 3));
      _blossom(c, 42, 28, 11, _sakura);
      _blossom(c, 28, 34, 8, Art.light(_sakura, .3));
    case 'log_kaede':
      c.drawLine(const Offset(32, 46), const Offset(38, 34), _line(bark, 3));
      _maple(c, 40, 28, 13, const Color(0xFFE8503A));
    case 'log_ichou':
      c.drawLine(const Offset(32, 46), const Offset(38, 34), _line(bark, 3));
      _ginkgo(c, 40, 30, 14, const Color(0xFFF5C83F));
    case 'log_matsu':
      c.drawLine(const Offset(30, 46), const Offset(40, 32), _line(bark, 3));
      final needle = _line(const Color(0xFF2E7A55), 2.2);
      for (var i = 0; i < 7; i++) {
        final a = -math.pi * .95 + i * math.pi * .15;
        c.drawLine(
          const Offset(40, 32),
          Offset(40 + math.cos(a) * 14, 32 + math.sin(a) * 14),
          needle,
        );
      }
    case 'log_shinboku':
      // Madera sagrada: la cuerda shimenawa y sus papeles en zigzag.
      c.drawLine(
        const Offset(40, 44),
        const Offset(40, 76),
        _line(const Color(0xFFE8D39A), 6),
      );
      c.drawLine(
        const Offset(40, 44),
        const Offset(40, 76),
        _line(const Color(0xFFB8994E), 1.2),
      );
      // Un papel shide colgando de la cuerda.
      paintPlastic(
        c,
        _poly(const [
          Offset(40, 60),
          Offset(48, 60),
          Offset(44, 68),
          Offset(50, 68),
          Offset(44, 80),
          Offset(46, 70),
          Offset(40, 70),
        ]),
        T.shellTop,
        edge: 1,
        shine: 0,
      );
      paintTwinkle(c, const Offset(24, 30), 7, Art.spark);
      paintTwinkle(c, const Offset(64, 34), 5, Art.spark);
    default:
      final green = id == 'log_kusu'
          ? const Color(0xFF4FA35E)
          : const Color(0xFF3E8E5A);
      c.drawLine(const Offset(30, 46), const Offset(40, 32), _line(bark, 3));
      _leafShape(c, const Offset(40, 32), const Offset(54, 24), green);
      _leafShape(c, const Offset(38, 34), const Offset(28, 22), green);
  }
}

void _maple(Canvas c, double x, double y, double r, Color color) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rr = i.isEven ? r : r * .45;
    final pt = Offset(x + math.cos(a) * rr, y + math.sin(a) * rr);
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  p.close();
  paintPlastic(c, p, color, edge: 1.4, shine: .5);
}

void _ginkgo(Canvas c, double x, double y, double r, Color color) {
  final p = Path()
    ..moveTo(x, y + r * .6)
    ..lineTo(x - r, y - r * .3)
    ..quadraticBezierTo(x, y - r * 1.1, x + r, y - r * .3)
    ..close();
  paintPlastic(c, p, color, edge: 1.4, shine: .5);
  c.drawLine(
    Offset(x, y - r * .6),
    Offset(x, y + r * .6),
    _line(Art.deep(color, .2), 1.2),
  );
}

/// Dos cañas de bambú cruzadas, con sus nudos y una hoja.
void _bamboo(Canvas c, Color base) {
  for (final (dx, a) in const [(-8.0, -.35), (10.0, .25)]) {
    _turned(c, 50 + dx, 54, a, () {
      paintPlastic(c, _rrect(43 + dx, 16, 14, 70, 7), base, edge: 1.8);
      for (final y in const [34.0, 54.0, 72.0]) {
        c.drawLine(
          Offset(44 + dx, y),
          Offset(56 + dx, y),
          _line(Art.deep(base, .3), 2.2),
        );
      }
    });
  }
  _leafShape(c, const Offset(60, 30), const Offset(82, 20), _leafDark, .35);
}

void _plank(Canvas c, Color base) {
  for (final (y, a, tone) in [
    (46.0, -.16, Art.deep(base, .08)),
    (62.0, .08, base),
  ]) {
    _turned(c, 50, y, a, () {
      paintPlastic(c, _rrect(14, y - 10, 72, 20, 4), tone, edge: 1.8);
      final grain = _line(Art.deep(tone, .2), 1.2);
      c.drawPath(
        Path()
          ..moveTo(22, y - 3)
          ..quadraticBezierTo(46, y - 6, 74, y - 2),
        grain,
      );
      c.drawPath(
        Path()
          ..moveTo(28, y + 4)
          ..quadraticBezierTo(52, y + 1, 78, y + 5),
        grain,
      );
      c.drawCircle(Offset(20, y), 1.8, _fill(_metal));
      c.drawCircle(Offset(80, y), 1.8, _fill(_metal));
    });
  }
}

// --- Pescado --------------------------------------------------------------------

/// Un pez de perfil: cuerpo en gota, cola en horquilla, aleta de arriba,
/// barriga clara, agalla y ojo. Los retoques van en [extra], ya recortados
/// por el cuerpo.
void _fish(
  Canvas c,
  Color back, {
  Color? belly,
  double len = 62,
  double h = 30,
  double cy = 56,
  bool spiky = false,
  void Function(Rect body)? extra,
}) {
  const cx = 52.0;
  final nose = cx + len / 2, tail = cx - len / 2;
  final body = Path()
    ..moveTo(nose, cy)
    ..cubicTo(
      nose - len * .1,
      cy - h * .72,
      cx - len * .2,
      cy - h * .6,
      tail,
      cy - h * .1,
    )
    ..lineTo(tail, cy + h * .1)
    ..cubicTo(
      cx - len * .2,
      cy + h * .6,
      nose - len * .1,
      cy + h * .72,
      nose,
      cy,
    )
    ..close();
  final fin = Art.deep(back, .12);
  // Cola.
  paintPlastic(
    c,
    _poly([
      Offset(tail + 3, cy),
      Offset(tail - 13, cy - h * .55),
      Offset(tail - 7, cy),
      Offset(tail - 13, cy + h * .55),
    ]),
    fin,
    edge: 1.6,
    shine: .3,
  );
  // Aleta de arriba: redonda o con púas.
  final top = cy - h * .42;
  final dorsal = spiky
      ? _poly([
          Offset(cx - 14, top + 3),
          Offset(cx - 10, top - 10),
          Offset(cx - 5, top - 2),
          Offset(cx - 1, top - 12),
          Offset(cx + 4, top - 2),
          Offset(cx + 8, top - 10),
          Offset(cx + 12, top + 3),
        ])
      : (Path()
          ..moveTo(cx - 12, top + 3)
          ..quadraticBezierTo(cx - 4, top - 12, cx + 10, top + 2)
          ..close());
  paintPlastic(c, dorsal, fin, edge: 1.4, shine: .3);
  paintPlastic(c, body, back, edge: 0);
  final bounds = body.getBounds();
  c.save();
  c.clipPath(body);
  c.drawRect(
    Rect.fromLTRB(bounds.left, cy + h * .05, bounds.right, bounds.bottom),
    _fill((belly ?? Art.light(back, .6)).withValues(alpha: .9)),
  );
  extra?.call(bounds);
  c.restore();
  c.drawPath(body, _line(Art.deep(back, .45), 2));
  // Aleta del lado y agalla.
  paintPlastic(
    c,
    Path()
      ..moveTo(nose - len * .36, cy + 2)
      ..quadraticBezierTo(
        nose - len * .5,
        cy + h * .35,
        nose - len * .52,
        cy + h * .1,
      )
      ..close(),
    fin,
    edge: 1.2,
    shine: 0,
  );
  c.drawPath(
    Path()
      ..moveTo(nose - len * .28, cy - h * .28)
      ..quadraticBezierTo(nose - len * .22, cy, nose - len * .28, cy + h * .26),
    _line(Art.deep(back, .35), 1.6),
  );
  final eye = Offset(nose - len * .14, cy - h * .1);
  c.drawCircle(eye, h * .13, _fill(T.shellTop));
  c.drawCircle(eye + const Offset(.8, 0), h * .08, _fill(T.tamaInk));
  c.drawCircle(eye + const Offset(-.4, -1), h * .03, _fill(T.shellTop));
}

void _fishFor(Canvas c, String id, Color base) {
  switch (id) {
    case 'fish_iwashi':
      _fish(
        c,
        base,
        len: 56,
        h: 24,
        extra: (b) {
          for (var i = 0; i < 5; i++) {
            c.drawCircle(
              Offset(40 + i * 7, 58),
              1.8,
              _fill(Art.deep(base, .4)),
            );
          }
        },
      );
    case 'fish_aji':
      _fish(
        c,
        base,
        extra: (b) {
          c.drawLine(
            const Offset(26, 57),
            const Offset(70, 55),
            _line(Art.deep(base, .3), 2.4),
          );
          c.drawCircle(
            const Offset(66, 50),
            2.4,
            _fill(const Color(0xFF4A5A4A)),
          );
        },
      );
    case 'fish_saba':
      _fish(
        c,
        base,
        belly: const Color(0xFFE9F1F6),
        extra: (b) {
          final stripe = _line(Art.deep(base, .45), 2);
          for (var i = 0; i < 5; i++) {
            final x = 28.0 + i * 9;
            c.drawPath(
              Path()
                ..moveTo(x, 42)
                ..quadraticBezierTo(x + 5, 47, x, 53),
              stripe,
            );
          }
        },
      );
    case 'fish_tai':
      _fish(
        c,
        base,
        h: 40,
        len: 60,
        spiky: true,
        extra: (b) {
          for (final (x, y) in const [
            (40.0, 48.0),
            (52.0, 44.0),
            (46.0, 56.0),
            (60.0, 50.0),
          ]) {
            c.drawCircle(Offset(x, y), 1.8, _fill(const Color(0xFF7EC8F2)));
          }
        },
      );
    case 'fish_sake':
      _fish(
        c,
        base,
        len: 66,
        belly: const Color(0xFFFFE3D6),
        extra: (b) {
          for (final (x, y) in const [
            (34.0, 46.0),
            (44.0, 44.0),
            (54.0, 47.0),
            (40.0, 51.0),
          ]) {
            c.drawCircle(Offset(x, y), 1.6, _fill(Art.deep(base, .5)));
          }
        },
      );
    case 'fish_unagi':
      _eel(c, base);
    case 'fish_maguro':
      _fish(
        c,
        base,
        len: 70,
        h: 32,
        belly: const Color(0xFFDCE6EE),
        extra: (b) {
          for (var i = 0; i < 4; i++) {
            c.drawCircle(
              Offset(24 + i * 5, 62),
              1.6,
              _fill(const Color(0xFFF5C83F)),
            );
          }
        },
      );
    case 'fish_kinkoi':
      _fish(
        c,
        base,
        h: 32,
        belly: const Color(0xFFFFF1C8),
        extra: (b) {
          paintPlastic(
            c,
            _circle(42, 46, 8),
            const Color(0xFFF26B3A),
            edge: 0,
            shine: 0,
          );
          paintPlastic(c, _circle(58, 52, 6), T.shellTop, edge: 0, shine: 0);
          paintPlastic(
            c,
            _circle(30, 54, 5),
            const Color(0xFFF26B3A),
            edge: 0,
            shine: 0,
          );
        },
      );
      // Bigotes de carpa.
      c.drawPath(
        Path()
          ..moveTo(80, 60)
          ..quadraticBezierTo(86, 66, 84, 72),
        _line(Art.deep(base, .3), 1.4),
      );
      paintTwinkle(c, const Offset(20, 32), 6, Art.spark);
    default:
      _fish(c, base);
  }
}

/// Una anguila: una cinta ondulada con la cabeza a la derecha.
void _eel(Canvas c, Color base) {
  final spine = Path()
    ..moveTo(14, 50)
    ..cubicTo(28, 30, 40, 76, 56, 58)
    ..cubicTo(66, 46, 74, 50, 84, 52);
  c.drawPath(spine, _line(Art.deep(base, .45), 17));
  c.drawPath(spine, _line(base, 13));
  c.drawPath(
    Path()
      ..moveTo(18, 50)
      ..cubicTo(30, 33, 40, 72, 56, 55)
      ..cubicTo(66, 44, 74, 47, 82, 49),
    _line(Art.light(base, .35), 4),
  );
  c.drawCircle(const Offset(80, 49), 2.6, _fill(T.shellTop));
  c.drawCircle(const Offset(80.6, 49), 1.5, _fill(T.tamaInk));
}

// --- Minerales y metales ----------------------------------------------------

/// Un cristal de seis caras con la punta arriba.
void _shard(Canvas c, double x, double y, double w, double h, Color color) {
  final p = _poly([
    Offset(x - w / 2, y + h),
    Offset(x - w / 2, y + h * .28),
    Offset(x, y),
    Offset(x + w / 2, y + h * .28),
    Offset(x + w / 2, y + h),
  ]);
  paintPlastic(c, p, color, edge: 1.6, shine: .8);
  c.drawLine(Offset(x, y), Offset(x, y + h), _line(Art.light(color, .5), 1.4));
  c.drawLine(
    Offset(x - w / 2, y + h * .28),
    Offset(x + w / 2, y + h * .28),
    _line(Art.deep(color, .15), 1),
  );
}

Path _rockPath() => Path()
  ..moveTo(14, 78)
  ..quadraticBezierTo(12, 62, 24, 56)
  ..quadraticBezierTo(34, 50, 48, 54)
  ..quadraticBezierTo(64, 48, 76, 56)
  ..quadraticBezierTo(90, 64, 84, 78)
  ..close();

/// Mineral: una roca con cristales (o pepitas) del color del metal.
void _ore(Canvas c, String id, Color color) {
  switch (id) {
    case 'ore_gold' || 'ore_iron' || 'ore_copper':
      paintPlastic(c, _rockPath(), _stone, edge: 2);
      // Pepitas redondeadas incrustadas.
      for (final (x, y, r) in const [
        (36.0, 62.0, 9.0),
        (58.0, 58.0, 11.0),
        (70.0, 70.0, 6.0),
        (26.0, 72.0, 5.0),
      ]) {
        paintPlastic(c, _oval(x, y, r * 2.2, r * 1.8), color, edge: 1.4);
      }
    default:
      _shard(c, 36, 24, 18, 40, Art.deep(color, .08));
      _shard(c, 56, 12, 24, 52, color);
      _shard(c, 74, 32, 14, 32, Art.light(color, .15));
      paintPlastic(c, _rockPath(), _stone, edge: 2);
  }
  if (id == 'ore_moon' || id == 'ore_star') {
    paintTwinkle(
      c,
      const Offset(24, 34),
      7,
      id == 'ore_star' ? Art.spark : T.shellTop,
    );
    paintTwinkle(
      c,
      const Offset(84, 30),
      5,
      id == 'ore_star' ? Art.spark : T.shellTop,
    );
  }
}

/// Dos lingotes, uno detrás de otro, con la cara de arriba más clara.
void _bars(Canvas c, Color color, {bool star = false}) {
  void ingot(double dx, double dy, Color tone) {
    paintPlastic(
      c,
      _poly([
        Offset(16 + dx, 72 + dy),
        Offset(24 + dx, 56 + dy),
        Offset(72 + dx, 56 + dy),
        Offset(80 + dx, 72 + dy),
      ]),
      tone,
      edge: 1.8,
    );
    paintPlastic(
      c,
      _poly([
        Offset(24 + dx, 56 + dy),
        Offset(30 + dx, 46 + dy),
        Offset(66 + dx, 46 + dy),
        Offset(72 + dx, 56 + dy),
      ]),
      Art.light(tone, .3),
      edge: 1.8,
    );
    c.drawOval(
      Rect.fromCenter(center: Offset(48 + dx, 51 + dy), width: 14, height: 5),
      _line(Art.deep(tone, .2), 1.2),
    );
  }

  ingot(6, -14, Art.deep(color, .1));
  ingot(-2, 4, color);
  if (star) {
    paintTwinkle(c, const Offset(22, 34), 7, Art.spark);
    paintTwinkle(c, const Offset(82, 44), 5, Art.spark);
  }
}

// --- Gemas ------------------------------------------------------------------------

void _gem(Canvas c, String id, Color color) {
  switch (id) {
    case 'gem_quartz':
      _shard(c, 36, 34, 14, 42, Art.deep(color, .05));
      _shard(c, 64, 30, 14, 46, Art.deep(color, .05));
      _shard(c, 50, 20, 20, 58, color);
    case 'gem_amethyst':
      // Geoda: media roca con cristales morados dentro.
      paintPlastic(c, _rockPath(), _stone, edge: 2);
      c.save();
      c.clipPath(_oval(50, 66, 60, 26));
      c.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        _fill(Art.deep(color, .35)),
      );
      c.restore();
      for (final (x, y, w, h) in const [
        (36.0, 52.0, 10.0, 20.0),
        (50.0, 44.0, 12.0, 28.0),
        (64.0, 50.0, 10.0, 22.0),
      ]) {
        _shard(c, x, y, w, h, color);
      }
    case 'gem_sapphire':
      paintPlastic(c, _oval(50, 54, 56, 44), color, edge: 2);
      final facet = _line(Art.light(color, .35), 1.3);
      c.drawOval(
        Rect.fromCenter(center: const Offset(50, 54), width: 30, height: 22),
        facet,
      );
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        c.drawLine(
          Offset(50 + math.cos(a) * 15, 54 + math.sin(a) * 11),
          Offset(50 + math.cos(a) * 28, 54 + math.sin(a) * 22),
          facet,
        );
      }
      _gleam(c, 40, 42, 5);
    case 'gem_pearl':
      paintPlastic(c, _circle(50, 56, 22), color, edge: 1.6);
      c.save();
      c.clipPath(_circle(50, 56, 22));
      c.drawCircle(const Offset(58, 64), 18, _fill(const Color(0x33F2B8D0)));
      c.restore();
      _gleam(c, 42, 46, 7);
    default:
      _brilliant(c, color);
  }
}

/// El corte de siempre: corona con facetas y pabellón en punta.
void _brilliant(
  Canvas c,
  Color color, [
  double x = 50,
  double y = 50,
  double k = 1,
]) {
  final w = 50 * k, top = 18 * k, crown = 12 * k, point = 42 * k;
  paintPlastic(
    c,
    _poly([
      Offset(x - w / 2, y - top + crown),
      Offset(x - w / 4, y - top),
      Offset(x + w / 4, y - top),
      Offset(x + w / 2, y - top + crown),
      Offset(x, y - top + crown + point),
    ]),
    color,
    edge: 1.8 * k,
  );
  final facet = _line(Art.deep(color, .25), 1.2 * k);
  final girdle = y - top + crown;
  c.drawLine(Offset(x - w / 2, girdle), Offset(x + w / 2, girdle), facet);
  c.drawLine(Offset(x - w / 4, y - top), Offset(x - w / 8, girdle), facet);
  c.drawLine(Offset(x + w / 4, y - top), Offset(x + w / 8, girdle), facet);
  c.drawLine(Offset(x - w / 8, girdle), Offset(x, girdle + point), facet);
  c.drawLine(Offset(x + w / 8, girdle), Offset(x, girdle + point), facet);
  _gleam(c, x - w / 5, y - top + crown * .5, 4 * k);
}

// --- Huerto y bosque --------------------------------------------------------------

void _crop(Canvas c, String id, Color color) {
  switch (id) {
    case 'crop_rice':
      // Gavilla: tallos atados y espigas que cuelgan.
      final stem = _line(const Color(0xFFC9A94A), 2.4);
      for (final a in const [-.5, -.25, 0.0, .25, .5]) {
        final top = Offset(50 + math.sin(a) * 30, 26 + (a.abs() * 14));
        c.drawLine(const Offset(50, 84), top, stem);
        for (var i = 0; i < 4; i++) {
          paintPlastic(
            c,
            _oval(top.dx + (a >= 0 ? 1 : -1) * i * 2.6, top.dy + i * 6, 6, 8),
            color,
            edge: 1,
            shine: .4,
          );
        }
      }
      paintPlastic(
        c,
        _rrect(40, 62, 20, 7, 3),
        const Color(0xFFB0433E),
        edge: 1.2,
      );
    case 'crop_daikon':
      _leafShape(c, const Offset(58, 34), const Offset(52, 10), _leaf, .35);
      _leafShape(c, const Offset(60, 34), const Offset(76, 14), _leafDark, .35);
      _leafShape(c, const Offset(56, 36), const Offset(36, 18), _leaf, .35);
      final root = Path()
        ..moveTo(46, 36)
        ..quadraticBezierTo(70, 30, 70, 44)
        ..quadraticBezierTo(62, 70, 30, 86)
        ..quadraticBezierTo(36, 60, 46, 36)
        ..close();
      paintPlastic(c, root, color, edge: 1.8);
      c.drawLine(
        const Offset(48, 56),
        const Offset(54, 54),
        _line(Art.deep(color, .2), 1.2),
      );
      c.drawLine(
        const Offset(42, 66),
        const Offset(48, 65),
        _line(Art.deep(color, .2), 1.2),
      );
    case 'crop_cotton':
      for (final (x, y) in const [(30.0, 64.0), (70.0, 64.0), (50.0, 70.0)]) {
        _leafShape(
          c,
          const Offset(50, 64),
          Offset(x, y + 10),
          const Color(0xFF8E6B45),
          .45,
        );
      }
      for (final (x, y, r) in const [
        (38.0, 50.0, 14.0),
        (62.0, 50.0, 14.0),
        (50.0, 36.0, 15.0),
        (50.0, 58.0, 13.0),
      ]) {
        paintPlastic(c, _circle(x, y, r), color, edge: 1.6);
      }
    case 'crop_soy':
      final pod = Path()
        ..moveTo(18, 66)
        ..quadraticBezierTo(22, 44, 50, 42)
        ..quadraticBezierTo(76, 40, 84, 30)
        ..quadraticBezierTo(86, 50, 58, 60)
        ..quadraticBezierTo(34, 68, 18, 66)
        ..close();
      paintPlastic(c, pod, color, edge: 1.8);
      for (final (x, y) in const [(34.0, 56.0), (50.0, 51.0), (66.0, 46.0)]) {
        c.drawCircle(Offset(x, y), 7, _fill(Art.light(color, .3)));
        c.drawCircle(Offset(x, y), 7, _line(Art.deep(color, .25), 1.2));
      }
    case 'crop_tea':
      c.drawLine(
        const Offset(50, 86),
        const Offset(50, 30),
        _line(const Color(0xFF7A6040), 2.6),
      );
      _leafShape(c, const Offset(50, 64), const Offset(20, 48), color);
      _leafShape(
        c,
        const Offset(50, 54),
        const Offset(80, 38),
        Art.deep(color, .08),
      );
      _leafShape(
        c,
        const Offset(50, 40),
        const Offset(50, 14),
        Art.light(color, .25),
        .3,
      );
    case 'crop_ichigo':
      final berry = Path()
        ..moveTo(50, 84)
        ..quadraticBezierTo(18, 60, 26, 42)
        ..quadraticBezierTo(50, 30, 74, 42)
        ..quadraticBezierTo(82, 60, 50, 84)
        ..close();
      paintPlastic(c, berry, color, edge: 1.8);
      for (final (x, y) in const [
        (38.0, 50.0),
        (50.0, 48.0),
        (62.0, 50.0),
        (44.0, 60.0),
        (56.0, 60.0),
        (50.0, 71.0),
      ]) {
        c.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: 2.6, height: 3.6),
          _fill(const Color(0xFFFFE08A)),
        );
      }
      for (var i = 0; i < 5; i++) {
        final a = math.pi + i * math.pi / 4;
        _leafShape(
          c,
          const Offset(50, 38),
          Offset(50 + math.cos(a) * 16, 38 + math.sin(a) * 8),
          _leaf,
          .4,
        );
      }
    case 'crop_imo':
      _turned(c, 50, 58, -.35, () {
        paintPlastic(c, _oval(50, 58, 72, 32), color, edge: 1.8);
        c.drawLine(
          const Offset(40, 52),
          const Offset(46, 54),
          _line(Art.deep(color, .3), 1.4),
        );
        c.drawLine(
          const Offset(58, 62),
          const Offset(64, 60),
          _line(Art.deep(color, .3), 1.4),
        );
      });
      c.drawLine(
        const Offset(84, 42),
        const Offset(92, 36),
        _line(Art.deep(color, .3), 1.8),
      );
    case 'crop_momo':
      paintPlastic(c, _circle(50, 58, 25), color, edge: 1.8);
      c.save();
      c.clipPath(_circle(50, 58, 25));
      c.drawCircle(const Offset(64, 46), 16, _fill(const Color(0x55FF6F7D)));
      c.restore();
      c.drawPath(
        Path()
          ..moveTo(50, 34)
          ..quadraticBezierTo(42, 58, 50, 82),
        _line(Art.deep(color, .25), 1.6),
      );
      _leafShape(c, const Offset(50, 34), const Offset(72, 22), _leaf, .4);
    default:
      paintPlastic(c, _circle(50, 58, 24), color);
  }
}

void _wild(Canvas c, String id, Color color) {
  switch (id) {
    case 'wild_tanpopo':
      c.drawLine(
        const Offset(50, 86),
        const Offset(50, 46),
        _line(_leafDark, 3),
      );
      _leafShape(c, const Offset(50, 82), const Offset(28, 66), _leaf, .3);
      _leafShape(c, const Offset(50, 82), const Offset(72, 68), _leaf, .3);
      for (var i = 0; i < 16; i++) {
        final a = i * math.pi / 8;
        c.drawLine(
          const Offset(50, 38),
          Offset(50 + math.cos(a) * 20, 38 + math.sin(a) * 20),
          _line(Art.deep(color, .12), 5),
        );
        c.drawLine(
          const Offset(50, 38),
          Offset(50 + math.cos(a) * 18, 38 + math.sin(a) * 18),
          _line(color, 3),
        );
      }
      paintPlastic(c, _circle(50, 38, 8), Art.deep(color, .1), edge: 1);
    case 'wild_shiitake':
      paintPlastic(
        c,
        _rrect(42, 52, 16, 30, 7),
        const Color(0xFFF2E6D0),
        edge: 1.6,
      );
      final cap = Path()
        ..moveTo(14, 58)
        ..quadraticBezierTo(18, 24, 50, 24)
        ..quadraticBezierTo(82, 24, 86, 58)
        ..quadraticBezierTo(50, 50, 14, 58)
        ..close();
      paintPlastic(c, cap, color, edge: 2);
      for (final (x, y) in const [
        (34.0, 40.0),
        (50.0, 34.0),
        (66.0, 40.0),
        (44.0, 48.0),
        (60.0, 48.0),
      ]) {
        c.drawCircle(Offset(x, y), 2.4, _fill(Art.light(color, .6)));
      }
    case 'wild_matsutake':
      paintPlastic(
        c,
        _rrect(40, 40, 20, 44, 9),
        const Color(0xFFF2E3C8),
        edge: 1.6,
      );
      final cap = Path()
        ..moveTo(30, 44)
        ..quadraticBezierTo(32, 22, 50, 22)
        ..quadraticBezierTo(68, 22, 70, 44)
        ..quadraticBezierTo(50, 38, 30, 44)
        ..close();
      paintPlastic(c, cap, color, edge: 1.8);
      c.drawLine(
        const Offset(44, 60),
        const Offset(48, 72),
        _line(Art.deep(color, .1), 1.4),
      );
    case 'wild_takenoko':
      final shoot = Path()
        ..moveTo(26, 84)
        ..quadraticBezierTo(30, 44, 52, 16)
        ..quadraticBezierTo(70, 44, 76, 84)
        ..close();
      paintPlastic(c, shoot, color, edge: 2);
      c.save();
      c.clipPath(shoot);
      for (final y in const [36.0, 52.0, 68.0]) {
        c.drawPath(
          Path()
            ..moveTo(20, y + 12)
            ..quadraticBezierTo(50, y - 6, 80, y + 12),
          _line(Art.deep(color, .3), 2),
        );
      }
      c.drawRect(
        const Rect.fromLTWH(0, 0, 100, 26),
        _fill(const Color(0xFF9CBF5A)),
      );
      c.restore();
    case 'wild_kuri':
      final nut = Path()
        ..moveTo(50, 22)
        ..quadraticBezierTo(80, 44, 76, 66)
        ..quadraticBezierTo(70, 84, 50, 84)
        ..quadraticBezierTo(30, 84, 24, 66)
        ..quadraticBezierTo(20, 44, 50, 22)
        ..close();
      paintPlastic(c, nut, color, edge: 2);
      c.save();
      c.clipPath(nut);
      c.drawRect(
        const Rect.fromLTWH(0, 70, 100, 30),
        _fill(const Color(0xFFE8C99A)),
      );
      c.restore();
      c.drawPath(nut, _line(Art.deep(color, .45), 2));
    case 'wild_yuzu':
      paintPlastic(c, _circle(50, 58, 25), color, edge: 1.8);
      for (final (x, y) in const [
        (40.0, 50.0),
        (56.0, 48.0),
        (62.0, 62.0),
        (46.0, 66.0),
        (52.0, 58.0),
      ]) {
        c.drawCircle(Offset(x, y), 1.3, _fill(Art.deep(color, .2)));
      }
      _leafShape(c, const Offset(52, 34), const Offset(76, 24), _leafDark, .4);
    case 'wild_hasu':
      for (final (a, tone) in [
        (-1.1, Art.deep(color, .08)),
        (1.1, Art.deep(color, .08)),
        (-.55, color),
        (.55, color),
        (0.0, Art.light(color, .25)),
      ]) {
        _turned(c, 50, 74, a, () {
          final petal = Path()
            ..moveTo(50, 76)
            ..quadraticBezierTo(34, 50, 50, 26)
            ..quadraticBezierTo(66, 50, 50, 76)
            ..close();
          paintPlastic(c, petal, tone, edge: 1.4, shine: .5);
        });
      }
      paintPlastic(c, _oval(50, 82, 60, 10), _leaf, edge: 1.2, shine: .3);
    case 'wild_kinmokusei':
      c.drawPath(
        Path()
          ..moveTo(16, 80)
          ..quadraticBezierTo(46, 64, 84, 26),
        _line(const Color(0xFF7A5A3E), 3),
      );
      _leafShape(c, const Offset(40, 66), const Offset(24, 50), _leafDark, .4);
      _leafShape(c, const Offset(70, 40), const Offset(84, 54), _leafDark, .4);
      for (final (x, y) in const [
        (46.0, 54.0),
        (58.0, 46.0),
        (52.0, 62.0),
        (64.0, 56.0),
        (40.0, 46.0),
        (70.0, 30.0),
      ]) {
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2 + .4;
          c.drawCircle(
            Offset(x + math.cos(a) * 3, y + math.sin(a) * 3),
            2.8,
            _fill(color),
          );
        }
        c.drawCircle(Offset(x, y), 1.4, _fill(Art.deep(color, .3)));
      }
    default:
      paintPlastic(c, _circle(50, 58, 24), color);
  }
}

/// Sobre de semillas con el dibujo de lo que sale.
void _packet(Canvas c, String crop) {
  final color = hatarakiItemColor(crop);
  paintPlastic(c, _rrect(24, 18, 52, 66, 6), Art.light(color, .72), edge: 1.8);
  c.drawPath(
    Path()
      ..moveTo(24, 26)
      ..lineTo(30, 22)
      ..lineTo(36, 26)
      ..lineTo(42, 22)
      ..lineTo(48, 26)
      ..lineTo(54, 22)
      ..lineTo(60, 26)
      ..lineTo(66, 22)
      ..lineTo(76, 26),
    _line(Art.deep(color, .25), 1.6),
  );
  _scaled(c, 50, 54, .5, () => _shape(c, crop));
  for (final (x, y) in const [
    (32.0, 76.0),
    (40.0, 78.0),
    (60.0, 77.0),
    (68.0, 75.0),
  ]) {
    c.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: 3, height: 4.4),
      _fill(const Color(0xFFB08A55)),
    );
  }
}

// --- Telas, tablas y rarezas ------------------------------------------------------

void _cloth(Canvas c, Color color, {bool silk = false}) {
  // Un tanmono: el rollo detrás y la tela que sale por debajo hacia delante.
  final tail = Path()
    ..moveTo(20, 40)
    ..lineTo(72, 40)
    ..lineTo(84, 68)
    ..quadraticBezierTo(74, 76, 64, 70)
    ..quadraticBezierTo(51, 80, 40, 72)
    ..quadraticBezierTo(28, 78, 16, 70)
    ..close();
  paintPlastic(c, tail, color, edge: 1.8);
  final fold = _line(Art.deep(color, .14), 1.2);
  c
    ..drawLine(const Offset(40, 54), const Offset(39, 72), fold)
    ..drawLine(const Offset(60, 54), const Offset(62, 70), fold);
  paintPlastic(c, _rrect(14, 20, 66, 30, 15), Art.deep(color, .06), edge: 1.8);
  paintPlastic(
    c,
    _oval(76, 35, 14, 30),
    Art.deep(color, .16),
    edge: 1.4,
    shine: 0,
  );
  final turn = _line(Art.deep(color, .32), 1);
  c
    ..drawOval(
      Rect.fromCenter(center: const Offset(76, 35), width: 9, height: 20),
      turn,
    )
    ..drawOval(
      Rect.fromCenter(center: const Offset(76, 35), width: 4, height: 9),
      _fill(_handle),
    );
  if (silk) {
    for (final (x, y, r) in const [
      (32.0, 62.0, 5.0),
      (52.0, 68.0, 5.0),
      (66.0, 58.0, 4.0),
      (36.0, 34.0, 4.0),
      (58.0, 30.0, 4.0),
    ]) {
      _blossom(c, x, y, r, Art.light(color, .5));
    }
  } else {
    final stitch = _line(Art.deep(color, .3), 1.2);
    c.drawPath(
      Path()
        ..moveTo(22, 70)
        ..quadraticBezierTo(30, 75, 40, 71)
        ..quadraticBezierTo(51, 78, 63, 69)
        ..quadraticBezierTo(71, 74, 77, 68),
      stitch,
    );
  }
}

void _spool(Canvas c, Color color) {
  paintPlastic(c, _rrect(26, 24, 48, 9, 4), _handle, edge: 1.4);
  paintPlastic(c, _rrect(32, 32, 36, 38, 6), color, edge: 1.8);
  final wrap = _line(Art.deep(color, .18), 1.2);
  for (var y = 38.0; y < 68; y += 5) {
    c.drawLine(Offset(33, y), Offset(67, y + 2), wrap);
  }
  paintPlastic(c, _rrect(26, 69, 48, 9, 4), _handle, edge: 1.4);
  c.drawPath(
    Path()
      ..moveTo(68, 52)
      ..quadraticBezierTo(86, 58, 80, 80),
    _line(color, 2.4),
  );
}

void _rare(Canvas c, String id, Color color) {
  switch (id) {
    case 'rare_feather':
      _turned(c, 50, 54, .6, () {
        final vane = Path()
          ..moveTo(50, 16)
          ..quadraticBezierTo(70, 36, 58, 76)
          ..lineTo(50, 82)
          ..quadraticBezierTo(30, 50, 50, 16)
          ..close();
        paintPlastic(c, vane, color, edge: 1.8);
        c.drawLine(
          const Offset(50, 18),
          const Offset(52, 92),
          _line(const Color(0xFFB9C4D0), 2),
        );
        for (var y = 30.0; y < 74; y += 8) {
          c.drawLine(
            Offset(51, y),
            Offset(60, y - 6),
            _line(const Color(0xFFD6DEE8), 1.2),
          );
          c.drawLine(
            Offset(51, y + 3),
            Offset(42, y - 3),
            _line(const Color(0xFFD6DEE8), 1.2),
          );
        }
      });
    case 'rare_shell':
      final fan = Path()..moveTo(50, 82);
      for (var i = 0; i <= 10; i++) {
        final a = math.pi + i * math.pi / 10;
        final r = i.isEven ? 36.0 : 32.0;
        fan.lineTo(50 + math.cos(a) * r, 66 + math.sin(a) * r);
      }
      fan.close();
      paintPlastic(c, fan, color, edge: 1.8);
      for (var i = 1; i < 10; i += 2) {
        final a = math.pi + i * math.pi / 10;
        c.drawLine(
          const Offset(50, 80),
          Offset(50 + math.cos(a) * 32, 66 + math.sin(a) * 32),
          _line(Art.deep(color, .22), 1.3),
        );
      }
      paintPlastic(c, _rrect(40, 76, 20, 9, 3), Art.deep(color, .1), edge: 1.2);
    case 'rare_amber':
      final drop = Path()
        ..moveTo(50, 18)
        ..quadraticBezierTo(80, 52, 74, 68)
        ..quadraticBezierTo(66, 86, 50, 86)
        ..quadraticBezierTo(34, 86, 26, 68)
        ..quadraticBezierTo(20, 52, 50, 18)
        ..close();
      paintPlastic(c, drop, color, edge: 2);
      c.drawCircle(
        const Offset(52, 64),
        12,
        _fill(Art.light(color, .45).withValues(alpha: .7)),
      );
      _leafShape(
        c,
        const Offset(46, 66),
        const Offset(58, 58),
        const Color(0xFF8C6A2E),
        .4,
      );
    case 'rare_ember':
      final flame = Path()
        ..moveTo(50, 86)
        ..quadraticBezierTo(20, 80, 26, 56)
        ..quadraticBezierTo(32, 40, 42, 34)
        ..quadraticBezierTo(42, 46, 50, 48)
        ..quadraticBezierTo(46, 30, 58, 14)
        ..quadraticBezierTo(62, 34, 72, 46)
        ..quadraticBezierTo(82, 60, 74, 76)
        ..quadraticBezierTo(66, 86, 50, 86)
        ..close();
      paintPlastic(c, flame, color, edge: 2);
      final core = Path()
        ..moveTo(50, 82)
        ..quadraticBezierTo(36, 78, 40, 64)
        ..quadraticBezierTo(46, 56, 52, 50)
        ..quadraticBezierTo(56, 62, 62, 66)
        ..quadraticBezierTo(64, 80, 50, 82)
        ..close();
      paintPlastic(c, core, const Color(0xFFFFD45A), edge: 0, shine: .6);
    case 'rare_cloud':
      _cloud(c, 50, 58, 1, color);
    case 'rare_moondust':
      paintPlastic(
        c,
        _rrect(40, 20, 20, 10, 3),
        const Color(0xFFB08A55),
        edge: 1.4,
      );
      final jar = Path()
        ..moveTo(38, 30)
        ..lineTo(62, 30)
        ..quadraticBezierTo(80, 44, 76, 70)
        ..quadraticBezierTo(72, 84, 50, 84)
        ..quadraticBezierTo(28, 84, 24, 70)
        ..quadraticBezierTo(20, 44, 38, 30)
        ..close();
      c.save();
      c.clipPath(jar);
      c.drawRect(const Rect.fromLTWH(0, 54, 100, 40), _fill(color));
      c.restore();
      paintPlastic(c, jar, const Color(0x55DDEBFF), edge: 1.8, shine: .8);
      paintTwinkle(c, const Offset(44, 66), 5, T.shellTop);
      paintTwinkle(c, const Offset(58, 72), 4, T.shellTop);
      paintTwinkle(c, const Offset(80, 30), 6, Art.spark);
    default:
      paintPlastic(c, _circle(50, 54, 20), color);
  }
}

/// Un furoshiki atado: el paquete de los encargos.
void _parcel(Canvas c, Color color) {
  final bundle = Path()
    ..moveTo(22, 50)
    ..quadraticBezierTo(20, 84, 50, 86)
    ..quadraticBezierTo(80, 84, 78, 50)
    ..quadraticBezierTo(50, 40, 22, 50)
    ..close();
  paintPlastic(c, bundle, color, edge: 2);
  // Lunares del estampado.
  for (final (x, y) in const [(34.0, 62.0), (50.0, 74.0), (64.0, 60.0)]) {
    c.drawCircle(Offset(x, y), 3.4, _fill(Art.light(color, .5)));
  }
  // El nudo con las dos orejas.
  for (final dir in const [-1.0, 1.0]) {
    paintPlastic(
      c,
      Path()
        ..moveTo(50, 46)
        ..quadraticBezierTo(50 + dir * 26, 20, 50 + dir * 12, 44)
        ..close(),
      Art.deep(color, .1),
      edge: 1.4,
    );
  }
  paintPlastic(c, _circle(50, 46, 7), Art.deep(color, .18), edge: 1.4);
}

void _cloud(Canvas c, double x, double y, double k, Color color) {
  final p = Path()
    ..addOval(
      Rect.fromCircle(center: Offset(x - 18 * k, y + 4 * k), radius: 14 * k),
    )
    ..addOval(Rect.fromCircle(center: Offset(x, y - 6 * k), radius: 18 * k))
    ..addOval(
      Rect.fromCircle(center: Offset(x + 18 * k, y + 2 * k), radius: 15 * k),
    )
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 30 * k, y, 60 * k, 18 * k),
        Radius.circular(9 * k),
      ),
    );
  // Unidas en una sola silueta, sin los bordes de cada bola por dentro.
  var cloud = Path();
  for (final m in p.computeMetrics()) {
    cloud = Path.combine(
      PathOperation.union,
      cloud,
      m.extractPath(0, m.length)..close(),
    );
  }
  paintPlastic(c, cloud, color, edge: 1.8 * k);
}

// --- Cocina y té ------------------------------------------------------------------

/// Un plato ovalado visto un poco desde arriba.
void _plateUnder(Canvas c, [Color color = _plate]) {
  paintPlastic(c, _oval(50, 70, 80, 26), color, edge: 1.8, shine: .5);
  c.drawOval(
    Rect.fromCenter(center: const Offset(50, 69), width: 58, height: 16),
    _line(Art.deep(color, .12), 1.2),
  );
}

/// Un cuenco con lo que lleva asomando por arriba ([top]).
void _bowl(Canvas c, Color bowl, void Function() top) {
  paintPlastic(
    c,
    _oval(50, 50, 66, 16),
    Art.deep(bowl, .25),
    edge: 0,
    shine: 0,
  );
  top();
  final body = Path()
    ..moveTo(16, 50)
    ..lineTo(84, 50)
    ..quadraticBezierTo(82, 80, 58, 82)
    ..lineTo(42, 82)
    ..quadraticBezierTo(18, 80, 16, 50)
    ..close();
  paintPlastic(c, body, bowl, edge: 2);
  paintPlastic(
    c,
    _rrect(38, 80, 24, 6, 3),
    Art.deep(bowl, .15),
    edge: 1.2,
    shine: 0,
  );
}

void _food(Canvas c, String id, Color color) {
  switch (id) {
    case 'food_onigiri':
      final tri = Path()
        ..moveTo(50, 20)
        ..quadraticBezierTo(58, 20, 80, 68)
        ..quadraticBezierTo(82, 80, 70, 80)
        ..lineTo(30, 80)
        ..quadraticBezierTo(18, 80, 20, 68)
        ..quadraticBezierTo(42, 20, 50, 20)
        ..close();
      paintPlastic(c, tri, _rice, edge: 2);
      paintPlastic(c, _rrect(37, 56, 26, 24, 3), _nori, edge: 1, shine: .4);
      c.drawCircle(const Offset(50, 44), 4, _fill(const Color(0xFFE8475F)));
    case 'food_iwashi' || 'food_aji':
      _plateUnder(c);
      for (final (dy, a) in const [(-8.0, -.08), (6.0, .06)]) {
        _turned(c, 50, 60 + dy, a, () {
          _scaled(c, 50, 60 + dy, .62, () {
            c.save();
            c.translate(-2, dy + 4);
            _fish(
              c,
              id == 'food_aji' ? const Color(0xFFE8A84A) : Art.deep(color, .1),
            );
            c.restore();
          });
        });
      }
      if (id == 'food_iwashi') {
        for (final x in const [40.0, 52.0]) {
          c.drawLine(
            Offset(x, 50),
            Offset(x + 6, 72),
            _line(const Color(0xFF6A4A33), 1.6),
          );
        }
      }
    case 'food_saba':
      _plateUnder(c);
      _turned(c, 46, 60, -.1, () {
        paintPlastic(
          c,
          _rrect(22, 48, 50, 22, 9),
          const Color(0xFFF2DCC0),
          edge: 1.8,
        );
        c.save();
        c.clipPath(_rrect(22, 48, 50, 22, 9));
        c.drawRect(const Rect.fromLTWH(20, 46, 60, 8), _fill(color));
        for (var x = 28.0; x < 70; x += 8) {
          c.drawLine(
            Offset(x, 48),
            Offset(x + 4, 54),
            _line(Art.deep(color, .4), 1.6),
          );
        }
        c.restore();
      });
      paintPlastic(
        c,
        _oval(76, 58, 16, 12),
        const Color(0xFFF7E05A),
        edge: 1.4,
      );
    case 'food_miso':
      _bowl(c, _lacquer, () {
        c.drawOval(
          Rect.fromCenter(center: const Offset(50, 50), width: 62, height: 13),
          _fill(color),
        );
        for (final x in const [38.0, 56.0]) {
          paintPlastic(
            c,
            _rrect(x, 44, 8, 7, 1.5),
            T.shellTop,
            edge: .8,
            shine: 0,
          );
        }
        for (final x in const [48.0, 66.0, 32.0]) {
          c.drawCircle(Offset(x, 50), 2.4, _line(_leaf, 1.4));
        }
      });
    case 'food_taimeshi':
      // Olla de barro con arroz y el besugo encima.
      _bowl(c, const Color(0xFF7A5A4A), () {
        c.drawOval(
          Rect.fromCenter(center: const Offset(50, 48), width: 62, height: 14),
          _fill(_rice),
        );
        _scaled(c, 50, 40, .5, () => _fish(c, color, h: 36, spiky: true));
      });
    case 'food_yakiimo':
      for (final (dx, a) in const [(-12.0, -.35), (12.0, .35)]) {
        _turned(c, 50 + dx, 62, a, () {
          paintPlastic(
            c,
            _oval(50 + dx, 62, 28, 44),
            const Color(0xFFA9496F),
            edge: 1.8,
          );
          paintPlastic(
            c,
            _oval(50 + dx, 58, 20, 34),
            color,
            edge: 1,
            shine: .6,
          );
        });
      }
      _steam(c, 50, 30);
    case 'food_unadon':
      _bowl(c, const Color(0xFF3A2E36), () {
        c.drawOval(
          Rect.fromCenter(center: const Offset(50, 48), width: 62, height: 14),
          _fill(_rice),
        );
        for (final x in const [30.0, 50.0]) {
          paintPlastic(c, _rrect(x, 34, 22, 14, 4), color, edge: 1.4);
          c.drawLine(
            Offset(x + 4, 39),
            Offset(x + 18, 39),
            _line(Art.deep(color, .35), 1.2),
          );
        }
      });
    case 'food_sushi':
      paintPlastic(
        c,
        _rrect(12, 64, 76, 14, 4),
        const Color(0xFFD9A86A),
        edge: 1.8,
      );
      for (final (x, fish) in [
        (34.0, color),
        (66.0, const Color(0xFFF5A87A)),
      ]) {
        paintPlastic(c, _rrect(x - 14, 50, 28, 16, 7), _rice, edge: 1.4);
        paintPlastic(c, _rrect(x - 16, 40, 32, 14, 7), fish, edge: 1.6);
        c.drawLine(
          Offset(x - 8, 44),
          Offset(x - 2, 50),
          _line(Art.light(fish, .5), 1.4),
        );
        c.drawLine(
          Offset(x + 2, 44),
          Offset(x + 8, 50),
          _line(Art.light(fish, .5), 1.4),
        );
      }
    case 'food_feast':
      // Jūbako: cajas lacadas apiladas, con comida en la de arriba.
      paintPlastic(c, _rrect(18, 58, 64, 24, 4), _lacquer, edge: 1.8);
      c.drawLine(
        const Offset(18, 70),
        const Offset(82, 70),
        _line(Art.gold, 2),
      );
      paintPlastic(
        c,
        _rrect(20, 36, 60, 24, 4),
        Art.deep(_lacquer, .1),
        edge: 1.8,
      );
      c.drawLine(
        const Offset(20, 48),
        const Offset(80, 48),
        _line(Art.gold, 2),
      );
      paintPlastic(c, _oval(34, 34, 16, 10), _rice, edge: 1);
      paintPlastic(c, _oval(50, 32, 14, 10), const Color(0xFFF5C84A), edge: 1);
      paintPlastic(c, _oval(66, 34, 16, 10), const Color(0xFFF0736B), edge: 1);
      _leafShape(c, const Offset(40, 30), const Offset(56, 24), _leaf, .35);
    default:
      _bowl(c, _china, () {
        c.drawOval(
          Rect.fromCenter(center: const Offset(50, 48), width: 62, height: 14),
          _fill(color),
        );
      });
  }
}

void _steam(Canvas c, double x, double y) {
  final steam = _line(T.shellTop.withValues(alpha: .9), 2.4);
  for (final dx in const [-7.0, 7.0]) {
    c.drawPath(
      Path()
        ..moveTo(x + dx, y + 8)
        ..quadraticBezierTo(x + dx - 5, y, x + dx, y - 6)
        ..quadraticBezierTo(x + dx + 5, y - 12, x + dx, y - 18),
      steam,
    );
  }
}

/// Un yunomi con el té y, flotando, lo que le da sabor.
void _tea(Canvas c, String id, Color tea) {
  _steam(c, 50, 22);
  if (id == 'tea_matcha') {
    // Chawan ancho con la espuma batida.
    final bowl = Path()
      ..moveTo(16, 46)
      ..lineTo(84, 46)
      ..quadraticBezierTo(82, 82, 50, 82)
      ..quadraticBezierTo(18, 82, 16, 46)
      ..close();
    paintPlastic(c, bowl, const Color(0xFF6E6A7A), edge: 2);
    paintPlastic(c, _oval(50, 47, 66, 14), tea, edge: 1, shine: .5);
    for (final (x, y) in const [(40.0, 46.0), (52.0, 48.0), (60.0, 45.0)]) {
      c.drawCircle(Offset(x, y), 1.6, _fill(Art.light(tea, .5)));
    }
    return;
  }
  final cup = Path()
    ..moveTo(26, 36)
    ..lineTo(74, 36)
    ..quadraticBezierTo(72, 82, 50, 82)
    ..quadraticBezierTo(28, 82, 26, 36)
    ..close();
  paintPlastic(c, cup, _china, edge: 2);
  c.drawLine(
    const Offset(28, 60),
    const Offset(72, 60),
    _line(const Color(0xFF7FA8D9), 2.4),
  );
  paintPlastic(c, _oval(50, 37, 46, 10), tea, edge: 1, shine: .5);
  switch (id) {
    case 'tea_tanpopo':
      _blossom(c, 50, 37, 7, const Color(0xFFFFD43F));
    case 'tea_sencha':
      _leafShape(c, const Offset(42, 38), const Offset(58, 34), _leaf, .35);
    case 'tea_genmai':
      for (final x in const [40.0, 48.0, 58.0]) {
        c.drawOval(
          Rect.fromCenter(center: Offset(x, 37), width: 4, height: 3),
          _fill(const Color(0xFF9A6A3A)),
        );
      }
    case 'tea_yuzu':
      paintPlastic(c, _circle(50, 36, 6), const Color(0xFFF7D13F), edge: 1);
    case 'tea_hoji':
      c.drawLine(
        const Offset(40, 36),
        const Offset(60, 34),
        _line(const Color(0xFF6A3E22), 2.4),
      );
    case 'tea_hasu':
      _leafShape(
        c,
        const Offset(44, 38),
        const Offset(58, 34),
        const Color(0xFFF59CC0),
        .45,
      );
    case 'tea_kinmoku':
      for (final x in const [42.0, 50.0, 58.0]) {
        c.drawCircle(Offset(x, 36), 2.4, _fill(const Color(0xFFF79A3A)));
      }
  }
}

// --- Equipo -----------------------------------------------------------------------

void _pick(Canvas c, Color head, {bool star = false}) {
  _turned(c, 50, 54, .5, () {
    paintPlastic(c, _rrect(46, 34, 8, 52, 4), _handle, edge: 1.6);
    final top = Path()
      ..moveTo(18, 46)
      ..quadraticBezierTo(50, 16, 82, 46)
      ..quadraticBezierTo(50, 32, 18, 46)
      ..close();
    paintPlastic(c, top, head, edge: 2);
    paintPlastic(c, _rrect(44, 30, 12, 12, 3), Art.deep(head, .15), edge: 1.4);
  });
  if (star) {
    paintTwinkle(c, const Offset(20, 24), 7, Art.spark);
    paintTwinkle(c, const Offset(84, 70), 5, Art.spark);
  }
}

void _outfit(Canvas c, String id, Color color) {
  switch (id) {
    case 'gear_scarf':
      paintPlastic(c, _oval(50, 36, 60, 26), color, edge: 2);
      c.drawOval(
        Rect.fromCenter(center: const Offset(50, 34), width: 34, height: 12),
        _fill(Art.deep(color, .3)),
      );
      for (final (x, a) in const [(38.0, .15), (54.0, -.1)]) {
        _turned(c, x, 48, a, () {
          paintPlastic(
            c,
            _rrect(x - 7, 44, 14, 38, 4),
            Art.deep(color, .05),
            edge: 1.6,
          );
          for (var i = 0; i < 4; i++) {
            c.drawLine(
              Offset(x - 5 + i * 3.4, 82),
              Offset(x - 5 + i * 3.4, 88),
              _line(color, 1.6),
            );
          }
          c.drawLine(
            Offset(x - 7, 58),
            Offset(x + 7, 58),
            _line(T.shellTop, 2),
          );
        });
      }
    case 'gear_cloak' || 'gear_beni_cloak':
      final cape = Path()
        ..moveTo(40, 22)
        ..lineTo(60, 22)
        ..quadraticBezierTo(80, 50, 84, 84)
        ..quadraticBezierTo(50, 76, 16, 84)
        ..quadraticBezierTo(20, 50, 40, 22)
        ..close();
      paintPlastic(c, cape, color, edge: 2);
      paintPlastic(c, _oval(50, 26, 30, 16), Art.deep(color, .15), edge: 1.6);
      paintPlastic(c, _circle(50, 34, 4.5), Art.gold, edge: 1.2);
    default:
      // Happi y kimono: mangas colgando detrás, cuerpo y cuello cruzado.
      final happi = id == 'gear_happi' || id == 'gear_ai_happi';
      final hem = happi ? 76.0 : 86.0;
      for (final x in const [12.0, 62.0]) {
        paintPlastic(
          c,
          _rrect(x, 24, 26, happi ? 30 : 38, 7),
          Art.deep(color, .1),
          edge: 1.8,
        );
      }
      final body = Path()
        ..moveTo(38, 20)
        ..lineTo(62, 20)
        ..lineTo(70, 26)
        ..lineTo(72, hem)
        ..lineTo(28, hem)
        ..lineTo(30, 26)
        ..close();
      paintPlastic(c, body, color, edge: 2);
      final collar = happi ? const Color(0xFF2E3A5A) : Art.light(color, .6);
      final band = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.butt
        ..color = collar;
      if (happi) {
        c
          ..drawLine(const Offset(42, 20), Offset(45, hem), band)
          ..drawLine(const Offset(58, 20), Offset(55, hem), band);
        c.drawCircle(const Offset(60, 60), 5, _line(T.shellTop, 2));
      } else {
        c
          ..drawLine(const Offset(40, 20), const Offset(58, 52), band)
          ..drawLine(const Offset(60, 20), const Offset(42, 52), band)
          ..drawLine(
            const Offset(60, 20),
            const Offset(42, 52),
            _line(Art.deep(collar, .2), .8),
          );
        final obi = id == 'gear_cloudrobe'
            ? const Color(0xFF9CC3F5)
            : const Color(0xFFF7C948);
        paintPlastic(c, _rrect(29, 50, 42, 11, 2), obi, edge: 1.4);
        c.drawLine(
          const Offset(30, 55.5),
          const Offset(70, 55.5),
          _line(const Color(0xFFE8475F), 1.4),
        );
      }
      if (id == 'gear_cloudrobe') {
        _cloud(c, 48, 74, .26, T.shellTop);
        _cloud(c, 22, 46, .18, T.shellTop);
        _cloud(c, 76, 50, .18, T.shellTop);
      }
      if (id == 'gear_ai_happi') {
        for (final (x, y) in const [(34.0, 40.0), (66.0, 62.0), (36.0, 68.0)]) {
          c.drawArc(
            Rect.fromCircle(center: Offset(x, y), radius: 5),
            math.pi,
            math.pi,
            false,
            _line(T.shellTop, 1.4),
          );
        }
      }
      if (id == 'gear_kimono' || id == 'gear_kin_kimono') {
        _blossom(c, 40, 74, 5, T.shellTop);
        _blossom(c, 60, 80, 4, T.shellTop);
        _blossom(c, 22, 48, 4, T.shellTop);
        _blossom(c, 78, 52, 4, T.shellTop);
      }
  }
}

/// Cesta de mimbre: el asa detrás, luego lo que lleve [inside] y el cuerpo
/// delante, para que lo de dentro asome sin taparla.
void _basket(Canvas c, Color color, [VoidCallback? inside]) {
  c.drawPath(
    Path()
      ..moveTo(24, 50)
      ..quadraticBezierTo(50, 4, 76, 50),
    _line(Art.deep(color, .3), 5),
  );
  inside?.call();
  final basket = Path()
    ..moveTo(16, 48)
    ..lineTo(84, 48)
    ..quadraticBezierTo(80, 82, 50, 82)
    ..quadraticBezierTo(20, 82, 16, 48)
    ..close();
  paintPlastic(c, basket, color, edge: 2);
  c.save();
  c.clipPath(basket);
  final weave = _line(Art.deep(color, .25), 1.4);
  for (var x = 10.0; x < 100; x += 8) {
    c
      ..drawLine(Offset(x, 46), Offset(x + 14, 86), weave)
      ..drawLine(Offset(x + 14, 46), Offset(x, 86), weave);
  }
  c.restore();
  paintPlastic(c, _rrect(14, 45, 72, 7, 3.5), Art.light(color, .1), edge: 1.6);
}

void _bag(Canvas c, String id, Color color) {
  switch (id) {
    case 'gear_basket':
      _basket(c, color);
    case 'gear_chest' || 'gear_sakurabox':
      paintPlastic(c, _rrect(16, 44, 68, 38, 5), color, edge: 2);
      paintPlastic(
        c,
        Path()
          ..moveTo(16, 46)
          ..quadraticBezierTo(16, 24, 50, 24)
          ..quadraticBezierTo(84, 24, 84, 46)
          ..close(),
        Art.light(color, .12),
        edge: 2,
      );
      if (id == 'gear_chest') {
        for (final x in const [26.0, 70.0]) {
          c.drawLine(Offset(x, 26), Offset(x, 82), _line(_metal, 4));
        }
        paintPlastic(c, _rrect(44, 42, 12, 14, 3), Art.gold, edge: 1.4);
      } else {
        for (final (x, y) in const [
          (32.0, 62.0),
          (52.0, 70.0),
          (68.0, 58.0),
          (46.0, 36.0),
        ]) {
          _blossom(c, x, y, 6, Art.light(_sakura, .2));
        }
      }
    case 'gear_shrine':
      // Omikoshi pequeño: tejado rojo, cuerpo dorado y varas.
      paintPlastic(
        c,
        _rrect(10, 70, 80, 7, 3),
        const Color(0xFF3A2E36),
        edge: 1.4,
      );
      paintPlastic(c, _rrect(28, 42, 44, 30, 3), Art.gold, edge: 1.8);
      paintPlastic(
        c,
        _rrect(40, 50, 20, 22, 2),
        const Color(0xFF3A2E36),
        edge: 1.2,
        shine: 0,
      );
      final roof = Path()
        ..moveTo(12, 44)
        ..quadraticBezierTo(50, 30, 88, 44)
        ..lineTo(74, 30)
        ..quadraticBezierTo(50, 16, 26, 30)
        ..close();
      paintPlastic(c, roof, color, edge: 2);
      paintTwinkle(c, const Offset(50, 16), 6, Art.spark);
    default:
      // Mochila con correas y bolsillo.
      c.drawPath(
        Path()
          ..moveTo(36, 36)
          ..quadraticBezierTo(36, 16, 50, 16)
          ..quadraticBezierTo(64, 16, 64, 36),
        _line(Art.deep(color, .25), 5),
      );
      paintPlastic(c, _rrect(20, 32, 60, 50, 14), color, edge: 2);
      paintPlastic(
        c,
        Path()
          ..moveTo(20, 50)
          ..quadraticBezierTo(50, 36, 80, 50)
          ..lineTo(80, 40)
          ..quadraticBezierTo(50, 26, 20, 40)
          ..close(),
        Art.deep(color, .12),
        edge: 1.6,
        shine: .3,
      );
      paintPlastic(
        c,
        _rrect(34, 58, 32, 18, 6),
        Art.light(color, .2),
        edge: 1.4,
      );
      paintPlastic(c, _rrect(46, 44, 8, 10, 2), Art.gold, edge: 1);
  }
}

void _charm(Canvas c, String id, Color gem) {
  switch (id) {
    case 'gear_quartz_charm':
      // Omamori: bolsita de tela con su cordón.
      c.drawPath(
        Path()
          ..moveTo(44, 26)
          ..quadraticBezierTo(50, 10, 56, 26),
        _line(const Color(0xFFE8475F), 3),
      );
      final pouch = Path()
        ..moveTo(32, 30)
        ..quadraticBezierTo(50, 22, 68, 30)
        ..lineTo(70, 82)
        ..lineTo(30, 82)
        ..close();
      paintPlastic(c, pouch, const Color(0xFFE8475F), edge: 2);
      paintPlastic(
        c,
        _rrect(40, 44, 20, 28, 3),
        T.shellTop,
        edge: 1.2,
        shine: 0,
      );
      _brilliant(c, gem, 50, 58, .3);
    case 'gear_sapphire_charm':
      c.drawPath(
        Path()
          ..moveTo(18, 20)
          ..quadraticBezierTo(50, 64, 82, 20),
        _line(Art.gold, 2.6),
      );
      c.drawCircle(const Offset(50, 42), 4, _line(Art.goldDark, 2));
      final drop = Path()
        ..moveTo(50, 46)
        ..quadraticBezierTo(70, 66, 62, 78)
        ..quadraticBezierTo(50, 88, 38, 78)
        ..quadraticBezierTo(30, 66, 50, 46)
        ..close();
      paintPlastic(c, drop, gem, edge: 2);
      _gleam(c, 44, 64, 4);
    case 'gear_pearl_crown':
      final crown = Path()
        ..moveTo(16, 74)
        ..lineTo(20, 40)
        ..lineTo(34, 56)
        ..lineTo(50, 30)
        ..lineTo(66, 56)
        ..lineTo(80, 40)
        ..lineTo(84, 74)
        ..close();
      paintPlastic(c, crown, Art.gold, edge: 2);
      for (final (x, y) in const [
        (20.0, 38.0),
        (50.0, 28.0),
        (80.0, 38.0),
        (36.0, 66.0),
        (50.0, 66.0),
        (64.0, 66.0),
      ]) {
        paintPlastic(c, _circle(x, y, 5), gem, edge: 1.2);
      }
    default:
      // Anillo de pie: aro con grosor, engaste y la piedra encima.
      final band = Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(
          Rect.fromCenter(center: const Offset(50, 62), width: 52, height: 44),
        )
        ..addOval(
          Rect.fromCenter(center: const Offset(50, 64), width: 38, height: 32),
        );
      paintPlastic(c, band, Art.gold, edge: 1.8);
      c.drawOval(
        Rect.fromCenter(center: const Offset(50, 64), width: 38, height: 32),
        _line(Art.goldDark, 1.4),
      );
      final seat = _poly(const [
        Offset(38, 36),
        Offset(62, 36),
        Offset(56, 46),
        Offset(44, 46),
      ]);
      paintPlastic(c, seat, Art.goldDark, edge: 1.4, shine: .4);
      _brilliant(c, gem, 50, 24, .48);
      final prong = _line(Art.goldDark, 2.2);
      c
        ..drawLine(const Offset(39, 36), const Offset(37, 31), prong)
        ..drawLine(const Offset(61, 36), const Offset(63, 31), prong);
  }
}

// --- Todo junto -----------------------------------------------------------------

/// Pinta un objeto sin su sombra (para meterlo dentro de otros dibujos).
void _shape(Canvas c, String id) {
  final color = hatarakiItemColor(id);
  final def = hItem(id);
  if (def?.kind == HItemKind.gear) {
    switch (def!.slot!) {
      case HGearSlot.tool:
        _pick(c, color, star: id == 'gear_star_pick');
      case HGearSlot.outfit:
        _outfit(c, id, color);
      case HGearSlot.bag:
        _bag(c, id, color);
      case HGearSlot.charm:
        _charm(c, id, color);
    }
    return;
  }
  if (def?.kind == HItemKind.furniture) {
    _furniture(c, id, color);
    return;
  }
  if (_craftTones.containsKey(id) && _craft(c, id, color)) return;
  switch (id.split('_').first) {
    case 'log':
      id == 'log_take' ? _bamboo(c, color) : _log(c, id, color);
    case 'fish':
      _fishFor(c, id, color);
    case 'ore':
      _ore(c, id, color);
    case 'bar':
      _bars(c, color, star: id == 'bar_star');
    case 'gem':
      _gem(c, id, color);
    case 'seed':
      _packet(c, 'crop_${id.substring(5)}');
    case 'crop':
      _crop(c, id, color);
    case 'wild':
      _wild(c, id, color);
    case 'plank':
      _plank(c, color);
    case 'cloth':
      _cloth(c, color, silk: id == 'cloth_silk');
    case 'silk':
      _spool(c, color);
    case 'rare':
      _rare(c, id, color);
    case 'parcel':
      _parcel(c, color);
    case 'food':
      _food(c, id, color);
    case 'tea':
      _tea(c, id, color);
    default:
      paintPlastic(c, _circle(50, 54, 20), color);
  }
}

/// Pinta un objeto en el lienzo de 100×100.
void paintHatarakiItem(Canvas c, String id) {
  paintGroundShadow(c, const Offset(50, 88), 60);
  _shape(c, id);
}

/// Pinta el objeto [id] sin sombra, centrado en [at] y dentro del radio [s]:
/// es lo que cae a la boca del Tama al darle de comer.
void paintHatarakiFood(Canvas c, String id, Offset at, double s) {
  // Los dibujos ocupan más o menos del 10 al 90 del lienzo de 100.
  final k = s * 2.3 / 80;
  c
    ..save()
    ..translate(at.dx - 50 * k, at.dy - 50 * k)
    ..scale(k);
  _shape(c, id);
  c.restore();
}

class _ItemPainter extends CustomPainter {
  _ItemPainter(this.item);

  final String item;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    paintHatarakiItem(canvas, item);
  }

  @override
  bool shouldRepaint(_ItemPainter old) => old.item != item;
}

// --- Oficios ----------------------------------------------------------------------

/// Un hacha con el filo hacia +x y el mango hacia arriba, con el ojo en el
/// origen.
void _axeLocal(Canvas c) {
  paintPlastic(c, _rrect(-3.5, -40, 7, 44, 3.5), _handle, edge: 1.6);
  final bit = Path()
    ..moveTo(4, -8)
    ..lineTo(16, -14)
    ..quadraticBezierTo(26, 0, 16, 14)
    ..lineTo(4, 8)
    ..close();
  paintPlastic(c, bit, _metal, edge: 1.8);
  c.drawPath(
    Path()
      ..moveTo(17, -11)
      ..quadraticBezierTo(24, 0, 17, 11),
    _line(T.shellTop, 1.6),
  );
  paintPlastic(c, _rrect(-7, -9, 13, 18, 3), Art.deep(_metal, .2), edge: 1.6);
}

void _paintSkill(Canvas c, HSkill skill) {
  paintGroundShadow(c, const Offset(50, 88), 64);
  switch (skill) {
    case HSkill.woodcutting:
      // Tocón con el hacha clavada.
      paintPlastic(c, _rrect(22, 56, 56, 28, 8), _tones['log_sugi']!, edge: 2);
      paintPlastic(c, _oval(50, 56, 56, 16), _heartwood, edge: 2, shine: .4);
      c.drawOval(
        Rect.fromCenter(center: const Offset(50, 56), width: 30, height: 8),
        _line(Art.deep(_heartwood, .3), 1.2),
      );
      // El hacha clavada en el corte: lo que entra en la madera no se ve.
      c
        ..save()
        ..clipRect(const Rect.fromLTRB(0, 0, 100, 57))
        ..translate(40, 41)
        ..rotate(.75)
        ..scale(1.25);
      _axeLocal(c);
      c.restore();
      c.drawLine(
        const Offset(40, 57),
        const Offset(56, 57),
        _line(Art.deep(_heartwood, .5), 2),
      );
    case HSkill.fishing:
      c.drawLine(const Offset(18, 86), const Offset(74, 14), _line(_handle, 4));
      c.drawPath(
        Path()
          ..moveTo(74, 14)
          ..quadraticBezierTo(86, 40, 70, 54),
        _line(T.inkSoft, 1.2),
      );
      _scaled(
        c,
        60,
        66,
        .55,
        () => _fish(c, _tones['fish_tai']!, h: 36, spiky: true),
      );
    case HSkill.mining:
      _scaled(c, 50, 70, .8, () => _ore(c, 'ore_jade', _tones['ore_jade']!));
      _scaled(c, 56, 40, .7, () => _pick(c, _metal));
    case HSkill.farming:
      paintPlastic(c, _oval(50, 74, 70, 20), const Color(0xFF8A5E3E), edge: 2);
      c.drawLine(
        const Offset(50, 72),
        const Offset(50, 46),
        _line(_leafDark, 3),
      );
      _leafShape(c, const Offset(50, 50), const Offset(26, 30), _leaf, .5);
      _leafShape(c, const Offset(50, 46), const Offset(74, 26), _leaf, .5);
    case HSkill.foraging:
      _basket(c, _tones['gear_basket']!, () {
        _scaled(
          c,
          38,
          20,
          .5,
          () => _wild(c, 'wild_shiitake', _tones['wild_shiitake']!),
        );
        _scaled(
          c,
          62,
          24,
          .45,
          () => _wild(c, 'wild_yuzu', _tones['wild_yuzu']!),
        );
      });
    case HSkill.agility:
      // Una sandalia de paja (waraji) vista desde arriba, ladeada, con su
      // tira roja en V y un ala en el talón: que no se confunda con una
      // bufanda.
      c
        ..save()
        ..translate(50, 52)
        ..rotate(.42)
        ..translate(-50, -52);
      final wing = Path()
        ..moveTo(62, 70)
        ..quadraticBezierTo(84, 56, 92, 64)
        ..quadraticBezierTo(84, 66, 88, 74)
        ..quadraticBezierTo(78, 74, 80, 82)
        ..quadraticBezierTo(70, 80, 62, 80)
        ..close();
      paintPlastic(c, wing, T.shellTop, edge: 1.6);
      final sole = RRect.fromRectAndCorners(
        const Rect.fromLTRB(34, 10, 66, 92),
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: const Radius.circular(13),
        bottomRight: const Radius.circular(13),
      );
      paintPlastic(c, Path()..addRRect(sole), const Color(0xFFE2BE7A), edge: 2);
      // El trenzado de la paja.
      final weave = _line(Art.deep(const Color(0xFFE2BE7A), .28), 1.6);
      for (var y = 20.0; y < 88; y += 8) {
        c.drawLine(Offset(38, y), Offset(62, y), weave);
      }
      // La tira: del dedo a los dos lados.
      final strap = _line(const Color(0xFFE8475F), 4.4);
      c
        ..drawLine(const Offset(50, 26), const Offset(36, 52), strap)
        ..drawLine(const Offset(50, 26), const Offset(64, 52), strap)
        ..drawCircle(
          const Offset(50, 26),
          3.6,
          Paint()..color = const Color(0xFFB8303F),
        )
        ..restore();
    case HSkill.cooking:
      // Olla nabe con tapa y vapor.
      _steam(c, 50, 22);
      paintPlastic(
        c,
        _rrect(16, 44, 68, 36, 14),
        const Color(0xFF5B6B79),
        edge: 2,
      );
      for (final x in const [10.0, 82.0]) {
        paintPlastic(
          c,
          _rrect(x, 50, 8, 8, 3),
          const Color(0xFF3A4750),
          edge: 1.2,
        );
      }
      paintPlastic(
        c,
        _oval(50, 44, 64, 14),
        const Color(0xFF8E9AA6),
        edge: 1.8,
      );
      paintPlastic(c, _rrect(44, 32, 12, 8, 4), _handle, edge: 1.4);
    case HSkill.carpentry:
      _plank(c, _tones['plank_sugi']!);
      _turned(c, 50, 40, .7, () {
        paintPlastic(c, _rrect(46, 30, 8, 44, 4), _handle, edge: 1.6);
        paintPlastic(c, _rrect(34, 20, 32, 14, 4), _metal, edge: 2);
      });
    case HSkill.smithing:
      // Yunque con el martillo encima.
      final anvil = Path()
        ..moveTo(14, 44)
        ..lineTo(80, 44)
        ..quadraticBezierTo(88, 44, 90, 38)
        ..lineTo(90, 52)
        ..lineTo(68, 56)
        ..lineTo(64, 70)
        ..lineTo(78, 82)
        ..lineTo(22, 82)
        ..lineTo(36, 70)
        ..lineTo(32, 56)
        ..quadraticBezierTo(16, 54, 14, 44)
        ..close();
      paintPlastic(c, anvil, const Color(0xFF6E7A86), edge: 2);
      _turned(c, 50, 30, -.4, () {
        paintPlastic(c, _rrect(48, 20, 7, 30, 3), _handle, edge: 1.4);
        paintPlastic(c, _rrect(36, 12, 30, 12, 3), _metal, edge: 1.8);
      });
      paintTwinkle(c, const Offset(24, 30), 6, Art.spark);
    case HSkill.tailoring:
      _spool(c, _tones['cloth_silk']!);
      _turned(c, 70, 40, .8, () {
        paintPlastic(c, _rrect(68, 8, 5, 60, 2.5), _metal, edge: 1.2);
        c.drawOval(
          Rect.fromCenter(center: const Offset(70.5, 14), width: 2, height: 6),
          _fill(T.shellTop),
        );
      });
    case HSkill.tea:
      // Dobin: tetera de barro con asa de bambú por arriba.
      const clay = Color(0xFFB8674A);
      c.drawPath(
        Path()
          ..moveTo(32, 50)
          ..cubicTo(32, 16, 68, 16, 68, 50),
        _line(Art.deep(_handle, .35), 6.5),
      );
      c.drawPath(
        Path()
          ..moveTo(32, 50)
          ..cubicTo(32, 16, 68, 16, 68, 50),
        _line(_handle, 4),
      );
      final spout = Path()
        ..moveTo(28, 66)
        ..quadraticBezierTo(16, 64, 10, 48)
        ..lineTo(17, 45)
        ..quadraticBezierTo(21, 56, 30, 56)
        ..close();
      paintPlastic(c, spout, Art.deep(clay, .08), edge: 1.6);
      _steam(c, 13, 30);
      paintPlastic(c, _oval(50, 64, 58, 40), clay, edge: 2);
      c.drawPath(
        Path()
          ..moveTo(24, 66)
          ..quadraticBezierTo(50, 74, 76, 66),
        _line(Art.light(clay, .35), 1.6),
      );
      for (final x in const [33.0, 67.0]) {
        paintPlastic(c, _circle(x, 49, 3.5), Art.deep(clay, .25), edge: 1);
      }
      paintPlastic(c, _oval(50, 46, 28, 9), Art.deep(clay, .12), edge: 1.4);
      paintPlastic(c, _circle(50, 41, 4), Art.deep(clay, .3), edge: 1.2);
      _leafShape(c, const Offset(44, 70), const Offset(58, 60), _leaf, .45);
    case HSkill.jewelry:
      _charm(c, 'gear_ruby_ring', _tones['gem_ruby']!);
      paintTwinkle(c, const Offset(80, 26), 6, Art.spark);
    case HSkill.pottery ||
        HSkill.dyeing ||
        HSkill.construction ||
        HSkill.writing ||
        HSkill.brewing ||
        HSkill.magic ||
        HSkill.study:
      _paintCraftSkill(c, skill);
    case HSkill.expedition:
      final paper = Path()
        ..moveTo(14, 34)
        ..lineTo(36, 28)
        ..lineTo(62, 36)
        ..lineTo(86, 30)
        ..lineTo(86, 78)
        ..lineTo(62, 84)
        ..lineTo(36, 76)
        ..lineTo(14, 82)
        ..close();
      paintPlastic(c, paper, const Color(0xFFF5E6C4), edge: 2);
      c.drawLine(
        const Offset(36, 28),
        const Offset(36, 76),
        _line(const Color(0xFFD9C49A), 1.4),
      );
      c.drawLine(
        const Offset(62, 36),
        const Offset(62, 84),
        _line(const Color(0xFFD9C49A), 1.4),
      );
      c.drawPath(
        Path()
          ..moveTo(22, 70)
          ..quadraticBezierTo(34, 48, 50, 60)
          ..quadraticBezierTo(62, 68, 70, 48),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFE8475F),
      );
      c.drawLine(
        const Offset(70, 50),
        const Offset(70, 18),
        _line(Art.pole, 2.4),
      );
      paintPlastic(
        c,
        _poly(const [Offset(70, 18), Offset(88, 24), Offset(70, 30)]),
        Art.flagRed,
        edge: 1.4,
      );
  }
}

class _SkillPainter extends CustomPainter {
  _SkillPainter(this.skill);

  final HSkill skill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    _paintSkill(canvas, skill);
  }

  @override
  bool shouldRepaint(_SkillPainter old) => old.skill != skill;
}

// --- Sitios -----------------------------------------------------------------------

/// Un paisaje dentro de una medalla: cielo, suelo y lo que tiene cada sitio.
void paintHatarakiZone(Canvas c, String zone) {
  paintGroundShadow(c, const Offset(50, 92), 70);
  final disc = _circle(50, 50, 40);
  final (sky, skyLow) = switch (zone) {
    'moon' => (const Color(0xFF26305A), const Color(0xFF4A4F8C)),
    'sky' => (const Color(0xFF8CC8FF), const Color(0xFFDDF0FF)),
    'onsen' => (const Color(0xFFF7C6A0), const Color(0xFFFFE8D2)),
    'coast' => (const Color(0xFFFFC98C), const Color(0xFFFFEBC8)),
    _ => (const Color(0xFF9FD6FF), const Color(0xFFE2F4FF)),
  };
  c.save();
  c.clipPath(disc);
  c.drawRect(
    const Rect.fromLTWH(0, 0, 100, 100),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [sky, skyLow],
      ).createShader(const Rect.fromLTWH(0, 10, 100, 70)),
  );
  switch (zone) {
    case 'meadow':
      paintPlastic(
        c,
        _oval(28, 80, 90, 44),
        const Color(0xFF8ED46A),
        edge: 0,
        shine: .4,
      );
      paintPlastic(
        c,
        _oval(78, 84, 80, 40),
        const Color(0xFF6CC05A),
        edge: 0,
        shine: .4,
      );
      for (final (x, y) in const [
        (30.0, 70.0),
        (50.0, 76.0),
        (68.0, 72.0),
        (40.0, 82.0),
      ]) {
        _blossom(c, x, y, 5, const Color(0xFFFFD43F));
      }
      c.drawCircle(const Offset(72, 30), 9, _fill(const Color(0xFFFFE27A)));
    case 'forest':
      paintPlastic(
        c,
        _rrect(0, 72, 100, 30, 0),
        const Color(0xFF6CC05A),
        edge: 0,
        shine: 0,
      );
      for (final (x, h, tone) in const [
        (28.0, 40.0, Color(0xFF3E8E5A)),
        (72.0, 44.0, Color(0xFF357F50)),
        (50.0, 52.0, Color(0xFF4FA35E)),
      ]) {
        paintPlastic(
          c,
          _rrect(x - 3, 70, 6, 12, 2),
          _handle,
          edge: 1,
          shine: 0,
        );
        paintPlastic(
          c,
          _poly([Offset(x, 74 - h), Offset(x + 16, 74), Offset(x - 16, 74)]),
          tone,
          edge: 1.4,
          shine: .5,
        );
      }
    case 'river':
      paintPlastic(
        c,
        _rrect(0, 60, 100, 40, 0),
        const Color(0xFF7CC66A),
        edge: 0,
        shine: 0,
      );
      final water = Path()
        ..moveTo(30, 60)
        ..quadraticBezierTo(60, 70, 40, 100)
        ..lineTo(80, 100)
        ..quadraticBezierTo(90, 72, 56, 60)
        ..close();
      paintPlastic(c, water, const Color(0xFF5BB6F0), edge: 0, shine: .6);
      for (final y in const [74.0, 86.0]) {
        c.drawPath(
          Path()
            ..moveTo(50, y)
            ..quadraticBezierTo(56, y - 4, 62, y),
          _line(T.shellTop, 2),
        );
      }
      paintPlastic(c, _oval(24, 80, 14, 8), _stone, edge: 1.2);
      paintPlastic(c, _oval(84, 70, 12, 7), _stone, edge: 1.2);
    case 'mountain':
      paintPlastic(
        c,
        _poly(const [Offset(-4, 90), Offset(34, 30), Offset(66, 90)]),
        const Color(0xFF7A8FA6),
        edge: 1.4,
      );
      paintPlastic(
        c,
        _poly(const [Offset(30, 92), Offset(66, 22), Offset(104, 92)]),
        const Color(0xFF6A7F96),
        edge: 1.4,
      );
      paintPlastic(
        c,
        _poly(const [
          Offset(56, 42),
          Offset(66, 22),
          Offset(76, 42),
          Offset(70, 38),
          Offset(66, 44),
          Offset(62, 38),
        ]),
        T.shellTop,
        edge: 1,
      );
      paintPlastic(
        c,
        _rrect(0, 82, 100, 20, 0),
        const Color(0xFF7CC66A),
        edge: 0,
        shine: 0,
      );
    case 'coast':
      c.drawCircle(const Offset(50, 54), 14, _fill(const Color(0xFFFF9A5A)));
      paintPlastic(
        c,
        _rrect(0, 56, 100, 30, 0),
        const Color(0xFF4FA8E8),
        edge: 0,
        shine: .5,
      );
      for (final x in const [20.0, 50.0, 80.0]) {
        c.drawPath(
          Path()
            ..moveTo(x - 10, 66)
            ..quadraticBezierTo(x, 58, x + 10, 66),
          _line(T.shellTop, 2.4),
        );
      }
      paintPlastic(
        c,
        _oval(50, 92, 110, 24),
        const Color(0xFFF5DDA0),
        edge: 0,
        shine: .3,
      );
    case 'onsen':
      paintPlastic(
        c,
        _rrect(0, 60, 100, 40, 0),
        const Color(0xFF9A928C),
        edge: 0,
        shine: 0,
      );
      paintPlastic(
        c,
        _oval(50, 74, 70, 22),
        const Color(0xFF8FD6E0),
        edge: 2,
        shine: .6,
      );
      for (final (x, y, r) in const [
        (18.0, 66.0, 9.0),
        (84.0, 70.0, 10.0),
        (30.0, 88.0, 8.0),
        (74.0, 88.0, 9.0),
      ]) {
        paintPlastic(c, _circle(x, y, r), _stone, edge: 1.4);
      }
      _steam(c, 40, 44);
      _steam(c, 62, 40);
    case 'sky':
      _cloud(c, 30, 76, .7, T.shellTop);
      _cloud(c, 76, 80, .6, T.shellTop);
      // Isla flotante con un árbol.
      final island = Path()
        ..moveTo(26, 50)
        ..lineTo(74, 50)
        ..quadraticBezierTo(64, 74, 50, 78)
        ..quadraticBezierTo(36, 74, 26, 50)
        ..close();
      paintPlastic(c, island, const Color(0xFF9A7A5A), edge: 1.6);
      paintPlastic(
        c,
        _rrect(24, 44, 52, 10, 5),
        const Color(0xFF7CC66A),
        edge: 1.4,
      );
      paintPlastic(c, _rrect(47, 30, 6, 16, 2), _handle, edge: 1);
      paintPlastic(c, _circle(50, 28, 11), const Color(0xFF4FA35E), edge: 1.4);
    case 'moon':
      for (final (x, y, r) in const [
        (24.0, 30.0, 3.0),
        (70.0, 22.0, 2.4),
        (80.0, 50.0, 3.2),
        (34.0, 54.0, 2.0),
      ]) {
        paintTwinkle(c, Offset(x, y), r * 1.6, const Color(0xFFFFF3B0));
      }
      final moon = Path.combine(
        PathOperation.difference,
        _circle(52, 40, 18),
        _circle(62, 34, 16),
      );
      paintPlastic(c, moon, const Color(0xFFFFE27A), edge: 1.6);
      paintPlastic(
        c,
        _oval(50, 90, 110, 34),
        const Color(0xFFB8B4D0),
        edge: 0,
        shine: .3,
      );
      for (final (x, y, r) in const [(30.0, 82.0, 5.0), (64.0, 86.0, 4.0)]) {
        c.drawCircle(Offset(x, y), r, _fill(const Color(0xFF9A96B8)));
      }
  }
  c.restore();
  // El canto de la medalla.
  c.drawPath(disc, _line(T.shellTop, 4));
  c.drawPath(
    _circle(50, 50, 42),
    _line(Art.deep(const Color(0xFFB8C4D0), .2), 1.4),
  );
}

class _ZonePainter extends CustomPainter {
  _ZonePainter(this.zone);

  final String zone;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    paintHatarakiZone(canvas, zone);
  }

  @override
  bool shouldRepaint(_ZonePainter old) => old.zone != zone;
}

// --- Canal --------------------------------------------------------------------------

/// El icono del canal: un tocón con el hacha clavada y una gema al lado. Lo
/// que se hace en Hatarakitama, de un vistazo.
void paintHataraki(Canvas canvas) {
  _paintSkill(canvas, HSkill.woodcutting);
  _brilliant(canvas, _tones['gem_sapphire']!, 82, 70, .36);
}
