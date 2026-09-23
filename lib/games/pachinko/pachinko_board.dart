// Ibasho — el tablero del pachinko pintado: laton, cristal y luces.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/gacha.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/gacha_art.dart';
import 'pachinko.dart';

/// Los destellos del tablero, apuntados en el reloj de efectos del canal.
class PachinkoFx {
  final Map<int, double> pinAt = <int, double>{};
  final Map<int, double> pocketAt = <int, double>{};
  double outAt = -9;

  /// Donde se va a soltar la siguiente bola (x de mundo), o `null`.
  double? aimX;

  /// Chispas: donde, cuando y de que color.
  final List<(Offset, double, Color)> sparks = <(Offset, double, Color)>[];

  /// Letreros que suben de un bolsillo: donde, cuando, que rareza sale y
  /// cuanto ha subido.
  final List<(Offset, double, Rarity, PocketKind)> popups = <(Offset, double, Rarity, PocketKind)>[];

  void clear() {
    pinAt.clear();
    pocketAt.clear();
    sparks.clear();
    popups.clear();
    outAt = -9;
  }

  void spark(Offset at, double now, Color color) {
    sparks.add((at, now, color));
    if (sparks.length > 24) sparks.removeAt(0);
  }

  void popup(Offset at, double now, Rarity rarity, PocketKind kind) {
    popups.add((at, now, rarity, kind));
    if (popups.length > 12) popups.removeAt(0);
  }
}

/// Cuanto queda de un destello de [length] segundos que empezo en [at].
double _fade(double now, double? at, double length) {
  if (at == null) return 0;
  final t = (now - at) / length;
  return t < 0 || t > 1 ? 0 : 1 - t;
}

/// El color de cada tipo de bolsillo.
Color pocketColor(PocketKind kind) => switch (kind) {
      PocketKind.out => const Color(0xFF8A94A6),
      PocketKind.same => const Color(0xFF9FB4CC),
      PocketKind.up1 => const Color(0xFF4FBF7A),
      PocketKind.up2 => const Color(0xFFF0506E),
    };

/// Lo que pone en cada bolsillo.
String pocketLabel(PocketKind kind) => switch (kind) {
      PocketKind.out => 'OUT',
      PocketKind.same => '=',
      PocketKind.up1 => '+1',
      PocketKind.up2 => '+2',
    };

class PachinkoBoard extends StatelessWidget {
  const PachinkoBoard({
    super.key,
    required this.game,
    required this.fx,
    required this.clock,
    required this.accent,
    required this.accentDeep,
  });

  final PachinkoGame game;
  final PachinkoFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final Color accentDeep;

