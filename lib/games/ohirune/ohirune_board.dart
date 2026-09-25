// Ibasho — el tablero de Ohirune: zonas de color, X y Tamas dormidos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../../backend/messaging.dart';
import '../../backend/tama.dart';
import '../../theme/tokens.dart';
import '../../ui/tama/tama_painter.dart';
import '../../ui/tama/tama_sticker.dart';
import 'ohirune.dart';

/// Los efectos en curso, con la hora (segundos del reloj de efectos) a la
/// que empieza cada uno. Igual que en el buscaminas: el tablero no anima
/// nada solo, el canal apunta aquí y mueve el reloj.
class OhiruneFx {
  /// Casilla → cuando se durmió su Tama.
  final Map<int, double> placed = <int, double>{};

  /// Casilla → cuando se falló en ella.
  final Map<int, double> misses = <int, double>{};

  /// El último fallo que rompía alguna regla: cuándo, qué casillas se
  /// encienden en rojo (fila, columna, zona o vecinas) y qué Tamas tienen la
  /// culpa.
  double? clashAt;
  Set<int> clashArea = const <int>{};
  Set<int> culprits = const <int>{};

  /// Cuando se despiertan todos a celebrarlo.
  double? winAt;

  double busyUntil = 0;

  void clear() {
    placed.clear();
    misses.clear();
    clashAt = null;
    clashArea = const <int>{};
    culprits = const <int>{};
    winAt = null;
    busyUntil = 0;
  }

  void touch(double until) => busyUntil = math.max(busyUntil, until);

  static const double placeTime = .45;
  static const double missTime = .6;
  static const double clashTime = 1.3;
  static const double winTime = 2.6;
}

/// El color de cada zona: el del cuerpo de su Tama. Si se parece mucho al de
/// una zona anterior, se aclara u oscurece hasta distinguirse (como la tinta
/// de Tamakoro).
List<Color> ohiruneZoneColors(List<Tama> tamas) {
  final out = <Color>[];
  for (var i = 0; i < tamas.length; i++) {
    var color = tamas[i].look.bodyColor;
    for (var tries = 0; tries < 4 && out.any((c) => _close(c, color)); tries++) {
      color = tries.isEven ? Color.lerp(color, T.dusk, .3)! : Color.lerp(color, T.shellTop, .45)!;
    }
    out.add(color);
  }
  return out;
}

bool _close(Color a, Color b) {
  final dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db) < 56;
}

/// El tablero. Tocar pone un Tama (o quita la X que haya); el clic derecho,
/// o tocar con [crossMode], pone y quita X, y arrastrando se marcan varias
/// casillas seguidas.
class OhiruneBoard extends StatefulWidget {
  const OhiruneBoard({
    super.key,
    required this.game,
    required this.cellSize,
    required this.zones,
    required this.looks,
    required this.fx,
    required this.clock,
    required this.crossMode,
    required this.onPlace,
    required this.onCross,
  });

  final OhiruneGame game;
  final double cellSize;

  /// Color de cada zona.
  final List<Color> zones;

  /// El Tama que duerme en cada zona.
  final List<TamaLook> looks;

  final OhiruneFx fx;
  final ValueNotifier<double> clock;
  final bool crossMode;
  final void Function(int x, int y) onPlace;

  /// Poner ([on]) o quitar una X.
  final void Function(int x, int y, bool on) onCross;

  @override
  State<OhiruneBoard> createState() => _OhiruneBoardState();
}

class _OhiruneBoardState extends State<OhiruneBoard> {
  final ValueNotifier<int?> _hover = ValueNotifier<int?>(null);

  /// Arrastrando X: si pone o quita, y la ultima casilla tocada.
  bool? _paintOn;
  int? _last;

  /// Un toque que aun no ha soltado el dedo, en modo Tama.
  int? _pendingTap;

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  int get _n => widget.game.size;

  int? _cellAt(Offset local) {
    final x = (local.dx / widget.cellSize).floor();
    final y = (local.dy / widget.cellSize).floor();
    if (x < 0 || y < 0 || x >= _n || y >= _n) return null;
    return y * _n + x;
  }

  void _down(PointerDownEvent e) {
    final cell = _cellAt(e.localPosition);
    if (cell == null || widget.game.isOver) return;
    final secondary = e.kind == PointerDeviceKind.mouse && e.buttons & kSecondaryMouseButton != 0;
    if (secondary || widget.crossMode) {
      final mark = widget.game.marks[cell];
      if (mark == OhiruneMark.tama || widget.game.misses.contains(cell)) return;
      _paintOn = mark != OhiruneMark.cross;
      _last = cell;
      widget.onCross(cell % _n, cell ~/ _n, _paintOn!);
    } else {
      _pendingTap = cell;
    }
  }

