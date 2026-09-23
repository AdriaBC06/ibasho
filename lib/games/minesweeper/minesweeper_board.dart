// Ibasho — el tablero del buscaminas: casillas de plastico y sus efectos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/menu_theme.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/channel_art.dart';
import 'minesweeper.dart';

/// Los efectos en curso del tablero, con la hora (en segundos del reloj de
/// efectos) a la que empieza cada uno.
///
/// El tablero no anima nada por su cuenta: el canal apunta aqui cuando pasa
/// algo y mueve el reloj mientras quede algun efecto por terminar. Con
/// movimiento reducido no se apunta nada y todo aparece en su estado final.
class BoardFx {
  /// Casilla (indice `y * ancho + x`) → cuando empieza a destaparse.
  final Map<int, double> reveal = <int, double>{};

  /// Casilla → cuando se clavo su bandera.
  final Map<int, double> flags = <int, double>{};

  /// La explosion: cuando y donde.
  double? boomAt;
  int? boomCell;

  /// La celebracion de la victoria.
  double? winAt;

  /// Hasta cuando hay algo moviendose.
  double busyUntil = 0;

  void clear() {
    reveal.clear();
    flags.clear();
    boomAt = null;
    boomCell = null;
    winAt = null;
    busyUntil = 0;
  }

  void touch(double until) => busyUntil = math.max(busyUntil, until);

  static const double revealTime = .26;
  static const double flagTime = .42;
  static const double boomTime = .9;
  static const double winTime = 3.2;

  /// Desplazamiento del tablero por la sacudida de la explosion.
  Offset shake(double now) {
    final at = boomAt;
    if (at == null) return Offset.zero;
    final t = now - at;
    if (t < 0 || t > .45) return Offset.zero;
    final k = (1 - t / .45) * 7;
    return Offset(math.sin(t * 71) * k, math.cos(t * 53) * k * .6);
  }
}

/// El tablero tactil. Pinta [game] con los efectos de [fx] a la hora que
/// marque [clock]; [hover] es la casilla bajo el raton.
class MinesweeperBoard extends StatelessWidget {
  const MinesweeperBoard({
    super.key,
    required this.game,
    required this.cellSize,
    required this.fx,
    required this.clock,
    required this.hover,
    required this.accent,
    required this.onCellTap,
    required this.onCellFlag,
  });

  final MinesweeperGame game;
  final double cellSize;
  final BoardFx fx;
  final ValueNotifier<double> clock;
  final ValueNotifier<int?> hover;
  final Color accent;
  final void Function(int x, int y) onCellTap;
  final void Function(int x, int y) onCellFlag;

