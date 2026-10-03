// Malla — tablero nativo, hitboxes y animación de conquista.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/type.dart';
import 'malla_game.dart';

/// Tablero ambiental del inicio, equivalente al tablero vivo de Malla Web.
/// No recibe entrada ni toca estadísticas: es solo una demostración del motor
/// canónico, y respeta la preferencia de movimiento reducido de Ibasho.
class MallaAmbientBoard extends StatefulWidget {
  const MallaAmbientBoard({
    super.key,
    required this.colors,
    required this.reducedMotion,
  });

  final List<Color> colors;
  final bool reducedMotion;

  @override
  State<MallaAmbientBoard> createState() => _MallaAmbientBoardState();
}

class _MallaAmbientBoardState extends State<MallaAmbientBoard> {
  final math.Random _random = math.Random();
  Timer? _timer;
  late MallaGame _game;

  @override
  void initState() {
    super.initState();
    _reset();
    _syncTimer();
  }

  @override
  void didUpdateWidget(MallaAmbientBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reducedMotion != widget.reducedMotion) _syncTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reset() {
    _game = MallaGame(
      size: 5,
      playerCount: 2,
      startSeat: _random.nextInt(2),
      chain: false,
    );
    for (var i = 0; i < 12; i++) {
      final free = _game.legalEdges;
      if (_game.finished || free.isEmpty) break;
      final edge = free[_random.nextInt(free.length)];
      _game.applyMove(edge.key, _game.currentPlayer);
    }
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (widget.reducedMotion) return;
    _timer = Timer.periodic(const Duration(milliseconds: 430), (_) => _step());
  }

  void _step() {
    if (!mounted) return;
    final free = _game.legalEdges;
    if (_game.finished || free.isEmpty) {
      _reset();
    } else {
      final edge = free[_random.nextInt(free.length)];
      _game.applyMove(edge.key, _game.currentPlayer);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: MallaBoardView(
      game: _game,
      markers: const <String>['A', 'B'],
      colors: widget.colors,
      enabled: false,
      onEdge: (_) {},
    ),
  );
}

class MallaBoardView extends StatefulWidget {
  const MallaBoardView({
    super.key,
    required this.game,
    required this.markers,
    required this.colors,
    required this.enabled,
    required this.onEdge,
    this.hintKey = '',
    this.captured = const <int>{},
  });

  final MallaGame game;
  final List<String> markers;
  final List<Color> colors;
  final bool enabled;
  final ValueChanged<String> onEdge;
  final String hintKey;
  final Set<int> captured;

  @override
  State<MallaBoardView> createState() => _MallaBoardViewState();
}

class _MallaBoardViewState extends State<MallaBoardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 430),
  );
  String _hoverKey = '';

  @override
  void didUpdateWidget(MallaBoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.captured.isNotEmpty &&
        (widget.game.moves.length != oldWidget.game.moves.length ||
            widget.captured.length != oldWidget.captured.length)) {
      _pulse.forward(from: 0);
    }
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
          final key = geometry.nearestEdge(
            local,
            pointer: kind,
            onlyFree: true,
          );
          if (key != null) widget.onEdge(key);
        }

        return MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onHover: widget.enabled
              ? (event) {
                  final key =
                      geometry.nearestEdge(
                        event.localPosition,
                        pointer: PointerDeviceKind.mouse,
                        onlyFree: true,
                      ) ??
                      '';
                  if (_hoverKey != key) setState(() => _hoverKey = key);
                }
              : null,
          onExit: (_) {
            if (_hoverKey.isNotEmpty) setState(() => _hoverKey = '');
          },
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerUp: (event) => hit(event.localPosition, event.kind),
            child: RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _MallaPainter(
                  game: widget.game,
                  geometry: geometry,
                  markers: widget.markers,
                  colors: widget.colors,
                  accent: skin.accent,
                  ink: skin.ink,
                  inkSoft: skin.inkSoft,
                  hairline: skin.hairline,
                  surface: skin.shellTop,
                  lastMoveKey: widget.game.lastMoveKey,
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
    const padding = 18.0;
    final rawW = math.max(1.0, maxX - minX);
    final rawH = math.max(1.0, maxY - minY);
    scale = math
        .min(
          (size.width - padding * 2) / rawW,
          (size.height - padding * 2) / rawH,
        )
        .clamp(.05, 20.0)
        .toDouble();
    final drawW = rawW * scale;
    final drawH = rawH * scale;
    origin = Offset(
      (size.width - drawW) / 2 - minX * scale,
      (size.height - drawH) / 2 - minY * scale,
    );
  }

  final MallaGame game;
  final Size size;
  late final double scale;
  late final Offset origin;

  Offset map(MallaPoint point) =>
      Offset(origin.dx + point.x * scale, origin.dy + point.y * scale);

  Offset center(MallaHex hex) =>
      Offset(origin.dx + hex.cx * scale, origin.dy + hex.cy * scale);

  String? nearestEdge(
    Offset p, {
    PointerDeviceKind? pointer,
    required bool onlyFree,
  }) {
    final threshold = switch (pointer) {
      PointerDeviceKind.touch => 16.0,
      PointerDeviceKind.stylus => 13.0,
      _ => 10.0,
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
    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2)
        .clamp(0.0, 1.0)
        .toDouble();
    final q = Offset(a.dx + dx * t, a.dy + dy * t);
    return (p - q).distance;
  }
}

