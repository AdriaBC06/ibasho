// Ibasho — el adorno del tema detras de los canales.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// En el menu el tema se ve entero por el fondo; dentro de un canal solo queda
// el plastico. Desde SR el tema deja ahi un rastro de su fondo, siempre por
// debajo del contenido y muy suave: un reflejo de cristal (SR), destellos en
// las esquinas (SSR), una luz que respira (UR) y un cielo vivo (∞).
// Solo UR e ∞ se mueven, y nunca con movimiento reducido.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../theme/menu_theme.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import 'channel_art.dart' show paintTwinkle;

class ThemeOrnament extends StatefulWidget {
  const ThemeOrnament({super.key});

  @override
  State<ThemeOrnament> createState() => _ThemeOrnamentState();
}

class _ThemeOrnamentState extends State<ThemeOrnament>
    with SingleTickerProviderStateMixin {
  // Una vuelta larga: los ritmos de dentro son multiplos enteros de ella, asi
  // que el bucle no da saltos.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final skin = IbashoSkin.of(context);
    final alive = skin.surfaces.ornament.index >= Ornament.aura.index &&
        !skin.reducedMotion;
    if (alive) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaces = IbashoSkin.of(context).surfaces;
    if (surfaces.ornament == Ornament.none) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _OrnamentPainter(surfaces, _loop),
        ),
      ),
    );
  }
}

/// Las estrellas de la ∞ dentro de los canales: fijas y pequenas.
final List<(double, double, double)> _stars =
    List<(double, double, double)>.generate(42, (i) {
  final random = math.Random(2000 + i);
  return (random.nextDouble(), random.nextDouble(), random.nextDouble());
});

/// Las fugaces de la ∞ en los canales: cuando salen en el bucle, de donde y
/// hacia donde (fracciones del canal).
const List<(double, Offset, Offset)> _comets = <(double, Offset, Offset)>[
  (.2, Offset(.1, .1), Offset(.4, .35)),
  (.55, Offset(.9, .15), Offset(.62, .4)),
  (.85, Offset(.3, .6), Offset(.6, .85)),
];

class _OrnamentPainter extends CustomPainter {
  _OrnamentPainter(this.surfaces, this.loop) : super(repaint: loop);

  final Surfaces surfaces;
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final level = surfaces.ornament.index;
    final t = loop.value * math.pi * 2;
    canvas.save();
    canvas.clipRect(rect);

    // UR: una luz del tema arriba y otra abajo, que respiran a destiempo.
    if (level >= Ornament.aura.index) {
      final breath = .5 + .5 * math.sin(t * 6);
      _glow(
        canvas,
        Offset(size.width * .5, -size.height * .1),
        size.longestSide * (.46 + .04 * breath),
        surfaces.glow.withValues(alpha: .16 + .08 * breath),
      );
      _glow(
        canvas,
        Offset(size.width * .92, size.height * 1.05),
        size.longestSide * .34,
        surfaces.glowAlt.withValues(alpha: .12 + .06 * (1 - breath)),
      );
    }

    // SR: un reflejo de cristal en diagonal, ancho y tenue.
    if (level >= Ornament.sheen.index) {
      final band = Rect.fromLTWH(0, 0, size.width * .34, size.height);
      canvas.save();
      canvas.translate(size.width * .58, 0);
      canvas.skew(-.45, 0);
      canvas.drawRect(
        band,
        Paint()
          ..shader = LinearGradient(
            colors: <Color>[
              T.glintNone,
              Color.lerp(T.glintMid, surfaces.glow.withValues(alpha: .25), .3)!
                  .withValues(alpha: surfaces.dark ? .1 : .25),
              T.glintNone,
            ],
          ).createShader(band),
      );
      canvas.restore();
    }