  (int, int)? _cellAt(Offset local) {
    final x = (local.dx / cellSize).floor();
    final y = (local.dy / cellSize).floor();
    if (x < 0 || y < 0 || x >= game.width || y >= game.height) return null;
    return (x, y);
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(game.width * cellSize, game.height * cellSize);
    return MouseRegion(
      cursor: game.isOver ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onHover: (e) {
        final c = _cellAt(e.localPosition);
        hover.value = c == null ? null : c.$2 * game.width + c.$1;
      },
      onExit: (_) => hover.value = null,
      child: GestureDetector(
        key: const ValueKey<String>('minesweeper.board'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final cell = _cellAt(details.localPosition);
          if (cell != null) onCellTap(cell.$1, cell.$2);
        },
        onLongPressStart: (details) {
          final cell = _cellAt(details.localPosition);
          if (cell != null) onCellFlag(cell.$1, cell.$2);
        },
        onSecondaryTapUp: (details) {
          final cell = _cellAt(details.localPosition);
          if (cell != null) onCellFlag(cell.$1, cell.$2);
        },
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: CustomPaint(
            painter: _BoardPainter(
              surfaces: IbashoSkin.of(context).surfaces,
              game: game,
              fx: fx,
              clock: clock,
              hover: hover,
              accent: accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.surfaces,
    required this.game,
    required this.fx,
    required this.clock,
    required this.hover,
    required this.accent,
  }) : super(repaint: Listenable.merge([clock, hover]));

  final MinesweeperGame game;
  final BoardFx fx;
  final ValueNotifier<double> clock;
  final ValueNotifier<int?> hover;
  final Color accent;
  final Surfaces surfaces;

  /// Numeros ya maquetados, por numero y tamaño: maquetar texto en cada
  /// fotograma para 256 casillas se nota.
  static final Map<String, TextPainter> _numbers = <String, TextPainter>{};

  static TextPainter _number(int n, double unit) {
    final key = '$n@${unit.toStringAsFixed(1)}';
    return _numbers.putIfAbsent(key, () {
      if (_numbers.length > 256) _numbers.clear();
      return TextPainter(
        text: TextSpan(
          text: '$n',
          style: TextStyle(
            fontFamily: Ty.round,
            fontSize: unit * .58,
            fontWeight: FontWeight.w700,
            color: T.mineNumbers[(n - 1).clamp(0, 7)],
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  static double _ease(double t) => Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
  static double _back(double t) => Curves.easeOutBack.transform(t.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    if (game.width == 0 || game.height == 0) return;
    final now = clock.value;
    final unit = size.width / game.width;
    final gap = math.max(1.5, unit * .07);
    final radius = unit * .22;

    canvas.save();
    canvas.translate(fx.shake(now).dx, fx.shake(now).dy);

    final hovered = game.isOver ? null : hover.value;
    for (var y = 0; y < game.height; y++) {
      for (var x = 0; x < game.width; x++) {
        final i = y * game.width + x;
        final cell = game.cellAt(x, y);
        final rect = Rect.fromLTWH(x * unit + gap / 2, y * unit + gap / 2, unit - gap, unit - gap);
        final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
        final odd = (x + y).isOdd;

        final start = fx.reveal[i];
        final t = cell.revealed ? (start == null ? 1.0 : (now - start) / BoardFx.revealTime) : 0.0;

        if (!cell.revealed || t <= 0) {
          _raised(canvas, rrect, unit, odd, hovered == i && !cell.revealed);
          if (cell.flagged) _flag(canvas, rect, unit, i, now, wrong: false);
          if (game.status == MinesweeperStatus.ready && game.start == (x, y)) {
            _startMark(canvas, rrect, unit, now);
          }
          continue;
        }

        final exploded = game.losingX == x && game.losingY == y;
        _well(canvas, rrect, unit, odd, exploded);
        final show = _back((t - .35) / .65);
        if (cell.mine) {
          if (show > 0) {
            canvas.save();
            canvas.translate(rect.center.dx, rect.center.dy);
            canvas.scale(show);
            paintBomb(canvas, Offset.zero, unit * .25,
                spark: exploded ? 1 : 0, glow: exploded ? 1 : 0);
            canvas.restore();
          }
        } else if (cell.adjacent > 0 && show > 0) {
          final tp = _number(cell.adjacent, unit);
          canvas.save();
          canvas.translate(rect.center.dx, rect.center.dy);
          canvas.scale(show);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2 + unit * .02));
          canvas.restore();
        }
        if (cell.wrongFlag) _flag(canvas, rect, unit, i, now, wrong: true);
        // La tapa sale despedida: sube, encoge y se desvanece.
        if (t < 1) {
          final k = _ease(t);
          canvas.saveLayer(rect.inflate(unit), Paint()..color = Color.fromRGBO(0, 0, 0, 1 - k));
          canvas.translate(rect.center.dx, rect.center.dy - unit * .28 * k);
          canvas.scale(1 - .45 * k);
          canvas.translate(-rect.center.dx, -rect.center.dy);
          _raised(canvas, rrect, unit, odd, false);
          canvas.restore();
        }
      }
    }

    _boom(canvas, unit, now);
    canvas.restore();
    _confetti(canvas, size, now);
  }

  /// Casilla tapada: plastico con brillo, un punto tenida del acento.
  void _raised(Canvas canvas, RRect r, double unit, bool odd, bool hovered) {
    final lift = hovered ? unit * .04 : 0.0;
    final rr = r.shift(Offset(0, -lift));
    canvas.drawRRect(r.shift(Offset(0, unit * .05)), Paint()..color = T.shadowDeep);
    final top = Color.lerp(T.shellTop, accent, odd ? .10 : .05)!;
    final bottom = Color.lerp(surfaces.shellBottom, accent, odd ? .30 : .22)!;
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: hovered ? [T.shellTop, Color.lerp(bottom, T.shellTop, .45)!] : [top, bottom],
        ).createShader(rr.outerRect),
    );
    final hl = Rect.fromLTWH(rr.left + unit * .1, rr.top + unit * .06, rr.width - unit * .2, rr.height * .42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(hl, Radius.circular(hl.height / 2)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.glintStrong, T.glintNone],
        ).createShader(hl),
    );
    canvas.drawRRect(
      rr.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(surfaces.hairline, accent, .25)!,
    );
  }

  /// Casilla destapada: hueco claro con sombra por dentro, arriba.
  void _well(Canvas canvas, RRect r, double unit, bool odd, bool exploded) {
    final rect = r.outerRect;
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: exploded
              ? [T.badge, T.mineBoom]
              : [odd ? surfaces.wellTop : Color.lerp(surfaces.wellTop, surfaces.wellBottom, .35)!, surfaces.wellBottom],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * .3),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [T.shadow, Color(0x003A4750)],
        ).createShader(Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * .3)),
    );
    canvas.restore();
  }

