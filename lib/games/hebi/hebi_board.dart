// Ibasho — el tablero de Hebi: la serpiente de plastico lacado que se
// desliza entre casillas, la comida de Tama y los destellos al comer.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/menu_theme.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../ui/tama/tama_food.dart';
import '../../ui/widgets/channel_art.dart';
import 'hebi.dart';

/// Colores de la serpiente. Son de la ilustracion, no del acento: un juguete
/// se ve igual con cualquier tema, como las piezas de Tsumiki.
abstract final class HebiColors {
  static const Color body = Color(0xFF74DDA2);
  static const Color belly = Color(0xFFD9F7C8);
  static const Color spot = Color(0xFF4FBF84);
}

/// Tiempos de los efectos, en el reloj de efectos del canal.
class HebiFx {
  static const double eatTime = .45;
  static const double overTime = .9;

  /// Donde se ha comido lo ultimo y cuando.
  Cell? eatAt;
  double eatenAt = -9;
  double overAt = -1;
  double busyUntil = 0;

  void touch(double until) => busyUntil = math.max(busyUntil, until);

  void clear() {
    eatAt = null;
    eatenAt = -9;
    overAt = -1;
    busyUntil = 0;
  }
}

class HebiBoard extends StatelessWidget {
  const HebiBoard({
    super.key,
    required this.game,
    required this.cellSize,
    required this.fx,
    required this.clock,
    required this.accent,
    this.reducedMotion = false,
  });