    // ∞: un cielo dentro del canal, siempre por debajo del contenido: dos
    // nebulosas que giran despacio, estrellas que titilan y cruzan (las
    // cercanas mas deprisa) y alguna fugaz.
    if (level >= Ornament.stars.index) {
      for (var i = 0; i < 2; i++) {
        final a = t + i * math.pi;
        _glow(
          canvas,
          Offset(
            size.width * (i == 0 ? .2 : .8) + math.cos(a) * size.width * .05,
            size.height * (i == 0 ? .7 : .3) + math.sin(a) * size.height * .05,
          ),
          size.longestSide * .4,
          (i == 0 ? surfaces.glowAlt : surfaces.glow)
              .withValues(alpha: .1 + .05 * math.sin(t * 4 + i * 2)),
        );
      }
      // Sobre plastico claro una estrella blanca no se ve: ahi van en la luz
      // del tema, algo oscurecida.
      final ink = surfaces.dark
          ? Color.lerp(surfaces.glow, T.shellTop, .55)!
          : Color.lerp(surfaces.glow, T.dusk, .3)!;
      for (var i = 0; i < _stars.length; i++) {
        final (fx, fy, phase) = _stars[i];
        final k = 3 + (phase * 5).floor();
        final twinkle = .5 + .5 * math.sin(t * k + phase * math.pi * 2);
        final layer = i % 3;
        final c = Offset(((fx + loop.value * layer) % 1) * size.width, fy * size.height);
        final color = ink.withValues(alpha: .2 + .5 * twinkle);
        if (phase > .8) {
          _glow(canvas, c, 12, surfaces.glow.withValues(alpha: .25 * twinkle));
          paintTwinkle(canvas, c, 4 + 3 * twinkle, color);
        } else {
          canvas.drawCircle(c, phase > .5 ? 2.2 : 1.4, Paint()..color = color);
        }
      }
      for (final (start, from, to) in _comets) {
        final p = (loop.value - start) / .03;
        if (p < 0 || p >= 1) continue;
        final a = Offset(from.dx * size.width, from.dy * size.height);
        final b = Offset(to.dx * size.width, to.dy * size.height);
        final head = Offset.lerp(a, b, p)!;
        final tail = head - (b - a) / (b - a).distance * 90;
        final fade = math.sin(p * math.pi);
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(tail, head, <Color>[
              ink.withValues(alpha: 0),
              ink.withValues(alpha: .8 * fade),
            ]),
        );
      }
    }

    // SSR: tres destellos en las esquinas de abajo, donde no estorban (arriba
    // estan el titulo y el boton de cerrar). Desde UR laten despacio.
    if (level >= Ornament.sparkle.index) {
      final alive = level >= Ornament.aura.index;
      final spots = <(double, double, double)>[
        (.968, .9, 14),
        (.93, .955, 8),
        (.03, .94, 11),
      ];
      for (var i = 0; i < spots.length; i++) {
        final (fx, fy, r) = spots[i];
        final pulse = alive ? .75 + .25 * math.sin(t * 5 + i * 2.1) : 1.0;
        final c = Offset(size.width * fx, size.height * fy);
        _glow(canvas, c, r * 2.8, surfaces.glow.withValues(alpha: .34 * pulse));
        paintTwinkle(
          canvas,
          c,
          r * pulse,
          Color.lerp(T.shellTop, surfaces.glow, .7)!,
        );
      }
    }
    canvas.restore();
  }

  /// Una luz redonda que se apaga hacia fuera. Degradado, no desenfoque: se
  /// repinta en cada fotograma de UR y asi sale barato.
  void _glow(Canvas canvas, Offset c, double r, Color color) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_OrnamentPainter old) =>
      old.surfaces != surfaces || old.loop != loop;
}

/// El filo de luz de la ∞ en las pantallas de cristal del menu: un cometa
/// que da la vuelta al marco, con la luz del tema, cada doce segundos. Con
/// movimiento reducido el filo se queda quieto.
class StarRim extends StatefulWidget {
  const StarRim({super.key, required this.radius});

  final double radius;

  @override
  State<StarRim> createState() => _StarRimState();
}

class _StarRimState extends State<StarRim> with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (IbashoSkin.of(context).reducedMotion) {
      _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RimPainter(
          widget.radius,
          IbashoSkin.of(context).surfaces,
          _loop,
        ),
      ),
    ),
  );
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.radius, this.surfaces, this.loop) : super(repaint: loop);

  final double radius;
  final Surfaces surfaces;
  final Animation<double> loop;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius)).deflate(1);
    final turn = loop.value * math.pi * 2;
    final glow = surfaces.glow, alt = surfaces.glowAlt;
    // Dos cometas opuestos, uno de cada luz del tema, y entre ellos el filo
    // casi apagado.
    final shader = SweepGradient(
      colors: <Color>[
        glow.withValues(alpha: 0),
        glow.withValues(alpha: .95),
        T.shellTop,
        alt.withValues(alpha: 0),
        alt.withValues(alpha: .8),
        T.shellTop.withValues(alpha: .9),
        glow.withValues(alpha: 0),
      ],
      stops: const <double>[0, .2, .23, .5, .7, .73, 1],
      transform: GradientRotation(turn),
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..shader = shader,
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.surfaces != surfaces || old.loop != loop;
}