  /// La salida segura del tablero del dia: un aro de acento que late y un
  /// destello.
  void _startMark(Canvas canvas, RRect r, double unit, double now) {
    final pulse = .5 + .5 * math.sin(now * 4);
    canvas.drawRRect(
      r.deflate(unit * .06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * (.08 + .04 * pulse)
        ..color = accent,
    );
    paintTwinkle(canvas, r.outerRect.center, unit * (.2 + .05 * pulse), accent);
  }

  void _flag(Canvas canvas, Rect rect, double unit, int i, double now, {required bool wrong}) {
    final planted = fx.flags[i];
    var drop = 0.0;
    if (planted != null) {
      final t = ((now - planted) / BoardFx.flagTime).clamp(0.0, 1.0);
      drop = (1 - Curves.bounceOut.transform(t)) * unit * .5;
    }
    var wave = 0.0;
    final win = fx.winAt;
    if (win != null && now - win < BoardFx.winTime) {
      wave = math.sin((now - win) * 9 + i * .7) * (1 - (now - win) / BoardFx.winTime);
    }
    paintFlag(canvas, Offset(rect.center.dx, rect.bottom - unit * .16 - drop), unit * .74,
        wave: wave, muted: wrong);
    if (wrong) {
      final c = rect.center;
      final r = unit * .26;
      final p = Paint()
        ..color = T.badge
        ..strokeWidth = math.max(1.6, unit * .09)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), p);
      canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), p);
    }
  }

  /// La onda y las chispas de la explosion.
  void _boom(Canvas canvas, double unit, double now) {
    final at = fx.boomAt;
    final idx = fx.boomCell;
    if (at == null || idx == null) return;
    final t = (now - at) / BoardFx.boomTime;
    if (t < 0 || t > 1) return;
    final c = Offset((idx % game.width + .5) * unit, (idx ~/ game.width + .5) * unit);
    final k = _ease(t);
    canvas.drawCircle(
      c,
      unit * (.4 + 4.5 * k),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * .35 * (1 - k)
        ..color = Art.sparkHot.withValues(alpha: .55 * (1 - k)),
    );
    canvas.drawCircle(
      c,
      unit * (.3 + 1.6 * k),
      Paint()
        ..color = Art.spark.withValues(alpha: .6 * (1 - k))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .3),
    );
    final rnd = math.Random(idx);
    for (var i = 0; i < 16; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final v = unit * (2 + rnd.nextDouble() * 3.4);
      final p = c + Offset(math.cos(a), math.sin(a)) * v * k + Offset(0, unit * 3 * t * t);
      paintTwinkle(canvas, p, unit * (.1 + .12 * rnd.nextDouble()) * (1.2 - t),
          (i.isEven ? Art.spark : Art.sparkHot).withValues(alpha: 1 - t));
    }
  }

  /// Confeti al ganar: cae sobre todo el tablero.
  void _confetti(Canvas canvas, Size size, double now) {
    final at = fx.winAt;
    if (at == null) return;
    final t = now - at;
    if (t < 0 || t > BoardFx.winTime) return;
    final rnd = math.Random(42);
    final fade = (1 - (t - BoardFx.winTime + .6) / .6).clamp(0.0, 1.0);
    for (var i = 0; i < 70; i++) {
      final x0 = rnd.nextDouble() * size.width;
      final delay = rnd.nextDouble() * .7;
      final speed = size.height * (.35 + rnd.nextDouble() * .35);
      final lt = t - delay;
      if (lt < 0) continue;
      final y = -20 + speed * lt + 60 * lt * lt;
      if (y > size.height + 20) continue;
      final x = x0 + math.sin(lt * (2 + rnd.nextDouble() * 3) + i) * 18;
      final w = 5 + rnd.nextDouble() * 5;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(lt * (3 + rnd.nextDouble() * 5) + i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: w * .55), const Radius.circular(1.5)),
        Paint()..color = T.confetti[i % T.confetti.length].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
