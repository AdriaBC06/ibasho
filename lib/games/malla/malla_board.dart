// Malla — el tablero: hexágonos de plástico, aristas y la conquista.
// Copyright (C) 2026 Julio Solano
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../theme/menu_theme.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../ui/widgets/channel_art.dart';
import 'malla_game.dart';

/// El tablero de una partida.
///
/// Los hexágonos libres son huecos hundidos; uno conquistado es una ficha de
/// plástico del color de quien lo ganó, que salta al ponerse. Las aristas
/// libres van en punteado, las jugadas son varillas de color y los vértices,
/// clavijas blancas. Dentro de un hexágono a medias, un punto por arista de
/// cada jugador dice cuánto le falta a cada uno.
class MallaBoardView extends StatefulWidget {
  const MallaBoardView({
    super.key,
    required this.game,
    required this.colors,
    required this.enabled,
    required this.onEdge,
    this.hintKey = '',
    this.captured = const <int>{},
  });

  final MallaGame game;
  final List<Color> colors;
  final bool enabled;
  final ValueChanged<String> onEdge;
  final String hintKey;
  final Set<int> captured;

  @override
  State<MallaBoardView> createState() => _MallaBoardViewState();
}

class _MallaBoardViewState extends State<MallaBoardView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  String _hoverKey = '';

  @override
  void didUpdateWidget(MallaBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.captured.isNotEmpty && !identical(widget.captured, oldWidget.captured)) {
      if (IbashoSkin.of(context).reducedMotion) {
        _pulse.value = 1;
      } else {
        _pulse.forward(from: 0);
      }
    }
    if (!widget.enabled && _hoverKey.isNotEmpty) _hoverKey = '';
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry = _MallaGeometry(widget.game, size);
        void hit(Offset local, PointerDeviceKind? kind) {
          if (!widget.enabled) return;
          final key = geometry.nearestEdge(local, pointer: kind, onlyFree: true);
          if (key != null) widget.onEdge(key);
        }

        return MouseRegion(
          cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onHover: widget.enabled
              ? (event) {
                  final key = geometry.nearestEdge(event.localPosition, pointer: PointerDeviceKind.mouse, onlyFree: true) ?? '';
                  if (_hoverKey != key) setState(() => _hoverKey = key);
                }
              : null,
          onExit: (_) {
            if (_hoverKey.isNotEmpty) setState(() => _hoverKey = '');
          },
          child: Listener(
            key: const ValueKey<String>('malla.board'),
            behavior: HitTestBehavior.opaque,
            onPointerUp: (event) => hit(event.localPosition, event.kind),
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _MallaPainter(
                  game: widget.game,
                  moves: widget.game.moves.length,
                  geometry: geometry,
                  colors: widget.colors,
                  accent: skin.accent,
                  surfaces: skin.surfaces,
                  hintKey: widget.hintKey,
                  hoverKey: _hoverKey,
                  captured: widget.captured,
                  pulse: _pulse,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MallaGeometry {
  _MallaGeometry(this.game, this.size) {
    final points = <MallaPoint>[for (final hex in game.hexes) ...hex.vertices];
    var minX = points.first.x;
    var maxX = points.first.x;
    var minY = points.first.y;
    var maxY = points.first.y;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    const padding = 14.0;
    final rawW = math.max(1.0, maxX - minX);
    final rawH = math.max(1.0, maxY - minY);
    scale = math
        .min((size.width - padding * 2) / rawW, (size.height - padding * 2) / rawH)
        .clamp(.05, 20.0)
        .toDouble();
    final drawW = rawW * scale;
    final drawH = rawH * scale;
    origin = Offset((size.width - drawW) / 2 - minX * scale, (size.height - drawH) / 2 - minY * scale);
  }

  final MallaGame game;
  final Size size;
  late final double scale;
  late final Offset origin;

  Offset map(MallaPoint point) => Offset(origin.dx + point.x * scale, origin.dy + point.y * scale);

  Offset center(MallaHex hex) => Offset(origin.dx + hex.cx * scale, origin.dy + hex.cy * scale);

  /// Lo que mide una arista en pantalla.
  double get side => MallaGame.cellRadius * scale;

  String? nearestEdge(Offset p, {PointerDeviceKind? pointer, required bool onlyFree}) {
    final threshold = switch (pointer) {
      PointerDeviceKind.touch => math.max(16.0, side * .4),
      PointerDeviceKind.stylus => 13.0,
      _ => math.max(10.0, side * .3),
    };
    MallaEdge? best;
    MallaEdge? second;
    var bestD = double.infinity;
    var secondD = double.infinity;
    for (final edge in game.edges.values) {
      if (onlyFree && edge.owner != null) continue;
      final d = _segmentDistance(p, map(edge.p), map(edge.q));
      if (d < bestD) {
        second = best;
        secondD = bestD;
        best = edge;
        bestD = d;
      } else if (d < secondD) {
        second = edge;
        secondD = d;
      }
    }
    if (best == null || bestD > threshold) return null;
    if (second != null && secondD - bestD < 2.2 && bestD < 4) return null;
    return best.key;
  }

  static double _segmentDistance(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2).clamp(0.0, 1.0).toDouble();
    return (p - Offset(a.dx + dx * t, a.dy + dy * t)).distance;
  }
}

class _MallaPainter extends CustomPainter {
  _MallaPainter({
    required this.game,
    required this.moves,
    required this.geometry,
    required this.colors,
    required this.accent,
    required this.surfaces,
    required this.hintKey,
    required this.hoverKey,
    required this.captured,
    required this.pulse,
  }) : super(repaint: pulse);

  final MallaGame game;

  /// Cuántas jugadas había al pintar: la partida cambia por dentro.
  final int moves;
  final _MallaGeometry geometry;
  final List<Color> colors;
  final Color accent;
  final Surfaces surfaces;
  final String hintKey;
  final String hoverKey;
  final Set<int> captured;
  final Animation<double> pulse;

  Color _color(int seat) => colors.isEmpty ? accent : colors[seat % colors.length];

  Path _hexPath(MallaHex hex, double shrink) {
    final c = geometry.center(hex);
    final path = Path();
    for (var k = 0; k < hex.vertices.length; k++) {
      final p = c + (geometry.map(hex.vertices[k]) - c) * shrink;
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = geometry.side;
    final t = pulse.value.clamp(0.0, 1.0).toDouble();
    final pop = pulse.isAnimating ? Curves.elasticOut.transform(t) : 1.0;

    // Los hexágonos: huecos hundidos o fichas de plástico.
    for (var i = 0; i < game.hexes.length; i++) {
      final hex = game.hexes[i];
      final owner = hex.owner;
      if (owner == null) {
        final well = _hexPath(hex, .94);
        final r = well.getBounds();
        canvas.drawPath(
          well,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [surfaces.wellTop, surfaces.wellBottom],
            ).createShader(r),
        );
        canvas.drawPath(
          well,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = surfaces.hairline,
        );
      } else {
        final grow = captured.contains(i) ? pop : 1.0;
        final c = geometry.center(hex);
        paintGroundShadow(canvas, c.translate(0, side * .78), side * 1.3 * grow, .14);
        paintPlastic(canvas, _hexPath(hex, .9 * grow), _color(owner), edge: math.max(1.2, side * .05), shine: .9);
      }
    }

    // Puntos de cada jugador dentro de los hexágonos a medias.
    final dot = (side * .07).clamp(2.0, 4.5);
    for (final hex in game.hexes) {
      if (hex.owner != null || hex.drawnSides == 0) continue;
      final pips = <Color>[
        for (var p = 0; p < hex.sidesByPlayer.length; p++)
          for (var n = 0; n < hex.sidesByPlayer[p]; n++) _color(p),
      ];
      final c = geometry.center(hex);
      final step = dot * 2.6;
      final from = c.dx - step * (pips.length - 1) / 2;
      for (var k = 0; k < pips.length; k++) {
        final at = Offset(from + step * k, c.dy);
        canvas.drawCircle(at, dot + .8, Paint()..color = Art.deep(pips[k], .35));
        canvas.drawCircle(at, dot, Paint()..color = pips[k]);
      }
    }

    // Las aristas.
    final stick = (side * .13).clamp(3.0, 8.0);
    final last = game.lastMoveKey;
    for (final edge in game.edges.values) {
      final a = geometry.map(edge.p);
      final b = geometry.map(edge.q);
      final owner = edge.owner;
      if (owner != null) {
        final color = _color(owner);
        if (edge.key == last) {
          canvas.drawLine(a, b, _line(color.withValues(alpha: .35), stick * 2.6));
        }
        canvas.drawLine(a, b, _line(Art.deep(color, .35), stick + 2));
        canvas.drawLine(a, b, _line(color, stick));
        canvas.drawLine(a, b, _line(T.glintMid, stick * .3));
      } else if (edge.key == hintKey) {
        canvas.drawLine(a, b, _line(accent.withValues(alpha: .3), stick * 2.8));
        canvas.drawLine(a, b, _line(accent, stick));
      } else if (edge.key == hoverKey) {
        canvas.drawLine(a, b, _line(accent.withValues(alpha: .25), stick * 2.2));
        canvas.drawLine(a, b, _line(accent, stick * .8));
      } else {
        _dashed(canvas, a, b, _line(surfaces.inkSoft.withValues(alpha: .42), math.max(1.6, stick * .4)),
            dash: math.max(2.0, side * .08), gap: math.max(4.0, side * .14));
      }
    }

    // Las clavijas de los vértices.
    final peg = (side * .075).clamp(2.0, 4.0);
    final seen = <String>{};
    for (final edge in game.edges.values) {
      for (final point in [edge.p, edge.q]) {
        if (!seen.add(point.wireKey)) continue;
        final at = geometry.map(point);
        canvas.drawCircle(at, peg + 1, Paint()..color = surfaces.hairline);
        canvas.drawCircle(at, peg, Paint()..color = surfaces.shellTop);
      }
    }
  }

  static Paint _line(Color color, double width) => Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, {required double dash, required double gap}) {
    final delta = b - a;
    final length = delta.distance;
    if (length == 0) return;
    final unit = delta / length;
    var travelled = gap / 2;
    while (travelled < length) {
      final end = math.min(length, travelled + dash);
      canvas.drawLine(a + unit * travelled, a + unit * end, paint);
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_MallaPainter old) =>
      old.game != game ||
      old.moves != moves ||
      old.geometry.size != geometry.size ||
      old.hintKey != hintKey ||
      old.hoverKey != hoverKey ||
      old.colors != colors ||
      old.accent != accent ||
      old.surfaces != surfaces ||
      old.captured != captured;
}