class _MallaPainter extends CustomPainter {
  _MallaPainter({
    required this.game,
    required this.geometry,
    required this.markers,
    required this.colors,
    required this.accent,
    required this.ink,
    required this.inkSoft,
    required this.hairline,
    required this.surface,
    required this.lastMoveKey,
    required this.hintKey,
    required this.hoverKey,
    required this.captured,
    required this.pulse,
  }) : super(repaint: pulse);

  final MallaGame game;
  final _MallaGeometry geometry;
  final List<String> markers;
  final List<Color> colors;
  final Color accent;
  final Color ink;
  final Color inkSoft;
  final Color hairline;
  final Color surface;
  final String lastMoveKey;
  final String hintKey;
  final String hoverKey;
  final Set<int> captured;
  final Animation<double> pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutBack.transform(
      pulse.value.clamp(0.0, 1.0).toDouble(),
    );
    for (var i = 0; i < game.hexes.length; i++) {
      final hex = game.hexes[i];
      final path = Path();
      for (var k = 0; k < hex.vertices.length; k++) {
        final p = geometry.map(hex.vertices[k]);
        if (k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      final owner = hex.owner;
      if (owner != null) {
        final color = colors[owner % colors.length];
        final center = geometry.center(hex);
        canvas.save();
        if (captured.contains(i) && pulse.isAnimating) {
          final scale = .84 + .16 * t;
          canvas.translate(center.dx, center.dy);
          canvas.scale(scale);
          canvas.translate(-center.dx, -center.dy);
        }
        canvas.drawPath(path, Paint()..color = color.withValues(alpha: .20));
        canvas.restore();
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = hairline.withValues(alpha: .45),
      );
    }

    for (final edge in game.edges.values) {
      final a = geometry.map(edge.p);
      final b = geometry.map(edge.q);
      final owner = edge.owner;
      if (owner != null) {
        final last = edge.key == lastMoveKey;
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = colors[owner % colors.length]
            ..strokeWidth = last ? 7 : 5
            ..strokeCap = StrokeCap.round,
        );
      } else if (edge.key == hintKey) {
        canvas.drawLine(
          a,
          b,
          Paint()
            ..color = accent
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      } else {
        final hovered = edge.key == hoverKey;
        final paint = Paint()
          ..color = hovered ? ink : inkSoft.withValues(alpha: .52)
          ..strokeWidth = hovered ? 3 : 2.2
          ..strokeCap = StrokeCap.round;
        _dashed(canvas, a, b, paint, dash: hovered ? 1000 : 2.5, gap: 6);
      }
    }

    for (var i = 0; i < game.hexes.length; i++) {
      final hex = game.hexes[i];
      final center = geometry.center(hex);
      final owner = hex.owner;
      if (owner != null) {
        final marker = owner < markers.length ? markers[owner] : '${owner + 1}';
        _text(
          canvas,
          marker,
          center,
          math.max(13.0, 16 * geometry.scale / 1.7),
          ink,
          FontWeight.w700,
        );
      } else if (hex.drawnSides > 0) {
        final text = game.playerCount == 2
            ? '${hex.sidesByPlayer[0]}·${hex.sidesByPlayer[1]}'
            : '${hex.drawnSides}/6';
        _text(
          canvas,
          text,
          center,
          math.max(10.0, 12 * geometry.scale / 1.7),
          inkSoft,
          FontWeight.w500,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset center,
    double size,
    Color color,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: Ty.ui,
          fontFamilyFallback: const <String>[Ty.round],
          fontSize: size.clamp(10.0, 24.0).toDouble(),
          fontWeight: weight,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static void _dashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final delta = b - a;
    final length = delta.distance;
    if (length == 0) return;
    final unit = delta / length;
    if (dash >= length) {
      canvas.drawLine(a, b, paint);
      return;
    }
    var travelled = 0.0;
    while (travelled < length) {
      final end = math.min(length, travelled + dash);
      canvas.drawLine(a + unit * travelled, a + unit * end, paint);
      travelled += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_MallaPainter old) =>
      old.game != game ||
      old.lastMoveKey != lastMoveKey ||
      old.hintKey != hintKey ||
      old.hoverKey != hoverKey ||
      old.colors != colors ||
      old.markers != markers ||
      old.accent != accent ||
      old.ink != ink ||
      old.hairline != hairline ||
      old.captured != captured;
}
