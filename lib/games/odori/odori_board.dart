// Ibasho — Odori: el tablero de Taki, los carriles por los que caen las notas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../theme/tokens.dart';
import 'odori_chart.dart';
import 'odori_engine.dart';

/// Hacia donde corren las notas. La de serie es de arriba abajo.
enum TakiFlow { down, up, right, left }

extension TakiFlowAxis on TakiFlow {
  /// Los carriles van de lado a lado y las notas de arriba abajo (o al
  /// reves); en horizontal, los carriles son filas.
  bool get vertical => this == TakiFlow.down || this == TakiFlow.up;
}

/// Aspecto de las notas: circulos, rayitas o flechas.
enum NoteLook { circle, bar, arrow }

/// Ambar de la tecla central (el espacio).
const Color odoriAmber = Color(0xFFFFB547);

/// Color de cada carril: los exteriores de plastico blanco, los interiores
/// del acento y el central ambar.
Color laneColor(int lane, int keys, Color accent) {
  if (keys.isOdd && lane == keys ~/ 2) return odoriAmber;
  if (keys >= 4 && (lane == 0 || lane == keys - 1)) return const Color(0xFFFFFFFF);
  return accent;
}

/// Lo que ve el tablero en un fotograma, ademas de las notas.
class TakiFx {
  /// Momento (tiempo de la cancion) en que se pulso cada carril por ultima
  /// vez, y si sigue pulsado.
  final List<double> pressedAt = List<double>.filled(odoriMaxKeys, -99);
  final List<bool> down = List<bool>.filled(odoriMaxKeys, false);

  /// Estallidos de los aciertos: carril, momento y juicio.
  final List<(int, double, Judgment)> bursts = <(int, double, Judgment)>[];

  void clear() {
    pressedAt.fillRange(0, odoriMaxKeys, -99);
    down.fillRange(0, odoriMaxKeys, false);
    bursts.clear();
  }
}

class TakiBoard extends StatelessWidget {
  const TakiBoard({
    super.key,
    required this.engine,
    required this.time,
    required this.fx,
    required this.accent,
    required this.accentDeep,
    this.flow = TakiFlow.down,
    this.look = NoteLook.circle,
    this.approach = 1.2,
    this.keyLabels = const <String>[],
    this.dark = false,
  });

  final OdoriEngine engine;

  /// Tiempo de la cancion; el tablero se repinta con el.
  final ValueNotifier<double> time;
  final TakiFx fx;
  final Color accent;
  final Color accentDeep;
  final TakiFlow flow;
  final NoteLook look;

  /// Segundos que tarda una nota en cruzar el tablero.
  final double approach;
  final List<String> keyLabels;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _TakiPainter(this),
      ),
    );
  }
}

/// Fraccion del recorrido donde esta la linea de juicio.
const double takiJudgeLine = .86;

class _TakiPainter extends CustomPainter {
  _TakiPainter(this.board) : super(repaint: board.time);

  final TakiBoard board;

  int get keys => board.engine.chart.keys;

  /// Pasa de coordenadas del tablero (carril a lo ancho, recorrido a lo
  /// largo, de 0 al principio a 1 al final) a la pantalla.
  Offset _at(Size size, double across, double along) => switch (board.flow) {
        TakiFlow.down => Offset(across * size.width, along * size.height),
        TakiFlow.up => Offset(across * size.width, (1 - along) * size.height),
        TakiFlow.right => Offset(along * size.width, across * size.height),
        TakiFlow.left => Offset((1 - along) * size.width, across * size.height),
      };

  double _laneSpan(Size size) => (board.flow.vertical ? size.width : size.height) / keys;
  double _length(Size size) => board.flow.vertical ? size.height : size.width;

  /// Donde va una nota de tiempo [t] ahora, de 0 a 1 en el recorrido.
  double _along(double t, double now) => takiJudgeLine - (t - now) / board.approach * takiJudgeLine;

