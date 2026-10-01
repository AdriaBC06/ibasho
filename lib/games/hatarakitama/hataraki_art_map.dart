// Ibasho — Hatarakitama: las casillas del mapa de expedición.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_art.dart';

/// Una casilla del mapa de [zone]: una ficha redonda con lo que hay. Con
/// niebla, una nube con una interrogación.
class HatarakiNodeIcon extends StatelessWidget {
  const HatarakiNodeIcon(
    this.zone,
    this.kind, {
    super.key,
    this.size = 40,
    this.fog = false,
  });

  final String zone;
  final HNodeKind kind;
  final double size;
  final bool fog;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _NodePainter(zone, kind, fog)),
  );
}

class _NodePainter extends CustomPainter {
  _NodePainter(this.zone, this.kind, this.fog);

  final String zone;
  final HNodeKind kind;
  final bool fog;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100, size.height / 100);
    paintHatarakiNode(canvas, zone, kind, fog: fog);
  }

  @override
  bool shouldRepaint(_NodePainter old) =>
      old.zone != zone || old.kind != kind || old.fog != fog;
}

const Map<HNodeKind, Color> _nodeTones = {
  HNodeKind.loot: Color(0xFFF3E3C8),
  HNodeKind.forage: Color(0xFFCDEBC0),
  HNodeKind.danger: Color(0xFFF6B3A8),
  HNodeKind.rest: Color(0xFFCFE3F5),
  HNodeKind.treasure: Color(0xFFFFE08A),
  HNodeKind.order: Color(0xFFF3D9C8),
};

/// Pinta una casilla en el lienzo de 100×100.
void paintHatarakiNode(
  Canvas c,
  String zone,
  HNodeKind kind, {
  bool fog = false,
}) {
  if (fog) {
    paintPlastic(c, _circle(50, 50, 44), const Color(0xFFD9DDE3), edge: 2);
    _cloud(c, 50, 46, .95, const Color(0xFFF4F6F9));
    final ink = _line(const Color(0xFF7D8794), 7);
    c
      ..drawPath(
        Path()
          ..moveTo(40, 40)
          ..quadraticBezierTo(40, 28, 50, 28)
          ..quadraticBezierTo(61, 28, 61, 38)
          ..quadraticBezierTo(61, 46, 50, 50)
          ..lineTo(50, 56),
        ink,
      )
      ..drawCircle(const Offset(50, 68), 4.5, _fill(const Color(0xFF7D8794)));
    return;
  }
  paintPlastic(c, _circle(50, 50, 44), _nodeTones[kind]!, edge: 2);
  final loot = hZoneById[zone]!.loot;
  switch (kind) {
    case HNodeKind.loot:
      final common = loot.reduce((a, b) => a.chance >= b.chance ? a : b);
      _scaled(c, 50, 52, .62, () => _shape(c, common.item));
    case HNodeKind.forage:
      final rare = loot.reduce((a, b) => a.chance <= b.chance ? a : b);
      _scaled(c, 50, 52, .6, () => _shape(c, rare.item));
      paintTwinkle(c, const Offset(74, 26), 8, Art.spark);
    case HNodeKind.danger:
      // Un estallido con la exclamación.
      final burst = Path();
      for (var i = 0; i < 16; i++) {
        final r = i.isEven ? 34.0 : 22.0;
        final a = i * math.pi / 8 - math.pi / 2;
        final p = Offset(50 + r * math.cos(a), 50 + r * math.sin(a));
        i == 0 ? burst.moveTo(p.dx, p.dy) : burst.lineTo(p.dx, p.dy);
      }
      paintPlastic(c, burst..close(), const Color(0xFFE0493E), edge: 1.6);
      paintPlastic(c, _rrect(45, 30, 10, 26, 5), T.shellTop, edge: 0);
      paintPlastic(c, _circle(50, 66, 5.5), T.shellTop, edge: 0);
    case HNodeKind.rest:
      // Una hoguera: dos leños cruzados y la llama.
      _turned(c, 50, 70, .35, () {
        paintPlastic(c, _rrect(26, 64, 48, 11, 5), _handle, edge: 1.2);
      });
      _turned(c, 50, 70, -.35, () {
        paintPlastic(c, _rrect(26, 64, 48, 11, 5), _handle, edge: 1.2);
      });
      paintPlastic(
        c,
        Path()
          ..moveTo(50, 20)
          ..quadraticBezierTo(70, 44, 64, 58)
          ..quadraticBezierTo(58, 70, 50, 70)
          ..quadraticBezierTo(42, 70, 36, 58)
          ..quadraticBezierTo(30, 44, 50, 20)
          ..close(),
        const Color(0xFFFF8A3D),
        edge: 1.4,
      );
      paintPlastic(
        c,
        Path()
          ..moveTo(50, 40)
          ..quadraticBezierTo(60, 54, 56, 62)
          ..quadraticBezierTo(50, 68, 44, 62)
          ..quadraticBezierTo(40, 54, 50, 40)
          ..close(),
        const Color(0xFFFFD86B),
        edge: 0,
      );
    case HNodeKind.order:
      // El paquete del encargo con un papelito.
      _scaled(c, 50, 54, .66, () => _shape(c, 'parcel'));
      paintPlastic(c, _rrect(62, 18, 16, 20, 2), const Color(0xFFFFFBF2));
      paintPlastic(c, _circle(70, 19, 2.4), const Color(0xFFE0493E));
    case HNodeKind.treasure:
      // Un cofre con la cerradura de oro.
      paintPlastic(c, _rrect(22, 46, 56, 32, 5), _handle, edge: 1.6);
      paintPlastic(
        c,
        Path()
          ..moveTo(22, 50)
          ..quadraticBezierTo(22, 26, 50, 26)
          ..quadraticBezierTo(78, 26, 78, 50)
          ..close(),
        Art.deep(_handle, .15),
        edge: 1.6,
      );
      paintPlastic(c, _rrect(22, 46, 56, 6, 2), const Color(0xFFE8B84A));
      paintPlastic(
        c,
        _rrect(44, 44, 12, 16, 3),
        const Color(0xFFFFD45A),
        edge: 1,
      );
      paintTwinkle(c, const Offset(76, 24), 8, Art.spark);
  }
}
