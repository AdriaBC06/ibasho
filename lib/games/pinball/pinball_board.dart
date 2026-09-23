// Ibasho — la mesa del pinball pintada: plastico, cristal y luces.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/gacha.dart';
import '../../theme/menu_theme.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/gacha_art.dart';
import 'pinball.dart';

/// Los destellos de la mesa, apuntados en el reloj de efectos del canal.
class PinballFx {
  final Map<int, double> bumperAt = <int, double>{};
  final Map<int, double> targetAt = <int, double>{};
  final Map<int, double> postAt = <int, double>{};
  final Map<GachaCategory, double> holeAt = <GachaCategory, double>{};
  double slingLeftAt = -9;
  double slingRightAt = -9;
  final Map<int, double> springAt = <int, double>{};
  final Map<int, double> spinnerAt = <int, double>{};
  double kickbackAt = -9;

  /// Cuando aparecio el Tama a salvar la bola y cuando la solto.
  double rescueAt = -9;
  double releaseAt = -9;
  double nudgeAt = -9;

  /// La camara: la y de mundo del borde de arriba de lo que se ve, y cuanto
  /// se ve de alto.
  double camera = PinballTable.height - PinballTable.viewHeight;
  double view = PinballTable.viewHeight;

  /// Mueve la camara hacia la bola; con [snap] va directa.
  void follow(PinballGame game, double dt, {bool snap = false}) {
    final max = PinballTable.height - view;
    if (max <= 0) {
      camera = 0;
      return;
    }
    // En el lanzador, al salvarla o antes de jugar, se mira abajo.
    final low = game.phase != PinballPhase.rolling || game.rescueUntil != null;
    final target = low ? max : (game.ball.dy - view * .55).clamp(0.0, max);
    camera = snap ? target : camera + (target - camera) * (1 - math.exp(-7 * dt));
  }

  /// Chispas: donde, cuando y de que color.
  final List<(Offset, double, Color)> sparks = <(Offset, double, Color)>[];

  void clear() {
    bumperAt.clear();
    targetAt.clear();
    postAt.clear();
    springAt.clear();
    spinnerAt.clear();
    holeAt.clear();
    sparks.clear();
    slingLeftAt = slingRightAt = kickbackAt = rescueAt = releaseAt = nudgeAt = -9;
  }

  void spark(Offset at, double now, Color color) {
    sparks.add((at, now, color));
    if (sparks.length > 24) sparks.removeAt(0);
  }
}

/// Cuanto queda de un destello de [length] segundos que empezo en [at].
double _fade(double now, double? at, double length) {
  if (at == null) return 0;
  final t = (now - at) / length;
  return t < 0 || t > 1 ? 0 : 1 - t;
}

class PinballBoard extends StatelessWidget {
  const PinballBoard({
    super.key,
    required this.game,
    required this.fx,
    required this.clock,
    required this.accent,
    required this.accentDeep,
  });

  final PinballGame game;
  final PinballFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final Color accentDeep;

