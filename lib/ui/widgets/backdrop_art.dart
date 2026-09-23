// Ibasho — el dibujo de los fondos del gacha: colores y temas a pantalla
// completa para el menu de inicio.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Como en `channel_art.dart` y `gacha_art.dart`, cada fondo tiene sus propios
// colores: no siguen al acento (docs/UI.md §4), para que se vean igual en
// cualquier cuenta. La escalera de rareza es la de docs/CREAR_PREMIOS.md §5:
// N un color, R dos y un detalle, SR con textura, SSR con destello, UR con
// algo vivo y ∞ animado.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/backdrops.dart';
import '../../backend/gacha.dart';
import '../../theme/skin.dart';
import 'channel_art.dart' show paintTwinkle;

/// El fondo puesto por la cuenta, a pantalla completa. [id] es el de
/// [Backdrop] (sin el prefijo `bg_`); vacio o desconocido no pinta nada y
/// deja el aspecto de siempre.
class BackdropView extends StatefulWidget {
  const BackdropView({super.key, this.id});

  final String? id;

  @override
  State<BackdropView> createState() => _BackdropViewState();
}

class _BackdropViewState extends State<BackdropView>
    with SingleTickerProviderStateMixin {
  // Una vuelta lenta y larga: con 70 estrellas y fases repartidas no hace
  // falta que sea mas corta para que parpadeen todo el rato, y asi la deriva
  // horizontal es casi imperceptible salvo mirando un buen rato.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 90),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BackdropView old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _sync();
  }

  void _sync() {
    final animate =
        widget.id == 'starfield' && !IbashoSkin.of(context).reducedMotion;
    if (animate) {
      if (!_drift.isAnimating) _drift.repeat();
    } else {
      _drift.stop();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    if (id == null || backdropById(id) == null) return const SizedBox.shrink();

    if (id == 'starfield') {
      return IgnorePointer(
        child: AnimatedBuilder(
          animation: _drift,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: _StarfieldPainter(_drift.value),
          ),
        ),
      );
    }
    return IgnorePointer(
      child: CustomPaint(size: Size.infinite, painter: _BackdropPainter(id)),
    );
  }
}

/// La paleta de un fondo: arriba, centro y (opcional) abajo del degradado.
class _Palette {
  const _Palette(this.top, this.base, [Color? deep]) : deep = deep ?? base;

  final Color top;
  final Color base;
  final Color deep;

  List<Color> get stops => top == deep ? [top, base] : [top, base, deep];
}

