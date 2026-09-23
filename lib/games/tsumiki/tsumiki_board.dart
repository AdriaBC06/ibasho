// Ibasho — el tablero de Tsumiki: bloques de plastico lacado, pieza
// fantasma, estela al soltar, destello de filas y la torre que se apaga.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../theme/menu_theme.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/channel_art.dart';
import 'tsumiki.dart';

/// Color de cada pieza. Son de la ilustracion, no del acento: se ven igual
/// con cualquier tema, como las piezas de un juguete.
Color pieceColor(TsumikiPiece p) => switch (p) {
      TsumikiPiece.i => Art.blockI,
      TsumikiPiece.o => Art.blockO,
      TsumikiPiece.t => Art.blockT,
      TsumikiPiece.s => Art.blockS,
      TsumikiPiece.z => Art.blockZ,
      TsumikiPiece.j => Art.blockJ,
      TsumikiPiece.l => Art.blockL,
    };

/// Tiempos de los efectos, en el reloj de efectos del canal.
class TsumikiFx {
  static const double dropTime = .28;
  static const double lockTime = .22;
  static const double overTime = 1.1;
  static const double shakeTime = .4;

  /// Estela de la ultima pieza soltada de golpe: columnas, fila de salida y
  /// de llegada, color y cuando.
  (List<int> cols, int from, int to, Color color, double at)? drop;

  /// Casillas recien asentadas y cuando.
  List<int> locked = const <int>[];
  double lockedAt = -9;

  double shakeAt = -9;
  double shakePower = 0;
  double overAt = -1;

  double busyUntil = 0;

  void touch(double until) => busyUntil = math.max(busyUntil, until);

  void clear() {
    drop = null;
    locked = const <int>[];
    lockedAt = -9;
    shakeAt = -9;
    overAt = -1;
    busyUntil = 0;
  }
}

/// Un bloque: cuadradito redondeado de plastico con brillo arriba. Se graba
/// una vez por color y tamaño y luego se estampa.
class BlockStamp {
  BlockStamp._();

  static final Map<(int, int), ui.Picture> _cache = <(int, int), ui.Picture>{};

  static void paint(Canvas canvas, Rect r, Color color) {
    final key = (color.toARGB32(), (r.width * 4).round());
    final pic = _cache.putIfAbsent(key, () {
      final rec = ui.PictureRecorder();
      _draw(Canvas(rec), r.width, color);
      return rec.endRecording();
    });
    canvas.save();
    canvas.translate(r.left, r.top);
    canvas.drawPicture(pic);
    canvas.restore();
  }

  static void _draw(Canvas canvas, double s, Color color) {
    final inset = s * .05;
    final body = Rect.fromLTWH(inset, inset, s - inset * 2, s - inset * 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(s * .2)));
    paintPlastic(canvas, path, color, edge: math.max(1, s * .06), shine: .9);
    // Un botoncito en el centro, como las piezas de un juguete de bloques.
    final c = body.center;
    canvas.drawCircle(c, s * .17, Paint()..color = Art.light(color, .2));
    canvas.drawCircle(
      c.translate(-s * .04, -s * .05),
      s * .06,
      Paint()..color = const Color(0x99FFFFFF),
    );
  }
}

class TsumikiBoard extends StatelessWidget {
  const TsumikiBoard({
    super.key,
    required this.game,
    required this.cellSize,
    required this.fx,
    required this.clock,
    required this.accent,
    this.worried = false,
  });