  final HebiGame game;
  final double cellSize;
  final HebiFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size(HebiGame.width * cellSize, HebiGame.height * cellSize),
          painter: _BoardPainter(game, cellSize, fx, clock, accent, reducedMotion, IbashoSkin.of(context).surfaces),
        ),
      );
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.game, this.cell, this.fx, this.clock, this.accent, this.reduced, this.surfaces)
      : super(repaint: clock);

  final HebiGame game;
  final double cell;
  final HebiFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final bool reduced;
  final Surfaces surfaces;

  Offset _center(Cell c) => Offset((c.$1 + .5) * cell, (c.$2 + .5) * cell);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final full = Offset.zero & size;
    final radius = Radius.circular(cell * .3);

    // El campo: cristal hundido con un damero muy tenue.
    canvas.drawRRect(
      RRect.fromRectAndRadius(full, radius),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(surfaces.shellTop, accent, .06)!, Color.lerp(surfaces.shellBottom, accent, .16)!],
        ).createShader(full),
    );
    final check = Paint()..color = accent.withValues(alpha: .06);
    for (var y = 0; y < HebiGame.height; y++) {
      for (var x = (y % 2); x < HebiGame.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), check);
      }
    }

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(full, radius));

    // La comida, con un brillo debajo y un balanceo suave.
    final food = game.food;
    if (food != null) {
      final c = _center(food);
      final bob = reduced ? 0.0 : math.sin(t * 4) * cell * .05;
      canvas.drawCircle(
        c,
        cell * .7,
        Paint()
          ..shader = RadialGradient(colors: [Art.spark.withValues(alpha: .35), Art.spark.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: cell * .7)),
      );
      paintFood(canvas, game.foodKind, c.translate(0, bob), cell * .62);
    }

    // Destello al comer: un anillo que se abre y unas chispas.
    final eatAt = fx.eatAt;
    final ek = (t - fx.eatenAt) / HebiFx.eatTime;
    if (eatAt != null && ek >= 0 && ek < 1) {
      final c = _center(eatAt);
      canvas.drawCircle(
        c,
        cell * (.4 + ek * .9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .12 * (1 - ek)
          ..color = Art.spark.withValues(alpha: 1 - ek),
      );
      if (!reduced) {
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3 + .3;
          paintTwinkle(canvas, c + Offset(math.cos(a), math.sin(a)) * cell * (.5 + ek * .8), cell * .14 * (1 - ek),
              Art.spark);
        }
      }
    }

    _paintSnake(canvas, t);
    canvas.restore();
  }

  void _paintSnake(Canvas canvas, double t) {
    final body = game.body.toList();
    final prev = game.previous;
    // Mientras juega, cada trozo va de su casilla de antes a la nueva; al
    // acabar se queda quieta donde choco.
    final k = game.status == HebiStatus.playing && !reduced ? game.progress : 1.0;
    final points = <Offset>[
      for (var i = 0; i < body.length; i++)
        Offset.lerp(_center(i < prev.length ? prev[i] : prev.last), _center(body[i]), k)!,
    ];
    if (game.isOver) {
      // Al chocar se pinta donde estaba, no a medio camino.
      for (var i = 0; i < points.length && i < prev.length; i++) {
        points[i] = _center(prev[i]);
      }
    }

    final overK = fx.overAt < 0 ? 0.0 : ((t - fx.overAt) / HebiFx.overTime).clamp(0.0, 1.0);
    Color tone(Color c) => Color.lerp(c, const Color(0xFFB7C2CC), overK * .75)!;
    final base = tone(HebiColors.body);

    final path = Path()..moveTo(points.last.dx, points.last.dy);
    for (var i = points.length - 2; i >= 0; i--) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;
    final w = cell * .78;
    canvas.drawPath(path.shift(Offset(0, cell * .08)), stroke(T.dusk.withValues(alpha: .12), w));
    canvas.drawPath(path, stroke(Art.deep(base, .35), w));
    canvas.drawPath(path, stroke(base, w - math.max(2, cell * .1)));
    // La tripa clara por el centro y el brillo del lacado arriba.
    canvas.drawPath(path, stroke(tone(HebiColors.belly).withValues(alpha: .55), w * .28));
    canvas.drawPath(
      path.shift(Offset(-cell * .1, -cell * .14)),
      stroke(const Color(0x66FFFFFF), w * .16),
    );
    // Lunares cada tres trozos, como un juguete de tela.
    final spot = Paint()..color = tone(HebiColors.spot);
    for (var i = 3; i < points.length; i += 3) {
      canvas.drawCircle(points[i], cell * .1, spot);
    }

    _paintHead(canvas, points.first, base, overK);
  }

  void _paintHead(Canvas canvas, Offset c, Color base, double overK) {
    final r = cell * .48;
    final head = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    paintPlastic(canvas, head, base, edge: math.max(1, cell * .06), shine: .9);

    final d = game.dir;
    final fwd = Offset(d.dx.toDouble(), d.dy.toDouble());
    final side = Offset(-fwd.dy, fwd.dx);
    final ink = Paint()..color = Art.brush;
    final shine = Paint()..color = T.shellTop;
    final over = game.isOver;
    for (final s in [-1.0, 1.0]) {
      final e = c + fwd * r * .22 + side * r * .42 * s;
      if (over) {
        // Ojos en aspa: se ha dado un golpe.
        final x = r * .16;
        final p = stroke(Art.brush, math.max(1.2, cell * .06));
        canvas.drawLine(e.translate(-x, -x), e.translate(x, x), p);
        canvas.drawLine(e.translate(-x, x), e.translate(x, -x), p);
      } else {
        canvas.drawCircle(e, r * .2, ink);
        canvas.drawCircle(e.translate(-r * .06, -r * .07), r * .07, shine);
      }
      final blush = c - fwd * r * .1 + side * r * .62 * s;
      canvas.drawOval(
        Rect.fromCenter(center: blush, width: r * .34, height: r * .2),
        Paint()..color = T.tamaBlush.withValues(alpha: .55 * (1 - overK * .6)),
      );
    }
    // La lengua, que asoma de vez en cuando.
    final tongue = !over && !reduced && (clock.value * 1.3) % 2 < .18;
    if (tongue) {
      final tip = c + fwd * r * 1.25;
      canvas.drawLine(c + fwd * r * .8, tip, stroke(Art.awningRed, math.max(1, cell * .05)));
      canvas.drawLine(tip, tip + (fwd + side) * r * .14, stroke(Art.awningRed, math.max(1, cell * .04)));
      canvas.drawLine(tip, tip + (fwd - side) * r * .14, stroke(Art.awningRed, math.max(1, cell * .04)));
    }
  }

  Paint stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = c;

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.game != game || old.cell != cell || old.accent != accent || old.surfaces != surfaces || old.reduced != reduced;
}