const Map<String, _Palette> _palettes = <String, _Palette>{
  // --- N: un color, en degradado suave. ---
  'sky': _Palette(Color(0xFFDFF6FF), Color(0xFF7FD4F5)),
  'coral': _Palette(Color(0xFFFFE7DE), Color(0xFFFF9C86)),
  'mint': _Palette(Color(0xFFE7FBF1), Color(0xFF7FE0B8)),
  'peach': _Palette(Color(0xFFFFF1DD), Color(0xFFFFC58A)),
  // --- R: dos colores y un detalle. ---
  'lavender': _Palette(Color(0xFFF3E9FF), Color(0xFFC8A8F2)),
  'dusk': _Palette(Color(0xFF32407A), Color(0xFF141935)),
  'sunrise': _Palette(Color(0xFFFFDCA3), Color(0xFFFF8FA6)),
  'lagoon': _Palette(Color(0xFFCBF2EC), Color(0xFF3FADC4)),
  // --- SR: mas elaborado, con textura de cristal. ---
  'aurora': _Palette(Color(0xFFD3F8EA), Color(0xFF7FD6F2)),
  'candy': _Palette(Color(0xFFFFE1F0), Color(0xFFCBA6F5)),
  'forest': _Palette(Color(0xFFE3F2C9), Color(0xFF3E8F5C)),
  // --- SSR: un destello blanco de cuatro puntas. ---
  'sunset': _Palette(Color(0xFFFFD37A), Color(0xFFF0578C), Color(0xFF5E3AA0)),
  'glacier': _Palette(Color(0xFFEBFBFF), Color(0xFF7FD1F2), Color(0xFF3E6FA8)),
  // --- UR: halo vivo y destellos de color. ---
  'phoenix': _Palette(Color(0xFFFFD37A), Color(0xFFF0577A), Color(0xFF6E1E3C)),
  'borealis': _Palette(Color(0xFF163049), Color(0xFF1E6E5C), Color(0xFF3C1E6E)),
};

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.id);

  final String id;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rarity = backdropById(id)?.rarity ?? Rarity.n;
    final palette =
        _palettes[id] ?? const _Palette(Color(0xFFEEF2F6), Color(0xFFDDE7EF));

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: palette.stops,
        ).createShader(rect),
    );

    if (rarity == Rarity.n) return;
    _detail(canvas, rect, id, palette);

    if (rarity.index < Rarity.sr.index) return;
    _glassSheen(canvas, rect);

    if (rarity.index < Rarity.ssr.index) return;
    final points = rarity == Rarity.ur ? 5 : 3;
    for (var i = 0; i < points; i++) {
      final dx = rect.width * (.16 + i * .68 / math.max(1, points - 1));
      final dy = rect.height * (.14 + (i.isOdd ? .5 : 0) * .18);
      paintTwinkle(
        canvas,
        Offset(dx, dy),
        rect.shortestSide * .028,
        const Color(0xEEFFFFFF),
      );
    }

    if (rarity != Rarity.ur) return;
    _halo(canvas, rect, palette.base);
  }

  /// El detalle de R en adelante: una forma con vida propia por tema, no solo
  /// el degradado.
  void _detail(Canvas canvas, Rect rect, String id, _Palette palette) {
    switch (id) {
      case 'lavender':
      case 'candy':
        _bokeh(canvas, rect, palette.deep);
      case 'dusk':
      case 'borealis':
        _moon(canvas, rect);
      case 'sunrise':
      case 'phoenix':
      case 'sunset':
        _horizonGlow(canvas, rect, palette.top);
      case 'lagoon':
      case 'aurora':
        _waves(canvas, rect, palette.deep);
      case 'forest':
        _lightShafts(canvas, rect);
      case 'glacier':
        _facets(canvas, rect);
    }
  }

  void _moon(Canvas canvas, Rect rect) {
    final c = Offset(rect.width * .78, rect.height * .22);
    final r = rect.shortestSide * .09;
    canvas.drawCircle(
      c,
      r * 2.4,
      Paint()
        ..color = const Color(0x33FFF6D6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFFFFF6D6));
  }

  void _bokeh(Canvas canvas, Rect rect, Color tint) {
    final spots = <(double, double, double)>[
      (.18, .74, .07),
      (.62, .18, .05),
      (.84, .62, .09),
      (.36, .40, .045),
    ];
    for (final (fx, fy, fr) in spots) {
      canvas.drawCircle(
        Offset(rect.width * fx, rect.height * fy),
        rect.shortestSide * fr,
        Paint()
          ..color = const Color(0x59FFFFFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _horizonGlow(Canvas canvas, Rect rect, Color glow) {
    final band = Rect.fromLTWH(
      0,
      rect.height * .48,
      rect.width,
      rect.height * .3,
    );
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            glow.withValues(alpha: .55),
            glow.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
  }

  void _waves(Canvas canvas, Rect rect, Color tint) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = rect.shortestSide * .012
      ..color = tint.withValues(alpha: .35);
    for (var i = 0; i < 3; i++) {
      final y = rect.height * (.72 + i * .08);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= rect.width; x += rect.width / 6) {
        path.quadraticBezierTo(
          x + rect.width / 12,
          y + (i.isEven ? -10 : 10),
          x + rect.width / 6,
          y,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  void _lightShafts(Canvas canvas, Rect rect) {
    final paint = Paint()..color = const Color(0x33FFFDE8);
    for (final fx in <double>[.2, .5, .78]) {
      final top = Offset(rect.width * fx, 0);
      final path = Path()
        ..moveTo(top.dx - rect.width * .04, top.dy)
        ..lineTo(top.dx + rect.width * .04, top.dy)
        ..lineTo(top.dx + rect.width * .14, rect.height)
        ..lineTo(top.dx - rect.width * .14, rect.height)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _facets(Canvas canvas, Rect rect) {
    final paint = Paint()..color = const Color(0x40FFFFFF);
    final spots = <(double, double, double)>[
      (.22, .3, .12),
      (.7, .58, .16),
      (.5, .16, .09),
    ];
    for (final (fx, fy, fs) in spots) {
      final c = Offset(rect.width * fx, rect.height * fy);
      final s = rect.shortestSide * fs;
      final path = Path()
        ..moveTo(c.dx, c.dy - s)
        ..lineTo(c.dx + s * .8, c.dy)
        ..lineTo(c.dx, c.dy + s)
        ..lineTo(c.dx - s * .8, c.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _glassSheen(Canvas canvas, Rect rect) {
    canvas.save();
    canvas.clipRect(rect);
    final band = Rect.fromLTWH(
      -rect.width * .2,
      0,
      rect.width * .5,
      rect.height,
    );
    canvas.save();
    canvas.translate(rect.width * .55, 0);
    canvas.skew(-.5, 0);
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[
            Color(0x00FFFFFF),
            Color(0x30FFFFFF),
            Color(0x00FFFFFF),
          ],
        ).createShader(band),
    );
    canvas.restore();
    canvas.restore();
  }

  void _halo(Canvas canvas, Rect rect, Color color) {
    final c = Offset(rect.width * .5, rect.height * .38);
    canvas.drawCircle(
      c,
      rect.shortestSide * .42,
      Paint()
        ..color = color.withValues(alpha: .28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.id != id;
}

/// Las estrellas de la unica ∞: posicion, tamano y fase, fijas de por vida
/// (una semilla propia) para que no salten al reconstruir el widget.
class _Star {
  const _Star(this.dx, this.dy, this.size, this.phase, this.speed);

  final double dx;
  final double dy;
  final double size;
  final double phase;
  final double speed;
}

final List<_Star> _stars = List<_Star>.generate(70, (i) {
  final random = math.Random(1000 + i);
  return _Star(
    random.nextDouble(),
    random.nextDouble(),
    random.nextBool() ? 1.1 : 1.9,
    random.nextDouble() * math.pi * 2,
    .5 + random.nextDouble() * 1.3,
  );
});

/// El cielo estrellado de la ∞: parpadeo suave y aleatorio por estrella (no
/// todas a la vez), una deriva lenta y, de cuando en cuando, una fugaz.
class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter(this.t);

  /// De 0 a 1, en bucle.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF0B1533), Color(0xFF1C2C5C)],
        ).createShader(rect),
    );

    final drift = t * math.pi * 2;
    for (final star in _stars) {
      final twinkle =
          .3 + .7 * (.5 + .5 * math.sin(drift * star.speed + star.phase));
      final dx = (star.dx + t * .02) % 1.0;
      canvas.drawCircle(
        Offset(dx * size.width, star.dy * size.height),
        star.size,
        Paint()..color = Color.fromRGBO(255, 255, 255, twinkle.clamp(0.0, 1.0)),
      );
    }

    // Una estrella fugaz de cuando en cuando: un tramo corto del bucle.
    const shootStart = .62, shootSpan = .1;
    if (t >= shootStart && t < shootStart + shootSpan) {
      final p = (t - shootStart) / shootSpan;
      final start = Offset(size.width * .12, size.height * .16);
      final end = Offset(size.width * .5, size.height * .46);
      final pos = Offset.lerp(start, end, p)!;
      final fade = math.sin(p * math.pi).clamp(0.0, 1.0);
      canvas.drawLine(
        pos,
        pos - const Offset(30, -16),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, .85 * fade)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => old.t != t;
}