  @override
  void paint(Canvas canvas, Size size) {
    final now = board.time.value;
    final span = _laneSpan(size);
    final length = _length(size);
    final colors = [for (var j = 0; j < keys; j++) laneColor(j, keys, board.accent)];

    // Carriles: franjas muy suaves de su color, con un haz al pulsar.
    for (var j = 0; j < keys; j++) {
      final a = _at(size, j / keys, 0);
      final b = _at(size, (j + 1) / keys, 1);
      final rect = Rect.fromPoints(a, b);
      final base = colors[j] == const Color(0xFFFFFFFF) ? board.accentDeep : colors[j];
      canvas.drawRect(rect, Paint()..color = base.withValues(alpha: board.dark ? .10 : .07));
      final since = now - board.fx.pressedAt[j];
      final held = board.fx.down[j];
      final glow = held ? 1.0 : (since >= 0 && since < .18 ? 1 - since / .18 : 0.0);
      if (glow > 0) {
        final from = _at(size, (j + .5) / keys, takiJudgeLine);
        final to = _at(size, (j + .5) / keys, takiJudgeLine * .35);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.linear(from, to, [
              base.withValues(alpha: .34 * glow),
              base.withValues(alpha: 0),
            ]),
        );
      }
      if (j > 0) {
        canvas.drawLine(
          _at(size, j / keys, 0),
          _at(size, j / keys, 1),
          Paint()
            ..color = (board.dark ? const Color(0xFFFFFFFF) : T.hairline).withValues(alpha: board.dark ? .12 : .8)
            ..strokeWidth = 1,
        );
      }
    }