  /// Ocupa lo que le den, con el tablero entero a lo ancho.
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: _BoardPainter(game, fx, clock, accent, accentDeep)),
      );
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.game, this.fx, this.clock, this.accent, this.accentDeep) : super(repaint: clock);

  final PachinkoGame game;
  final PachinkoFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final Color accentDeep;

  double get now => clock.value;
  PachinkoLayout get layout => game.layout;

  static const Color _brass = Color(0xFFC9A45C);
  static const Color _brassLight = Color(0xFFF4E2B0);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / PachinkoTable.width;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(s);
    _field(canvas);
    _rail(canvas);
    _out(canvas);
    _pins(canvas);
    _windmills(canvas);
    _pockets(canvas);
    _balls(canvas);
    _sparks(canvas);
    _popups(canvas);
    canvas.restore();
  }

  Path get _framePath {
    const l = PachinkoTable.left, r = PachinkoTable.right, t = PachinkoTable.top, c = PachinkoTable.corner;
    return Path()
      ..moveTo(l, PachinkoTable.height)
      ..lineTo(l, t + c)
      ..arcToPoint(const Offset(l + c, t), radius: const Radius.circular(c))
      ..lineTo(r - c, t)
      ..arcToPoint(const Offset(r, t + c), radius: const Radius.circular(c))
      ..lineTo(r, PachinkoTable.height)
      ..close();
  }

  void _field(Canvas canvas) {
    final field = _framePath;
    const rect = Rect.fromLTWH(0, 0, PachinkoTable.width, PachinkoTable.height);
    canvas.drawPath(
      field,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color.lerp(T.shellTop, accent, .08)!, Color.lerp(T.shellBottom, accent, .18)!],
        ).createShader(rect),
    );

    // Rayos tenues desde el tulipan, como el fondo de un canal de la Wii.
    canvas.save();
    canvas.clipPath(field);
    final rays = Paint()..color = T.shellTop.withValues(alpha: .4);
    final o = layout.pockets.firstWhere((p) => p.tulip).at;
    for (var i = 0; i < 14; i++) {
      final a = i / 14 * 2 * math.pi - now * .04;
      final p = Path()
        ..moveTo(o.dx, o.dy)
        ..lineTo(o.dx + math.cos(a - .08) * 900, o.dy + math.sin(a - .08) * 900)
        ..lineTo(o.dx + math.cos(a + .08) * 900, o.dy + math.sin(a + .08) * 900)
        ..close();
      canvas.drawPath(p, rays);
    }
    canvas.restore();

    canvas.drawPath(
      field,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = T.shellTop,
    );
    canvas.drawPath(
      field,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = Art.chromeDark,
    );
  }

  /// El riel de arriba, de donde salen las bolas, y la marca de donde va a
  /// caer la siguiente.
  void _rail(Canvas canvas) {
    const y = PachinkoTable.dropY - 10;
    final rail = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Art.chrome;
    canvas.drawLine(const Offset(PachinkoTable.dropMinX, y), const Offset(PachinkoTable.dropMaxX, y), rail);
    canvas.drawLine(
      const Offset(PachinkoTable.dropMinX, y - 1.2),
      const Offset(PachinkoTable.dropMaxX, y - 1.2),
      Paint()
        ..strokeWidth = 1
        ..color = T.shellTop,
    );
    final aim = fx.aimX;
    if (aim == null) return;
    final x = aim.clamp(PachinkoTable.dropMinX, PachinkoTable.dropMaxX);
    final pulse = .6 + .4 * math.sin(now * 6);
    final marker = Path()
      ..moveTo(x - 6, y - 8)
      ..lineTo(x + 6, y - 8)
      ..lineTo(x, y - 1)
      ..close();
    canvas.drawPath(marker, Paint()..color = accentDeep.withValues(alpha: pulse));
    // La guia de caida, punteada.
    final dash = Paint()
      ..strokeWidth = 1.2
      ..color = accentDeep.withValues(alpha: .25);
    for (var yy = y + 6; yy < 70; yy += 6) {
      canvas.drawLine(Offset(x, yy), Offset(x, yy + 3), dash);
    }
  }

  /// La salida de abajo: un canal oscuro donde se pierden las bolas.
  void _out(Canvas canvas) {
    const top = PachinkoTable.outY - 4;
    final flash = _fade(now, fx.outAt, .3);
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTRB(PachinkoTable.left + 4, top, PachinkoTable.right - 4, PachinkoTable.height + 8),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = Color.lerp(const Color(0xFF3A4152), const Color(0xFF5A6377), flash)!);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Art.chromeDark,
    );
    final text = TextPainter(
      text: TextSpan(
        text: 'OUT',
        style: Ty.numeral(11, weight: FontWeight.w800, color: T.shellTop.withValues(alpha: .55))
            .copyWith(letterSpacing: 3),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(PachinkoTable.width / 2 - text.width / 2, top + 5));
  }

  void _pins(Canvas canvas) {
    final body = Paint()..color = _brass;
    final shine = Paint()..color = _brassLight;
    const r = PachinkoTable.pinRadius;
    for (var i = 0; i < layout.pins.length; i++) {
      final c = layout.pins[i];
      final hit = _fade(now, fx.pinAt[i], .18);
      canvas.drawCircle(c.translate(.8, 1), r, Paint()..color = const Color(0x33000000));
      if (hit > 0) {
        canvas.drawCircle(c, r + 2.5 * hit, Paint()..color = Art.gold.withValues(alpha: .6 * hit));
      }
      canvas.drawCircle(c, r, body);
      canvas.drawCircle(c.translate(-.7, -.7), r * .45, shine);
    }
  }

  void _windmills(Canvas canvas) {
    for (var i = 0; i < layout.windmills.length; i++) {
      final c = layout.windmills[i].center;
      final tips = game.windmillTips(i);
      for (var k = 0; k < tips.length; k++) {
        final color = k.isEven ? const Color(0xFFFFD166) : const Color(0xFF6FC3F0);
        final dir = tips[k] - c;
        final side = Offset(-dir.dy, dir.dx) * .28;
        final blade = Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(tips[k].dx + side.dx, tips[k].dy + side.dy)
          ..lineTo(tips[k].dx - side.dx * .2, tips[k].dy - side.dy * .2)
          ..close();
        canvas.drawPath(blade, Paint()..color = color);
        canvas.drawPath(
          blade,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8
            ..color = Art.deep(color, .5),
        );
      }
      canvas.drawCircle(c, 3.2, Paint()..color = Art.chrome);
      canvas.drawCircle(c.translate(-.8, -.8), 1.2, Paint()..color = T.shellTop);
    }
  }

  void _pockets(Canvas canvas) {
    for (var i = 0; i < layout.pockets.length; i++) {
      final p = layout.pockets[i];
      final color = pocketColor(p.kind);
      final flash = _fade(now, fx.pocketAt[i], .6);

      // El halo cuando entra una bola.
      if (flash > 0) {
        canvas.drawCircle(p.at.translate(0, 6), 18 + 10 * (1 - flash), Paint()..color = color.withValues(alpha: .45 * flash));
      }

      // El cubo.
      final cup = Path()
        ..moveTo(p.leftLip.dx, p.leftLip.dy)
        ..lineTo(p.leftLip.dx + 1.5, p.at.dy + PachinkoTable.cupDepth)
        ..lineTo(p.rightLip.dx - 1.5, p.at.dy + PachinkoTable.cupDepth)
        ..lineTo(p.rightLip.dx, p.rightLip.dy)
        ..close();
      canvas.drawPath(cup, Paint()..color = Color.lerp(color, T.shellTop, .55)!.withValues(alpha: .9));
      final edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = Art.deep(color, .45);
      canvas.drawPath(
        Path()
          ..moveTo(p.leftLip.dx, p.leftLip.dy)
          ..lineTo(p.leftLip.dx + 1.5, p.at.dy + PachinkoTable.cupDepth)
          ..lineTo(p.rightLip.dx - 1.5, p.at.dy + PachinkoTable.cupDepth)
          ..lineTo(p.rightLip.dx, p.rightLip.dy),
        edge,
      );

      // Los brazos del embudo, o las alas del tulipan.
      if (p.tulip) {
        final (la, lb, ra, rb) = game.tulipWings(p);
        for (final (a, b) in <(Offset, Offset)>[(la, lb), (ra, rb)]) {
          final dir = b - a;
          final side = Offset(-dir.dy, dir.dx) * (.32 * (a == la ? 1 : -1));
          final wing = Path()
            ..moveTo(a.dx, a.dy)
            ..quadraticBezierTo(a.dx + dir.dx * .5 - side.dx, a.dy + dir.dy * .5 - side.dy, b.dx, b.dy)
            ..lineTo(a.dx + dir.dx * .3, a.dy + dir.dy * .3)
            ..close();
          canvas.drawPath(wing, Paint()..color = color);
          canvas.drawPath(
            wing,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = Art.deep(color, .5),
          );
        }
      } else {
        final arm = Paint()
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = Art.deep(color, .3);
        for (final w in p.arms) {
          canvas.drawLine(w.a, w.b, arm);
        }
      }

      // Los labios: dos remaches del color de la rareza mas alta que cabe.
      final fits = RarityArt.of(p.fits);
      for (final lip in <Offset>[p.leftLip, p.rightLip]) {
        canvas.drawCircle(lip, PachinkoTable.lipRadius + .6, Paint()..color = Art.deep(fits, .45));
        canvas.drawCircle(lip, PachinkoTable.lipRadius - .4, Paint()..color = fits);
      }

      // El letrero.
      final text = TextPainter(
        text: TextSpan(
          text: pocketLabel(p.kind),
          style: Ty.numeral(8.5, weight: FontWeight.w900, color: Art.deep(color, .6)).copyWith(height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(p.at.dx - text.width / 2, p.at.dy + PachinkoTable.cupDepth + 3));
    }
  }

  void _balls(Canvas canvas) {
    for (final b in game.flying) {
      paintGroundShadow(canvas, b.pos.translate(1.5, b.radius * .9), b.radius * 2, .2);
      paintGachaBall(canvas, b.pos, b.radius, b.rarity, shadow: 0, spin: b.spin, twinkle: false);
    }
  }

  void _sparks(Canvas canvas) {
    for (final (at, t0, color) in fx.sparks) {
      final t = (now - t0) / .45;
      if (t < 0 || t > 1) continue;
      for (var k = 0; k < 6; k++) {
        final a = k / 6 * 2 * math.pi + t0 * 7;
        final p = at + Offset(math.cos(a), math.sin(a)) * (6 + t * 18);
        canvas.drawCircle(p, 2 * (1 - t), Paint()..color = color.withValues(alpha: 1 - t));
      }
    }
  }

  /// Lo que sale de cada bolsillo sube y se desvanece: la bola nueva con su
  /// sigla, o la de antes tachada si se ha quedado igual.
  void _popups(Canvas canvas) {
    for (final (at, t0, rarity, kind) in fx.popups) {
      final t = (now - t0) / 1.1;
      if (t < 0 || t > 1) continue;
      final prize = pachinkoPrize(rarity, kind);
      if (prize == null) continue;
      final alpha = t < .7 ? 1.0 : 1 - (t - .7) / .3;
      final c = at.translate(0, -8 - 26 * Curves.easeOut.transform(t));
      final r = 7.0 * (t < .15 ? Curves.easeOutBack.transform(t / .15) : 1);
      canvas.saveLayer(Rect.fromCircle(center: c, radius: 40), Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      paintGachaBall(canvas, c, r, prize, shadow: 0, twinkle: false);
      final text = TextPainter(
        text: TextSpan(
          text: prize.label,
          style: Ty.numeral(9, weight: FontWeight.w900, color: Art.deep(RarityArt.of(prize), .55)).copyWith(
            height: 1,
            shadows: const <Shadow>[Shadow(color: Color(0xFFFFFFFF), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(c.dx + r + 2, c.dy - text.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) =>
      old.game != game || old.accent != accent || old.accentDeep != accentDeep;
}