  final TsumikiGame game;
  final double cellSize;
  final TsumikiFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final bool worried;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          size: Size(TsumikiGame.width * cellSize, TsumikiGame.visibleRows * cellSize),
          painter: _BoardPainter(game, cellSize, fx, clock, accent, worried, IbashoSkin.of(context).surfaces),
        ),
      );
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.game, this.cell, this.fx, this.clock, this.accent, this.worried, this.surfaces) : super(repaint: clock);

  final Surfaces surfaces;

  final TsumikiGame game;
  final double cell;
  final TsumikiFx fx;
  final ValueNotifier<double> clock;
  final Color accent;
  final bool worried;

  Rect _rect(int x, int y) =>
      Rect.fromLTWH(x * cell, (y - TsumikiGame.hiddenRows) * cell, cell, cell);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final full = Offset.zero & size;

    // Sacudida: con cuatro filas o al acabar.
    final since = t - fx.shakeAt;
    if (since >= 0 && since < TsumikiFx.shakeTime) {
      final k = 1 - since / TsumikiFx.shakeTime;
      canvas.translate(0, math.sin(since * 60) * fx.shakePower * k);
    }

    // El pozo: cristal hundido con la rejilla muy tenue.
    canvas.drawRRect(
      RRect.fromRectAndRadius(full, Radius.circular(cell * .3)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(surfaces.shellTop, accent, .06)!, Color.lerp(surfaces.shellBottom, accent, .16)!],
        ).createShader(full),
    );
    final grid = Paint()
      ..color = accent.withValues(alpha: .1)
      ..strokeWidth = 1;
    for (var x = 1; x < TsumikiGame.width; x++) {
      canvas.drawLine(Offset(x * cell, 0), Offset(x * cell, size.height), grid);
    }
    for (var y = 1; y < TsumikiGame.visibleRows; y++) {
      canvas.drawLine(Offset(0, y * cell), Offset(size.width, y * cell), grid);
    }

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(full, Radius.circular(cell * .3)));

    // Estela de la ultima pieza soltada.
    final drop = fx.drop;
    if (drop != null) {
      final k = (t - drop.$5) / TsumikiFx.dropTime;
      if (k >= 0 && k < 1) {
        for (final x in drop.$1) {
          final top = (drop.$2 - TsumikiGame.hiddenRows) * cell;
          final bottom = (drop.$3 - TsumikiGame.hiddenRows + 1) * cell;
          final r = Rect.fromLTRB(x * cell + cell * .2, top, x * cell + cell * .8, bottom);
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(cell * .3)),
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [drop.$4.withValues(alpha: 0), drop.$4.withValues(alpha: .45 * (1 - k))],
              ).createShader(r),
          );
        }
      }
    }

    // Lo asentado. Al acabar se apaga fila a fila desde abajo.
    final overK = fx.overAt < 0 ? -1.0 : ((t - fx.overAt) / TsumikiFx.overTime).clamp(0.0, 1.0);
    final clearing = game.clearing.toSet();
    final clearK = game.clearProgress;
    for (var y = TsumikiGame.hiddenRows; y < TsumikiGame.rows; y++) {
      final fromBottom = (TsumikiGame.rows - 1 - y) / TsumikiGame.visibleRows;
      final stone = overK >= 0 && fromBottom <= overK;
      for (var x = 0; x < TsumikiGame.width; x++) {
        final p = game.at(x, y);
        if (p == null) continue;
        var r = _rect(x, y);
        var color = stone ? Color.lerp(pieceColor(p), Ty.inkSoft, .72)! : pieceColor(p);
        if (clearing.contains(y)) {
          // Se hinchan, se vuelven blancas y se encogen hacia el centro.
          final grow = clearK < .35 ? 1 + clearK * .3 : math.max(0.0, 1.1 - (clearK - .35) / .65 * 1.1);
          r = Rect.fromCenter(center: r.center, width: r.width * grow, height: r.height * grow);
          color = Color.lerp(color, T.shellTop, math.min(1, clearK * 2.2))!;
          if (r.width < 1) continue;
        }
        BlockStamp.paint(canvas, r, color);
      }
    }

    // Destellos donde se va una fila.
    if (clearing.isNotEmpty && clearK > .25) {
      final k = (clearK - .25) / .75;
      for (final y in clearing) {
        final cy = (y - TsumikiGame.hiddenRows + .5) * cell;
        canvas.drawRect(
          Rect.fromLTRB(0, cy - cell * .5 * (1 - k), size.width, cy + cell * .5 * (1 - k)),
          Paint()..color = T.shellTop.withValues(alpha: .7 * (1 - k)),
        );
        for (var i = 0; i < 5; i++) {
          final dx = (i + .5) / 5 * size.width + math.sin(y * 7.0 + i) * cell * .6;
          paintTwinkle(canvas, Offset(dx, cy - k * cell * 1.2), cell * .45 * (1 - k * .6), Art.spark.withValues(alpha: 1 - k));
        }
      }
    }

    // Brillo de lo recien asentado.
    final lk = (t - fx.lockedAt) / TsumikiFx.lockTime;
    if (lk >= 0 && lk < 1) {
      final glow = Paint()..color = T.shellTop.withValues(alpha: .55 * (1 - lk));
      for (final i in fx.locked) {
        final y = i ~/ TsumikiGame.width;
        if (y < TsumikiGame.hiddenRows || clearing.contains(y)) continue;
        canvas.drawRRect(RRect.fromRectAndRadius(_rect(i % TsumikiGame.width, y), Radius.circular(cell * .2)), glow);
      }
    }

    // Fantasma y pieza que cae.
    final p = game.current;
    if (p != null && !game.isOver) {
      final ghost = game.ghost!;
      final color = pieceColor(p.type);
      if (ghost.y != p.y) {
        final line = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, cell * .08)
          ..color = color.withValues(alpha: .6);
        final fill = Paint()..color = color.withValues(alpha: .14);
        for (final (x, y) in ghost.cells) {
          if (y < TsumikiGame.hiddenRows) continue;
          final r = RRect.fromRectAndRadius(_rect(x, y).deflate(cell * .1), Radius.circular(cell * .18));
          canvas.drawRRect(r, fill);
          canvas.drawRRect(r, line);
        }
      }
      for (final (x, y) in p.cells) {
        if (y < TsumikiGame.hiddenRows) continue;
        BlockStamp.paint(canvas, _rect(x, y), color);
      }
      _paintEyes(canvas, p, t);
    }
    canvas.restore();
  }

  /// La pieza que cae tiene ojos: miran hacia abajo, parpadean de vez en
  /// cuando y se asustan si la torre esta muy alta.
  void _paintEyes(Canvas canvas, FallingPiece p, double t) {
    final cells = p.cells.where((c) => c.$2 >= TsumikiGame.hiddenRows).toList();
    if (cells.isEmpty || cell < 14) return;
    // La casilla de arriba del todo, y de ellas la mas centrada.
    cells.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : (a.$1 - 4.5).abs().compareTo((b.$1 - 4.5).abs()));
    final r = _rect(cells.first.$1, cells.first.$2);
    final blink = (t % 3.4) > 3.25;
    final ink = Paint()..color = Ty.ink.withValues(alpha: .85);
    for (final dx in [-.18, .18]) {
      final c = r.center + Offset(dx * cell, worried ? -cell * .02 : cell * .04);
      if (blink) {
        canvas.drawLine(c.translate(-cell * .06, 0), c.translate(cell * .06, 0), ink..strokeWidth = cell * .05);
      } else {
        canvas.drawOval(Rect.fromCenter(center: c, width: cell * .12, height: cell * (worried ? .2 : .16)), ink);
        canvas.drawCircle(c.translate(-cell * .02, -cell * .03), cell * .025, Paint()..color = T.shellTop);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

/// Una pieza sola, centrada en su caja: para la siguiente y la guardada.
class PiecePreview extends StatelessWidget {
  const PiecePreview({super.key, required this.piece, this.size = 56, this.muted = false});

  final TsumikiPiece? piece;
  final double size;
  final bool muted;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size * .66,
        child: piece == null ? null : CustomPaint(painter: _PreviewPainter(piece!, muted)),
      );
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter(this.piece, this.muted);

  final TsumikiPiece piece;
  final bool muted;

  @override
  void paint(Canvas canvas, Size size) {
    final cells = shapeOf(piece, 0);
    final minX = cells.map((c) => c.$1).reduce(math.min);
    final maxX = cells.map((c) => c.$1).reduce(math.max);
    final minY = cells.map((c) => c.$2).reduce(math.min);
    final maxY = cells.map((c) => c.$2).reduce(math.max);
    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    final s = math.min(size.width / 4.4, size.height / 2.4);
    final origin = Offset((size.width - w * s) / 2, (size.height - h * s) / 2);
    final color = muted ? Color.lerp(pieceColor(piece), Ty.inkSoft, .6)! : pieceColor(piece);
    for (final (x, y) in cells) {
      BlockStamp.paint(canvas, Rect.fromLTWH(origin.dx + (x - minX) * s, origin.dy + (y - minY) * s, s, s), color);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.piece != piece || old.muted != muted;
}
