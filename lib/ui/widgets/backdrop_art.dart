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
import 'dart:ui' as ui;

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
    // De SR en adelante el fondo se mueve, muy despacio: el cristal, las
    // luces y los destellos. R y N se quedan quietos.
    final rarity = backdropById(widget.id)?.rarity;
    final animate = rarity != null &&
        rarity.index >= Rarity.sr.index &&
        !IbashoSkin.of(context).reducedMotion;
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
          builder: (context, _) => RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: _StarfieldPainter(_drift.value),
            ),
          ),
        ),
      );
    }
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _BackdropPainter(id, _drift),
      ),
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
  _BackdropPainter(this.id, this.loop) : super(repaint: loop);

  final String id;

  /// La vuelta de 90 s. Todo ritmo de dentro es un multiplo entero de ella
  /// para que el bucle no de saltos. Quieta (0) en N, R y con movimiento
  /// reducido.
  final Animation<double> loop;

  /// Una onda de [cycles] vueltas por bucle, de -1 a 1.
  double _wave(int cycles, [double phase = 0]) =>
      math.sin(loop.value * math.pi * 2 * cycles + phase);

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
    if (rarity == Rarity.ur) _halo(canvas, rect, palette.base);
    final points = rarity == Rarity.ur ? 5 : 3;
    for (var i = 0; i < points; i++) {
      final dx = rect.width * (.16 + i * .68 / math.max(1, points - 1));
      final dy = rect.height * (.14 + (i.isOdd ? .5 : 0) * .18);
      // Cada destello late a su ritmo, nunca todos a la vez.
      final pulse = .78 + .22 * _wave(9 + i * 2, i * 1.7);
      paintTwinkle(
        canvas,
        Offset(dx, dy),
        rect.shortestSide * .028 * pulse,
        const Color(0xEEFFFFFF),
      );
    }
  }

  /// El detalle de R en adelante: una forma con vida propia por tema, no solo
  /// el degradado.
  void _detail(Canvas canvas, Rect rect, String id, _Palette palette) {
    switch (id) {
      case 'lavender':
      case 'candy':
        _bokeh(canvas, rect, palette.deep);
      case 'dusk':
        _moon(canvas, rect);
      case 'borealis':
        _curtains(canvas, rect);
        _moon(canvas, rect);
      case 'sunrise':
      case 'sunset':
        _horizonGlow(canvas, rect, palette.top);
      case 'phoenix':
        _horizonGlow(canvas, rect, palette.top);
        _embers(canvas, rect);
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
    for (var i = 0; i < spots.length; i++) {
      final (fx, fy, fr) = spots[i];
      // Flotan arriba y abajo, cada una a su ritmo.
      final float = _wave(3 + i, i * 1.3) * rect.height * .02;
      canvas.drawCircle(
        Offset(rect.width * fx, rect.height * fy + float),
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
            glow.withValues(alpha: .5 + .08 * _wave(4)),
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
    final step = rect.width / 6;
    for (var i = 0; i < 3; i++) {
      final y = rect.height * (.72 + i * .08);
      // Corren de lado un tramo entero por vuelta, cada fila a su paso: con
      // un tramo de margen a la izquierda el bucle no se nota.
      final shift = (loop.value * (i + 2) % 1) * step;
      final path = Path()..moveTo(shift - step, y);
      for (var x = shift - step; x <= rect.width; x += step) {
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
    const light = Color(0x33FFFDE8);
    final shafts = <double>[.2, .5, .78];
    for (var i = 0; i < shafts.length; i++) {
      final fx = shafts[i];
      // La luz entre las hojas va y viene.
      final paint = Paint()
        ..color = light.withValues(alpha: light.a * (.75 + .35 * _wave(5 + i, i * 2.0)));
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
    final spots = <(double, double, double)>[
      (.22, .3, .12),
      (.7, .58, .16),
      (.5, .16, .09),
    ];
    for (var i = 0; i < spots.length; i++) {
      final (fx, fy, fs) = spots[i];
      // Las caras del hielo cogen la luz por turnos.
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, .2 + .1 * _wave(6 + i, i * 2.1));
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
    canvas.translate(rect.width * (.55 + .06 * _wave(2)), 0);
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
    final breath = .5 + .5 * _wave(6);
    canvas.drawCircle(
      c,
      rect.shortestSide * (.4 + .04 * breath),
      Paint()
        ..color = color.withValues(alpha: .22 + .1 * breath)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
  }

  /// Las cortinas de la aurora boreal: tres cintas de luz que ondulan.
  void _curtains(Canvas canvas, Rect rect) {
    const colors = <Color>[
      Color(0xFF5FF0B0),
      Color(0xFF7FD6F2),
      Color(0xFFA07CF0),
    ];
    for (var i = 0; i < colors.length; i++) {
      final top = rect.height * (.1 + i * .07);
      final depth = rect.height * (.26 + i * .04);
      final path = Path();
      const steps = 24;
      final edge = <Offset>[];
      for (var s = 0; s <= steps; s++) {
        final fx = s / steps;
        final sway = math.sin(fx * math.pi * (2 + i) + loop.value * math.pi * 2 * (2 + i) + i);
        edge.add(Offset(rect.width * fx, top + sway * rect.height * .035));
      }
      path.moveTo(edge.first.dx, edge.first.dy);
      for (final p in edge.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      for (final p in edge.reversed) {
        path.lineTo(p.dx, p.dy + depth);
      }
      path.close();
      final band = Rect.fromLTWH(0, top - rect.height * .04, rect.width, depth + rect.height * .08);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              colors[i].withValues(alpha: 0),
              colors[i].withValues(alpha: .34 + .1 * _wave(3 + i, i * 1.9)),
              colors[i].withValues(alpha: 0),
            ],
            stops: const <double>[0, .3, 1],
          ).createShader(band),
      );
    }
  }

  /// Las brasas del fenix: suben despacio desde abajo, oscilan y se apagan.
  void _embers(Canvas canvas, Rect rect) {
    for (var i = 0; i < _emberSeeds.length; i++) {
      final (fx, phase, speed) = _emberSeeds[i];
      final p = (loop.value * speed + phase) % 1.0;
      final x = rect.width * fx + math.sin(p * math.pi * 4 + i) * rect.width * .02;
      final y = rect.height * (1.02 - p * .7);
      final fade = math.sin(p * math.pi);
      final r = rect.shortestSide * (.006 + .004 * (i % 3));
      canvas.drawCircle(
        Offset(x, y),
        r * 2.6,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[
              Color.fromRGBO(255, 190, 90, .45 * fade),
              const Color(0x00FFBE5A),
            ],
          ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r * 2.6)),
      );
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Color.fromRGBO(255, 236, 190, .9 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.id != id || old.loop != loop;
}

/// Las brasas del fenix: posicion horizontal, fase y vueltas por bucle
/// (entero, para que el bucle no salte).
final List<(double, double, int)> _emberSeeds =
    List<(double, double, int)>.generate(16, (i) {
  final random = math.Random(3000 + i);
  return (random.nextDouble(), random.nextDouble(), 6 + random.nextInt(6));
});

/// Una estrella de la unica ∞: posicion, tamano, fase, vueltas de parpadeo
/// por bucle (entero, para que el bucle no salte) y capa de profundidad.
/// Fijas de por vida (semilla propia): no saltan al reconstruir el widget.
class _Star {
  const _Star(this.dx, this.dy, this.size, this.phase, this.cycles, this.layer);

  final double dx;
  final double dy;
  final double size;
  final double phase;
  final int cycles;

  /// 0 lejos (quieta), 1 media, 2 cerca: las cercanas cruzan el cielo mas
  /// deprisa y dan la sensacion de profundidad.
  final int layer;
}

final List<_Star> _stars = List<_Star>.generate(120, (i) {
  final random = math.Random(1000 + i);
  final layer = i < 70 ? 0 : (i < 104 ? 1 : 2);
  return _Star(
    random.nextDouble(),
    random.nextDouble(),
    const <double>[.8, 1.3, 2][layer] + random.nextDouble() * .5,
    random.nextDouble() * math.pi * 2,
    2 + random.nextInt(8),
    layer,
  );
});

/// El polvo de la via lactea: una banda diagonal de puntos muy finos.
final List<(double, double, double)> _dust =
    List<(double, double, double)>.generate(220, (i) {
  final random = math.Random(4000 + i);
  // Gauss aproximado: la banda es densa en el centro y se deshilacha.
  final across =
      (random.nextDouble() + random.nextDouble() + random.nextDouble() - 1.5) *
          .16;
  return (random.nextDouble(), across, random.nextDouble());
});

/// Las estrellas grandes de la ∞, con halo, cruz y un color propio.
const List<(double, double, Color)> _brightStars = <(double, double, Color)>[
  (.14, .2, Color(0xFFBFD4FF)),
  (.36, .09, Color(0xFFFFE6B8)),
  (.63, .24, Color(0xFFFFC8EC)),
  (.86, .13, Color(0xFFD8CCFF)),
  (.08, .62, Color(0xFFFFE6B8)),
  (.52, .55, Color(0xFFBFF0FF)),
  (.92, .7, Color(0xFFFFC8EC)),
  (.3, .84, Color(0xFFD8CCFF)),
];

/// Las fugaces de cada bucle: cuando empiezan (0–1), cuanto duran, de donde
/// salen y hacia donde van (fracciones de la pantalla).
const List<(double, double, Offset, Offset)> _shooting =
    <(double, double, Offset, Offset)>[
  (.08, .035, Offset(.18, .08), Offset(.46, .34)),
  (.31, .03, Offset(.78, .06), Offset(.52, .3)),
  (.55, .04, Offset(.1, .3), Offset(.44, .58)),
  (.74, .03, Offset(.66, .12), Offset(.94, .38)),
  (.9, .035, Offset(.4, .04), Offset(.7, .26)),
];

/// El cielo de la ∞, el fondo mas vistoso: nebulosas que respiran y giran
/// despacio, la via lactea en diagonal, estrellas en tres capas de
/// profundidad, grandes estrellas de color con halo y varias fugaces por
/// bucle. Todo ritmo es entero por bucle: la vuelta no salta.
class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter(this.t);

  /// De 0 a 1, en bucle.
  final double t;

  double _wave(int cycles, [double phase = 0]) =>
      math.sin(t * math.pi * 2 * cycles + phase);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final w = size.width, h = size.height;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF0B1533), Color(0xFF1C2C5C), Color(0xFF2E1F5E)],
          stops: <double>[0, .6, 1],
        ).createShader(rect),
    );

    // Nebulosas: tres nubes grandes que respiran a destiempo y dan una vuelta
    // lenta alrededor de su sitio.
    const nebulae = <(double, double, double, Color)>[
      (.24, .3, .5, Color(0xFF7A5CF0)),
      (.78, .22, .42, Color(0xFF4FA8F0)),
      (.62, .82, .55, Color(0xFFE05CB8)),
    ];
    for (var i = 0; i < nebulae.length; i++) {
      final (fx, fy, fr, color) = nebulae[i];
      final a = t * math.pi * 2 + i * 2.1;
      final c = Offset(
        w * fx + math.cos(a) * w * .03,
        h * fy + math.sin(a) * h * .03,
      );
      final breath = .5 + .5 * _wave(3 + i, i * 1.3);
      _cloud(canvas, c, size.longestSide * fr * (.92 + .08 * breath),
          color.withValues(alpha: .2 + .12 * breath));
    }

    // La via lactea: una banda de luz en diagonal y su polvo de estrellas.
    final bandFrom = Offset(0, h * .95), bandTo = Offset(w, h * .05);
    final along = bandTo - bandFrom;
    final normal = Offset(-along.dy, along.dx) / along.distance;
    canvas.save();
    canvas.translate(bandFrom.dx, bandFrom.dy);
    canvas.rotate(math.atan2(along.dy, along.dx));
    final band = Rect.fromLTWH(0, -h * .2, along.distance, h * .4);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            const Color(0x00B8C8FF),
            Color.fromRGBO(200, 210, 255, .1 + .03 * _wave(2)),
            const Color(0x00B8C8FF),
          ],
        ).createShader(band),
    );
    canvas.restore();
    final dust = Paint();
    for (final (fa, fn, phase) in _dust) {
      final p = bandFrom + along * fa + normal * (fn * h);
      final glint = .5 + .5 * _wave(2 + (phase * 5).floor(), phase * 6.3);
      dust.color = Color.fromRGBO(225, 232, 255, .18 + .3 * glint);
      canvas.drawCircle(p, .7 + phase * .5, dust);
    }

    // Tres capas: la lejana quieta, la media cruza el cielo una vez por
    // bucle y la cercana dos. `% 1` con vueltas enteras no salta.
    final star = Paint();
    for (final s in _stars) {
      final twinkle = .5 + .5 * _wave(s.cycles, s.phase);
      final dx = (s.dx + t * s.layer) % 1.0;
      final alpha = (.25 + .75 * twinkle) * const <double>[.7, .85, 1][s.layer];
      star.color = Color.fromRGBO(255, 255, 255, alpha);
      final c = Offset(dx * w, s.dy * h);
      canvas.drawCircle(c, s.size, star);
      if (s.layer == 2) {
        _cloud(canvas, c, s.size * 5, Color.fromRGBO(190, 205, 255, .22 * twinkle));
      }
    }

    // Las grandes, de color: halo, cruz que late y un punto blanco.
    for (var i = 0; i < _brightStars.length; i++) {
      final (fx, fy, color) = _brightStars[i];
      final c = Offset(w * fx, h * fy);
      final pulse = .6 + .4 * (.5 + .5 * _wave(5 + i, i * 1.7));
      final r = size.shortestSide * .02 * pulse;
      _cloud(canvas, c, r * 3.2, color.withValues(alpha: .38 * pulse));
      paintTwinkle(canvas, c, r, color.withValues(alpha: .95));
      canvas.drawCircle(c, 1.6, Paint()..color = const Color(0xFFFFFFFF));
    }

    // Las fugaces: una cabeza blanca y una cola que se apaga.
    for (final (start, span, from, to) in _shooting) {
      if (t < start || t >= start + span) continue;
      final p = (t - start) / span;
      final a = Offset(from.dx * w, from.dy * h);
      final b = Offset(to.dx * w, to.dy * h);
      final head = Offset.lerp(a, b, p)!;
      final dir = (b - a) / (b - a).distance;
      final tail = head - dir * size.shortestSide * .16;
      final fade = math.sin(p * math.pi);
      canvas.drawLine(
        tail,
        head,
        Paint()
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..shader = ui.Gradient.linear(tail, head, <Color>[
            const Color(0x00FFFFFF),
            Color.fromRGBO(255, 255, 255, .9 * fade),
          ]),
      );
      _cloud(canvas, head, 10, Color.fromRGBO(220, 230, 255, .7 * fade));
    }
  }

  /// Una luz redonda que se apaga hacia fuera (degradado, que se repinta en
  /// cada fotograma y el desenfoque saldria caro).
  void _cloud(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) => old.t != t;
}