  /// Ocupa lo que le den: el ancho es la mesa entera y el alto, la ventana
  /// que sigue la camara de [fx].
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _BoardPainter(game, fx, clock, accent, accentDeep, IbashoSkin.of(context).surfaces),
        ),
      );
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.game, this.fx, this.clock, this.accent, this.accentDeep, this.surfaces) : super(repaint: clock);

  final Surfaces surfaces;

  final PinballGame game;
  final PinballFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final Color accentDeep;

  double get now => clock.value;
  PinballLayout get layout => game.layout;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / PinballTable.width;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(s);
    // El meneo de la mesa: un temblor corto de lado.
    final shake = _fade(now, fx.nudgeAt, .3);
    canvas.translate(math.sin(now * 90) * 3 * shake, -fx.camera);
    _field(canvas);
    _lane(canvas);
    _holes(canvas);
    _posts(canvas);
    _springs(canvas);
    _targets(canvas);
    _bumpers(canvas);
    _spinners(canvas);
    _guides(canvas);
    _slings(canvas);
    _lamps(canvas);
    _flippers(canvas);
    _ball(canvas);
    _sparks(canvas);
    canvas.restore();
  }

  Path get _domePath {
    const c = PinballTable.domeCenter;
    final path = Path()..moveTo(12, PinballTable.height + 10);
    path.lineTo(12, c.dy);
    for (var i = 0; i <= 40; i++) {
      final a = i / 40 * math.pi;
      path.lineTo(c.dx - math.cos(a) * PinballTable.domeRx, c.dy - math.sin(a) * PinballTable.domeRy);
    }
    path
      ..lineTo(392, PinballTable.height + 10)
      ..close();
    return path;
  }

  void _field(Canvas canvas) {
    final field = _domePath;
    const rect = Rect.fromLTWH(0, 0, PinballTable.width, PinballTable.height);
    canvas.drawPath(
      field,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color.lerp(surfaces.shellTop, accent, .1)!, Color.lerp(surfaces.shellBottom, accent, .16)!],
        ).createShader(rect),
    );

    // Rayos tenues desde los bumpers, como el fondo de un canal de la Wii.
    canvas.save();
    canvas.clipPath(field);
    final rays = Paint()..color = T.shellTop.withValues(alpha: .38);
    final o = layout.orbits.first.center;
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * 2 * math.pi + now * .05;
      final p = Path()
        ..moveTo(o.dx, o.dy)
        ..lineTo(o.dx + math.cos(a - .09) * 900, o.dy + math.sin(a - .09) * 900)
        ..lineTo(o.dx + math.cos(a + .09) * 900, o.dy + math.sin(a + .09) * 900)
        ..close();
      canvas.drawPath(p, rays);
    }
    canvas.restore();

    // El borde de plastico.
    canvas.drawPath(
      field,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = T.shellTop,
    );
    canvas.drawPath(
      field,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Art.chromeDark,
    );
  }

  void _lane(Canvas canvas) {
    // El carril, hundido como un cristal.
    const lane = Rect.fromLTWH(PinballTable.fieldRight + 2, PinballTable.gateY, 30, PinballTable.height - PinballTable.gateY);
    canvas.drawRect(
      lane,
      Paint()
        ..shader = LinearGradient(colors: <Color>[surfaces.wellTop, surfaces.wellBottom]).createShader(lane),
    );
    _rail(canvas, const Offset(PinballTable.fieldRight, PinballTable.height + 10), const Offset(PinballTable.fieldRight, PinballTable.gateY), 4);
    _rail(canvas, const Offset(PinballTable.fieldRight, PinballTable.gateY), const Offset(392, PinballTable.gateY - 20), 3,
        color: Color.lerp(Art.chrome, accent, .35)!);

    // El muelle del lanzador, que se comprime al tirar.
    final pull = game.phase == PinballPhase.ready ? game.pull : 0.0;
    final top = PinballTable.plungerRest.dy + 10 + pull * 14;
    for (var y = top; y < PinballTable.plungerRest.dy + 26; y += 4) {
      canvas.drawLine(Offset(368, y), Offset(384, y + 2), Paint()
        ..color = Art.chromeDark
        ..strokeWidth = 1.6);
    }
    final knob = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(365, top - 5, 22, 7), const Radius.circular(3.5)));
    paintPlastic(canvas, knob, accent, edge: 1.2);
  }

  void _rail(Canvas canvas, Offset a, Offset b, double w, {Color? color}) {
    canvas.drawLine(a, b, Paint()
      ..color = Art.chromeDark
      ..strokeWidth = w + 2
      ..strokeCap = StrokeCap.round);
    canvas.drawLine(a, b, Paint()
      ..color = color ?? Art.chrome
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round);
  }

  void _holes(Canvas canvas) {
    for (final entry in layout.holes.entries) {
      final cat = entry.key;
      final c = entry.value;
      const r = PinballTable.holeRadius;
      final color = categoryColor(cat);
      final open = game.open.contains(cat) || (game.phase == PinballPhase.captured && game.capturedIn == cat);
      final flash = _fade(now, fx.holeAt[cat], .9);

      if (open) {
        // Un agujero abierto: pozo oscuro con el aro de su color latiendo.
        final pulse = .5 + .5 * math.sin(now * 6);
        canvas.drawCircle(c, r + 7 + pulse * 3 + flash * 10, Paint()
          ..color = color.withValues(alpha: .25 + flash * .4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: <Color>[T.dusk, Art.deep(color, .6)]).createShader(Rect.fromCircle(center: c, radius: r)),
        );
        canvas.drawCircle(c, r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..color = color);
      } else {
        // Tapado: una tapa de plastico con su icono encima.
        canvas.drawCircle(c, r + 2, Paint()..color = Art.chromeDark.withValues(alpha: .5));
        final lid = Path()..addOval(Rect.fromCircle(center: c, radius: r));
        paintPlastic(canvas, lid, Art.light(color, .45), edge: 1.6);
        canvas.save();
        canvas.translate(c.dx - 13, c.dy - 13);
        canvas.scale(.26);
        paintCategory(canvas, cat);
        canvas.restore();
      }

      // Tres luces debajo: las dianas tumbadas de su color.
      final lit = game.knockedOf(cat);
      for (var i = 0; i < targetsPerCategory; i++) {
        final p = c.translate((i - 1) * 9.0, r + 10);
        final on = open || i < lit;
        canvas.drawCircle(p, 3.4, Paint()..color = on ? color : Art.chromeDark.withValues(alpha: .45));
        if (on) canvas.drawCircle(p.translate(-1, -1), 1.2, Paint()..color = T.shellTop.withValues(alpha: .8));
      }
    }
  }

  void _targets(Canvas canvas) {
    for (var i = 0; i < layout.targets.length; i++) {
      final spec = layout.targets[i];
      final color = categoryColor(spec.category);
      if (spec.rail > 0) {
        // El carril por donde se desliza.
        _rail(canvas, spec.at.translate(-spec.rail - PinballTable.targetHalf, 0),
            spec.at.translate(spec.rail + PinballTable.targetHalf, 0), 1.6,
            color: Art.chromeDark.withValues(alpha: .4));
      }
      final (a, b) = layout.targetEnds(i, game.time);
      final down = game.knocked.contains(i);
      final hit = _fade(now, fx.targetAt[i], .5);
      final mid = Offset.lerp(a, b, .5)!;
      final angle = math.atan2(b.dy - a.dy, b.dx - a.dx);
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(angle);
      // Tumbada se queda hundida y apagada, pero sigue en su carril: la
      // mesa no se para aunque caigan todas.
      final body = Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: PinballTable.targetHalf * 2 + (down ? 0 : 4),
            height: down ? PinballTable.targetThickness : PinballTable.targetThickness * 2 + 2,
          ),
          const Radius.circular(5),
        ));
      if (down) {
        canvas.drawPath(body, Paint()..color = Color.lerp(color, surfaces.shellBottom, .55)!.withValues(alpha: .7));
        canvas.drawPath(body, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Art.deep(color, .3).withValues(alpha: .5));
      } else {
        paintPlastic(canvas, body, Color.lerp(color, T.shellTop, hit * .6)!, edge: 1.4);
      }
      canvas.restore();
    }
  }

  void _bumpers(Canvas canvas) {
    for (final o in layout.orbits) {
      canvas.drawCircle(o.center, o.radius, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: .25));
    }
    for (var i = 0; i < layout.bumperCount; i++) {
      final c = layout.bumperAt(i, game.time);
      final hit = _fade(now, fx.bumperAt[i], .35);
      final r = layout.bumperRadiusOf(i) * (1 + hit * .12);
      paintGroundShadow(canvas, c.translate(0, r * .8), r * 2.1, .18);
      canvas.drawCircle(c, r + 3, Paint()..color = Color.lerp(accent, T.shellTop, hit)!);
      final cap = Path()..addOval(Rect.fromCircle(center: c, radius: r - 2));
      paintPlastic(canvas, cap, Color.lerp(T.shellTop, accent, .15 + hit * .5)!, edge: 1.6);
      paintStar(canvas, c, r * .42, Color.lerp(accentDeep, Art.gold, hit)!);
    }
  }

  void _posts(Canvas canvas) {
    for (var i = 0; i < layout.posts.length; i++) {
      final c = layout.posts[i];
      final hit = _fade(now, fx.postAt[i], .3);
      const r = PinballTable.postRadius;
      // Anillo de goma con el poste de metal dentro.
      canvas.drawCircle(c, r + 1 + hit * 2, Paint()..color = Color.lerp(accentDeep, Art.gold, hit)!);
      canvas.drawCircle(c, r - 1.4, Paint()..color = Art.chrome);
      canvas.drawCircle(c.translate(-1, -1), 1.3, Paint()..color = T.shellTop);
    }
  }

  void _springs(Canvas canvas) {
    for (var i = 0; i < layout.springs.length; i++) {
      final w = layout.springs[i];
      final left = w.a.dx < PinballTable.centerX;
      final flash = _fade(now, fx.springAt[i], .3);
      final x = left ? 16.0 : PinballTable.fieldRight - 4;
      final dir = left ? 1.0 : -1.0;
      final top = math.min(w.a.dy, w.b.dy);
      final bottom = math.max(w.a.dy, w.b.dy);
      // Un muelle en zigzag pegado a la pared, que vibra al rebotar.
      final wobble = flash * math.sin(now * 60) * 3;
      final path = Path()..moveTo(x, top);
      var k = 0;
      for (var y = top; y <= bottom; y += 7.5, k++) {
        path.lineTo(x + dir * ((k.isEven ? 1 : 6) + wobble), y);
      }
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(Art.chrome, accent, .4 + flash * .6)!);
    }
  }

  void _spinners(Canvas canvas) {
    for (var i = 0; i < layout.spinners.length; i++) {
      _spinner(canvas, i);
    }
  }

  void _spinner(Canvas canvas, int i) {
    final (c, half) = layout.spinners[i];
    final (a, b) = layout.spinnerEnds(i, game.spinnerAngles[i]);
    final hit = _fade(now, fx.spinnerAt[i], .3);
    canvas.drawCircle(c, half + 4, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: .22 + hit * .4));
    paintGroundShadow(canvas, c.translate(0, 6), half * 1.6, .12);
    final angle = game.spinnerAngles[i];
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final paddle = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: (b - a).distance + PinballTable.spinnerThickness * 2,
          height: PinballTable.spinnerThickness * 2 + 1,
        ),
        const Radius.circular(5),
      ));
    paintPlastic(canvas, paddle, Color.lerp(T.shellTop, accent, .55)!, edge: 1.2);
    canvas.restore();
    canvas.drawCircle(c, 4.5, Paint()..color = accentDeep);
    canvas.drawCircle(c.translate(-1, -1), 1.5, Paint()..color = T.shellTop);
  }

  void _guides(Canvas canvas) {
    for (final w in PinballTable.guides) {
      _rail(canvas, w.a, w.b, w.thickness * 2);
    }
  }

  void _slings(Canvas canvas) {
    for (final left in <bool>[true, false]) {
      final flash = _fade(now, left ? fx.slingLeftAt : fx.slingRightAt, .25);
      final pts = left ? PinballTable.leftSling : PinballTable.rightSling;
      final tri = Path()..addPolygon(pts, true);
      paintPlastic(canvas, tri, Color.lerp(T.shellTop, accent, .5 + flash * .4)!, edge: 2);
      canvas.drawLine(pts[0], pts[2], Paint()
        ..color = Color.lerp(accentDeep, Art.gold, flash)!
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
    }
  }

  void _lamps(Canvas canvas) {
    // Kickbacks: una flecha al fondo de cada calle de fuera.
    for (final left in <bool>[true, false]) {
      final on = left ? game.kickbackLeft : game.kickbackRight;
      final x = left ? 28.0 : 344.0;
      final arrow = Path()
        ..moveTo(x, PinballTable.kickbackY - 10)
        ..lineTo(x + 7, PinballTable.kickbackY)
        ..lineTo(x - 7, PinballTable.kickbackY)
        ..close();
      final pulse = on ? .75 + .25 * math.sin(now * 8) : 0.0;
      if (on) {
        canvas.drawCircle(Offset(x, PinballTable.kickbackY - 4), 12, Paint()
          ..color = Art.gold.withValues(alpha: .35 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }
      canvas.drawPath(arrow, Paint()..color = on ? Art.gold : Art.chromeDark.withValues(alpha: .4));
    }

    // El salvabolas: un escudo entre los flippers que parpadea al acabarse.
    final saver = game.saverLeft;
    final blink = saver > 0 && (saver > 2.5 || (now * 6).floor().isEven);
    final c = Offset(PinballTable.centerX, PinballTable.leftPivot.dy - 22);
    final shield = Path()
      ..moveTo(c.dx, c.dy - 8)
      ..quadraticBezierTo(c.dx + 8, c.dy - 7, c.dx + 7, c.dy - 3)
      ..quadraticBezierTo(c.dx + 6, c.dy + 5, c.dx, c.dy + 9)
      ..quadraticBezierTo(c.dx - 6, c.dy + 5, c.dx - 7, c.dy - 3)
      ..quadraticBezierTo(c.dx - 8, c.dy - 7, c.dx, c.dy - 8)
      ..close();
    if (blink) {
      canvas.drawCircle(c, 13, Paint()
        ..color = accent.withValues(alpha: .35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
    canvas.drawPath(shield, Paint()..color = blink ? accent : Art.chromeDark.withValues(alpha: .35));
  }

  void _flippers(Canvas canvas) {
    for (final left in <bool>[true, false]) {
      final pivot = left ? PinballTable.leftPivot : PinballTable.rightPivot;
      final tip = PinballTable.flipperTip(left: left, angle: left ? game.leftAngle : game.rightAngle);
      final angle = math.atan2(tip.dy - pivot.dy, tip.dx - pivot.dx);
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(angle);
      const len = PinballTable.flipperLength;
      final body = Path()
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: 9))
        ..addOval(Rect.fromCircle(center: const Offset(len, 0), radius: 5))
        ..moveTo(0, -9)
        ..lineTo(len, -5)
        ..lineTo(len, 5)
        ..lineTo(0, 9)
        ..close();
      final merged = Path.combine(PathOperation.union, Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 9)), body);
      paintGroundShadow(canvas, const Offset(len / 2, 9), len + 10, .2);
      paintPlastic(canvas, merged, T.shellTop, edge: 0);
      canvas.drawPath(merged, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = accentDeep);
      canvas.drawCircle(Offset.zero, 3.2, Paint()..color = accentDeep);
      canvas.restore();
    }
  }

  void _ball(Canvas canvas) {
    final b = game.current;
    if (b == null) return;
    if (game.phase == PinballPhase.lost || game.phase == PinballPhase.over) return;
    // En brazos del Tama la pinta el canal, encima de el.
    if (game.rescueUntil != null) return;
    var r = PinballTable.ballRadius;
    if (game.phase == PinballPhase.captured) {
      // Cae en el agujero: se encoge girando.
      final t = _fade(now, fx.holeAt[game.capturedIn], .6);
      if (t <= 0) return;
      r *= t;
    }
    paintGroundShadow(canvas, game.ball.translate(2, r * .9), r * 2, .25);
    paintGachaBall(canvas, game.ball, r, b.rarity, shadow: 0, spin: game.spin, twinkle: false);
  }

  void _sparks(Canvas canvas) {
    for (final (at, t0, color) in fx.sparks) {
      final t = (now - t0) / .45;
      if (t < 0 || t > 1) continue;
      for (var k = 0; k < 6; k++) {
        final a = k / 6 * 2 * math.pi + t0 * 7;
        final p = at + Offset(math.cos(a), math.sin(a)) * (8 + t * 22);
        canvas.drawCircle(p, 2.4 * (1 - t), Paint()..color = color.withValues(alpha: 1 - t));
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.game != game || old.accent != accent || old.accentDeep != accentDeep;
}