  void _move(PointerMoveEvent e) {
    final cell = _cellAt(e.localPosition);
    if (_paintOn != null) {
      if (cell == null || cell == _last) return;
      _last = cell;
      if (widget.game.marks[cell] == OhiruneMark.tama || widget.game.misses.contains(cell)) return;
      if ((widget.game.marks[cell] == OhiruneMark.cross) == _paintOn) return;
      widget.onCross(cell % _n, cell ~/ _n, _paintOn!);
    } else if (_pendingTap != null && cell != _pendingTap) {
      _pendingTap = null;
    }
  }

  void _up(PointerUpEvent e) {
    final cell = _pendingTap;
    _pendingTap = null;
    _paintOn = null;
    _last = null;
    if (cell == null || _cellAt(e.localPosition) != cell) return;
    final x = cell % _n, y = cell ~/ _n;
    // Una X protege la casilla: el primer toque solo la quita.
    if (widget.game.misses.contains(cell)) return;
    if (widget.game.marks[cell] == OhiruneMark.cross) {
      widget.onCross(x, y, false);
    } else {
      widget.onPlace(x, y);
    }
  }

  void _cancel(PointerCancelEvent e) {
    _pendingTap = null;
    _paintOn = null;
    _last = null;
  }

  @override
  Widget build(BuildContext context) {
    final side = _n * widget.cellSize;
    return MouseRegion(
      cursor: widget.game.isOver ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onHover: (e) => _hover.value = _cellAt(e.localPosition),
      onExit: (_) => _hover.value = null,
      child: Listener(
        key: const ValueKey<String>('ohirune.board'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        child: SizedBox(
          width: side,
          height: side,
          child: CustomPaint(
            painter: _BoardPainter(
              game: widget.game,
              zones: widget.zones,
              looks: widget.looks,
              fx: widget.fx,
              clock: widget.clock,
              hover: _hover,
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.game,
    required this.zones,
    required this.looks,
    required this.fx,
    required this.clock,
    required this.hover,
  }) : super(repaint: Listenable.merge([clock, hover]));

  final OhiruneGame game;
  final List<Color> zones;
  final List<TamaLook> looks;
  final OhiruneFx fx;
  final ValueNotifier<double> clock;
  final ValueNotifier<int?> hover;

  static final TamaPose _sleep = poseForFace(StickerFace.sleepy);
  static final TamaPose _awake = poseForFace(StickerFace.happy);

  @override
  void paint(Canvas canvas, Size size) {
    final n = game.size;
    final u = size.width / n;
    final now = clock.value;
    final puzzle = game.puzzle;
    final outer = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * .22));

    canvas.save();
    canvas.clipRRect(outer);
    // Las casillas: plastico del color de su zona, con un reflejo arriba.
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final i = y * n + x;
        final base = Color.lerp(zones[puzzle.regions[i]], T.shellTop, .5)!;
        final r = Rect.fromLTWH(x * u, y * u, u, u);
        canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.lerp(base, T.shellTop, .35)!, base, Color.lerp(base, T.dusk, .06)!],
              stops: const [0, .5, 1],
            ).createShader(r),
        );
        if (hover.value == i && !game.isOver && game.marks[i] != OhiruneMark.tama) {
          canvas.drawRect(r, Paint()..color = T.shellTop.withValues(alpha: .4));
        }
        final miss = fx.misses[i];
        if (miss != null && now >= miss && now < miss + OhiruneFx.missTime) {
          final t = (now - miss) / OhiruneFx.missTime;
          canvas.drawRect(r, Paint()..color = T.wrong.withValues(alpha: .55 * (1 - t)));
        }
      }
    }

    // La regla rota: la fila, la columna, la zona o las vecinas laten en
    // rojo dos veces y se apagan; el Tama con el que choca, con un aro.
    final clash = fx.clashAt;
    if (clash != null && now >= clash && now < clash + OhiruneFx.clashTime) {
      final t = (now - clash) / OhiruneFx.clashTime;
      final pulse = math.pow(math.sin(t * math.pi * 2).abs(), .7) * (1 - t * .6);
      final wash = Paint()..color = T.wrong.withValues(alpha: .5 * pulse);
      for (final i in fx.clashArea) {
        canvas.drawRect(Rect.fromLTWH((i % n) * u, (i ~/ n) * u, u, u), wash);
      }
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.4, u * .07)
        ..color = Color.lerp(T.wrong, T.dusk, .1)!.withValues(alpha: pulse.toDouble().clamp(0, 1));
      for (final i in fx.culprits) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH((i % n) * u, (i ~/ n) * u, u, u).deflate(u * .08), Radius.circular(u * .2)),
          ring,
        );
      }
    }

    // Lineas finas dentro de cada zona, y fronteras gruesas entre zonas.
    final thin = Paint()
      ..color = T.dusk.withValues(alpha: .1)
      ..strokeWidth = math.max(1, u * .02);
    final thick = Paint()
      ..color = T.dusk.withValues(alpha: .62)
      ..strokeWidth = math.max(2.2, u * .075)
      ..strokeCap = StrokeCap.round;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final here = puzzle.regionAt(x, y);
        if (x < n - 1) {
          final line = (Offset((x + 1) * u, y * u), Offset((x + 1) * u, (y + 1) * u));
          canvas.drawLine(line.$1, line.$2, puzzle.regionAt(x + 1, y) == here ? thin : thick);
        }
        if (y < n - 1) {
          final line = (Offset(x * u, (y + 1) * u), Offset((x + 1) * u, (y + 1) * u));
          canvas.drawLine(line.$1, line.$2, puzzle.regionAt(x, y + 1) == here ? thin : thick);
        }
      }
    }

    // Las marcas.
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final i = y * n + x;
        final c = Offset((x + .5) * u, (y + .5) * u);
        switch (game.marks[i]) {
          case OhiruneMark.none:
            break;
          case OhiruneMark.cross:
            final miss = fx.misses[i];
            var k = 1.0;
            var dx = 0.0;
            if (miss != null && now >= miss && now < miss + OhiruneFx.missTime) {
              final t = (now - miss) / OhiruneFx.missTime;
              dx = math.sin(t * 40) * (1 - t) * u * .08;
              k = Curves.easeOutBack.transform(math.min(1, t * 2.5));
            }
            final locked = game.misses.contains(i);
            final color = Color.lerp(zones[puzzle.regions[i]], T.dusk, .5)!;
            final ink = Paint()
              ..color = locked ? Color.lerp(T.wrong, T.dusk, .15)! : color.withValues(alpha: .8)
              ..strokeWidth = u * .085
              ..strokeCap = StrokeCap.round;
            final d = u * .15 * k;
            canvas.drawLine(c + Offset(-d + dx, -d), c + Offset(d + dx, d), ink);
            canvas.drawLine(c + Offset(d + dx, -d), c + Offset(-d + dx, d), ink);
          case OhiruneMark.tama:
            _tama(canvas, x, y, u, now);
        }
      }
    }
    canvas.restore();

    canvas.drawRRect(
      outer.deflate(math.max(1.1, u * .04)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.2, u * .08)
        ..color = T.dusk.withValues(alpha: .62),
    );
  }

  void _tama(Canvas canvas, int x, int y, double u, double now) {
    final i = y * game.size + x;
    final at = fx.placed[i];
    var scale = 1.0;
    if (at != null && now < at + OhiruneFx.placeTime) {
      scale = now < at ? 0 : Curves.easeOutBack.transform((now - at) / OhiruneFx.placeTime);
    }
    final win = fx.winAt;
    var pose = _sleep;
    var hop = 0.0;
    if (win != null) {
      final t = now - win - (x + y) * .07;
      if (t >= 0) {
        pose = _awake;
        if (t < 1.6) hop = math.max(0, math.sin(t * math.pi * 2.5)) * u * .12 * (1 - t / 1.6);
      }
    }
    if (scale <= 0) return;
    final box = u * 1.02;
    canvas.save();
    canvas.translate((x + .5) * u, (y + .54) * u - hop);
    canvas.scale(scale);
    canvas.translate(-box / 2, -box / 2);
    TamaPainter(look: looks[game.puzzle.regions[i]], pose: pose, shadow: true).paint(canvas, Size.square(box));
    canvas.restore();
  }

  @override
  // Las marcas cambian dentro de la misma partida: cada reconstruccion
  // repinta. Entre medias, lo mueven el reloj y el raton.
  bool shouldRepaint(_BoardPainter old) => true;
}