    // Linea de juicio: una barra de cristal.
    final lineA = _at(size, 0, takiJudgeLine);
    final lineB = _at(size, 1, takiJudgeLine);
    canvas.drawLine(
      lineA,
      lineB,
      Paint()
        ..color = board.accentDeep.withValues(alpha: .35)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final r = math.min(span * .36, 30.0);

    // Receptores: aros del color del carril, que se hunden al pulsar.
    for (var j = 0; j < keys; j++) {
      final c = _at(size, (j + .5) / keys, takiJudgeLine);
      final pressed = board.fx.down[j];
      _receptor(canvas, c, r * (pressed ? .9 : 1), colors[j], pressed, j);
      if (j < board.keyLabels.length) {
        final tp = TextPainter(
          text: TextSpan(
            text: board.keyLabels[j],
            style: TextStyle(
              fontFamily: 'Rounded',
              fontSize: math.min(14, r * .55),
              fontWeight: FontWeight.w700,
              color: (board.dark ? const Color(0xFFFFFFFF) : T.ink).withValues(alpha: .45),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lc = _at(size, (j + .5) / keys, math.min(.985, takiJudgeLine + (r + 10) / length));
        tp.paint(canvas, lc - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Notas.
    final notes = board.engine.chart.notes;
    final state = board.engine.state;
    final horizon = now + board.approach * 1.05;
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.time > horizon) break;
      final st = state[i];
      if (st == NoteState.done) continue;
      if (!n.hold && st == NoteState.missed && now - n.time > .25) continue;
      if (n.hold && n.end < now - .25) continue;
      final color = colors[n.lane];
      final faded = st == NoteState.missed;
      final across = (n.lane + .5) / keys;
      if (n.hold) {
        final head = st == NoteState.holding ? takiJudgeLine : _along(n.time, now);
        final tail = _along(n.end, now);
        _holdBody(canvas, _at(size, across, tail.clamp(-.1, 1.1)), _at(size, across, head.clamp(-.1, 1.1)), r, color,
            faded, st == NoteState.holding);
        if (st != NoteState.holding) _note(canvas, _at(size, across, head), r, color, faded, n.lane);
      } else {
        _note(canvas, _at(size, across, _along(n.time, now)), r, color, faded, n.lane);
      }
    }

    // Estallidos: un anillo que se abre donde se acerto. Un fallo deja el
    // receptor rojo un momento, temblando.
    for (final (lane, at, j) in board.fx.bursts) {
      final age = now - at;
      if (age < 0 || age > .3) continue;
      if (j == Judgment.miss) {
        final k = age / .3;
        final shake = math.sin(age * 70) * r * .12 * (1 - k);
        final c = _at(size, (lane + .5) / keys, takiJudgeLine) + Offset(shake, 0);
        canvas
          ..drawCircle(c, r, Paint()..color = const Color(0xFFFF4D6A).withValues(alpha: .25 * (1 - k)))
          ..drawCircle(
            c,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = const Color(0xFFFF4D6A).withValues(alpha: .9 * (1 - k)),
          );
        continue;
      }
      final k = age / .3;
      final c = _at(size, (lane + .5) / keys, takiJudgeLine);
      final col = j == Judgment.brillo ? odoriAmber : colors[lane];
      canvas.drawCircle(
        c,
        r * (1 + k * .9),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * (1 - k)
          ..color = (col == const Color(0xFFFFFFFF) ? board.accent : col).withValues(alpha: 1 - k),
      );
      // El brillo, ademas, un segundo anillo dorado mas ancho.
      if (j == Judgment.brillo) {
        canvas.drawCircle(
          c,
          r * (1.15 + k * 1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5 * (1 - k)
            ..color = const Color(0xFFFFE08A).withValues(alpha: .8 * (1 - k)),
        );
      }
    }
  }

  void _receptor(Canvas canvas, Offset c, double r, Color color, bool pressed, int lane) {
    final rim = color == const Color(0xFFFFFFFF) ? board.accentDeep : color;
    canvas.drawCircle(c, r, Paint()..color = rim.withValues(alpha: pressed ? .32 : .12));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = rim.withValues(alpha: pressed ? .95 : .6),
    );
    if (board.look == NoteLook.arrow) _arrowPath(canvas, c, r * .55, lane, Paint()..color = rim.withValues(alpha: .35));
  }

  void _note(Canvas canvas, Offset c, double r, Color color, bool faded, int lane) {
    final rim = color == const Color(0xFFFFFFFF) ? board.accentDeep : Color.lerp(color, const Color(0xFF000000), .25)!;
    final alpha = faded ? .3 : 1.0;
    final light = Color.lerp(color, const Color(0xFFFFFFFF), .55)!;
    switch (board.look) {
      case NoteLook.circle:
        final rect = Rect.fromCircle(center: c, radius: r);
        canvas.drawCircle(c + const Offset(0, 2), r, Paint()..color = T.shadowDeep.withValues(alpha: .25 * alpha));
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-.3, -.4),
              colors: [light.withValues(alpha: alpha), color.withValues(alpha: alpha)],
            ).createShader(rect),
        );
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = rim.withValues(alpha: alpha),
        );
        // Brillo de plastico lacado.
        canvas.drawOval(
          Rect.fromCenter(center: c + Offset(-r * .18, -r * .42), width: r * 1.1, height: r * .5),
          Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: .7 * alpha),
        );
      case NoteLook.bar:
        final span = r * 2.4;
        final w = board.flow.vertical ? span : r * .7;
        final h = board.flow.vertical ? r * .7 : span;
        final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w, height: h), Radius.circular(r * .35));
        canvas.drawRRect(
          rr,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [light.withValues(alpha: alpha), color.withValues(alpha: alpha)],
            ).createShader(rr.outerRect),
        );
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = rim.withValues(alpha: alpha),
        );
      case NoteLook.arrow:
        _arrowPath(canvas, c, r, lane, Paint()..color = color.withValues(alpha: alpha));
        _arrowPath(
          canvas,
          c,
          r,
          lane,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeJoin = StrokeJoin.round
            ..color = rim.withValues(alpha: alpha),
        );
    }
  }

  /// Direccion de la flecha de cada carril, en radianes (0 = derecha): con 4
  /// teclas, izquierda, abajo, arriba y derecha; si no, en el sentido en que
  /// corren las notas.
  double _arrowAngle(int lane) {
    if (keys == 4) return const [math.pi, math.pi / 2, -math.pi / 2, 0.0][lane];
    return switch (board.flow) {
      TakiFlow.down => math.pi / 2,
      TakiFlow.up => -math.pi / 2,
      TakiFlow.right => 0.0,
      TakiFlow.left => math.pi,
    };
  }

  void _arrowPath(Canvas canvas, Offset c, double r, int lane, Paint paint) {
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(0, -r)
      ..lineTo(0, -r * .45)
      ..lineTo(-r, -r * .45)
      ..lineTo(-r, r * .45)
      ..lineTo(0, r * .45)
      ..lineTo(0, r)
      ..close();
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(_arrowAngle(lane));
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _holdBody(Canvas canvas, Offset from, Offset to, double r, Color color, bool faded, bool active) {
    final w = r * .9;
    final rect = Rect.fromPoints(from, to).inflate(w / 2);
    final body = board.flow.vertical
        ? Rect.fromLTRB(from.dx - w / 2, math.min(from.dy, to.dy), from.dx + w / 2, math.max(from.dy, to.dy))
        : Rect.fromLTRB(math.min(from.dx, to.dx), from.dy - w / 2, math.max(from.dx, to.dx), from.dy + w / 2);
    final base = color == const Color(0xFFFFFFFF) ? board.accent : color;
    final rr = RRect.fromRectAndRadius(body.isEmpty ? rect : body, Radius.circular(w / 2));
    canvas.drawRRect(rr, Paint()..color = base.withValues(alpha: faded ? .12 : (active ? .7 : .45)));
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFFFFF).withValues(alpha: faded ? .2 : .7),
    );
  }

  @override
  bool shouldRepaint(_TakiPainter old) => old.board != board;
}
