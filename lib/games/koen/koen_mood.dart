// Ibasho — Tama Kōen: lo que se dicen dos Tamas y cómo se dibuja.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../audio/tama_voice.dart';
import '../../backend/tama.dart';
import '../../ui/widgets/channel_art.dart' show Art;

/// Los estados de ánimo que salen en los bocadillos.
enum KoenMood {
  greet,
  happy,
  laugh,
  surprise,
  shy,
  sleepy,
  pout,
  love,
  curious,
  sing;

  /// La cara que pone el Tama mientras lo dice (humor de -1 a 1).
  double get joy => switch (this) {
    love || laugh => 1,
    happy => .9,
    sing => .8,
    greet => .7,
    curious => .5,
    surprise => .4,
    shy => .3,
    sleepy => .2,
    pout => -.2,
  };

  /// Cómo suena al decirlo.
  ChirpKind get chirp => switch (this) {
    love || laugh || happy || sing => ChirpKind.happy,
    greet || curious || surprise => ChirpKind.hello,
    shy || sleepy || pout => ChirpKind.sigh,
  };

  /// Si da un saltito al decirlo. Solo con lo que emociona.
  bool get hops => this == laugh || this == love || this == surprise;
}

/// Una frase de la conversación: quién la dice ([first] es el que empieza) y
/// con qué ánimo.
typedef KoenLine = ({bool first, KoenMood mood});

/// La conversación entre dos Tamas que se encuentran: de tres a cinco frases
/// por turnos, según lo bien que se conocen ([closeness], de 0 a 1) y la
/// personalidad de cada uno.
///
/// Los que apenas se conocen se saludan con timidez y curiosidad; los muy
/// amigos se ríen y se dan cariño. El tímido se avergüenza con quien no
/// conoce, el pícaro gasta bromas (y el otro se sorprende o se ríe), el
/// juguetón canta y el dormilón bosteza.
List<KoenLine> koenChat({
  required TamaPersonality first,
  required TamaPersonality second,
  required double closeness,
  required math.Random random,
}) {
  T any<T>(List<T> from) => from[random.nextInt(from.length)];
  final stranger = closeness < .35;
  final close = closeness >= .7;
  final count = 3 + random.nextInt(stranger ? 2 : 3);
  final out = <KoenLine>[];
  for (var i = 0; i < count; i++) {
    final isFirst = i.isEven;
    final me = isFirst ? first : second;
    final prev = out.isEmpty ? null : out.last.mood;
    var mood = switch (prev) {
      // Quien empieza.
      null => stranger
          ? any([KoenMood.greet, KoenMood.greet, KoenMood.curious])
          : close
          ? any([KoenMood.love, KoenMood.happy, KoenMood.greet])
          : any([KoenMood.greet, KoenMood.happy]),
      // Se responde a lo que ha dicho el otro.
      KoenMood.pout => any([KoenMood.surprise, KoenMood.laugh]),
      KoenMood.surprise => any([KoenMood.laugh, KoenMood.happy]),
      KoenMood.love => close ? any([KoenMood.love, KoenMood.happy]) : KoenMood.shy,
      KoenMood.greet when stranger => any([KoenMood.greet, KoenMood.curious]),
      KoenMood.greet => any([KoenMood.greet, KoenMood.happy]),
      KoenMood.sleepy => any([KoenMood.curious, KoenMood.laugh]),
      _ => stranger
          ? any([KoenMood.curious, KoenMood.happy, KoenMood.greet])
          : close
          ? any([KoenMood.laugh, KoenMood.love, KoenMood.happy, KoenMood.sing])
          : any([KoenMood.happy, KoenMood.laugh, KoenMood.curious]),
    };
    // Cada uno a su manera, pero sin pisar la reacción a una broma.
    if (prev != KoenMood.pout) {
      switch (me) {
        case TamaPersonality.shy when closeness < .5 && random.nextInt(2) == 0:
          mood = KoenMood.shy;
        case TamaPersonality.cheeky when i > 0 && i < count - 1 && random.nextInt(5) < 2:
          mood = KoenMood.pout;
        case TamaPersonality.playful when random.nextInt(10) < 3:
          mood = any([KoenMood.sing, KoenMood.laugh]);
        case TamaPersonality.sleepy when i > 0 && random.nextInt(4) == 0:
          mood = KoenMood.sleepy;
        case TamaPersonality.calm when mood == KoenMood.laugh:
          mood = KoenMood.happy;
        default:
          break;
      }
    }
    // La última frase, siempre en paz.
    if (i == count - 1 && (mood == KoenMood.pout || mood == KoenMood.surprise)) mood = KoenMood.laugh;
    out.add((first: isFirst, mood: mood));
  }
  return out;
}

/// Un bocadillo con un estado de ánimo dibujado: la carita del Tama (de su
/// color) poniendo esa cara, o un corazón, una nota o unas zetas al lado.
///
/// [age] son los segundos que lleva fuera y [life] los que dura: entra con
/// un rebote y se va desvaneciendo. Con [tailRight], el pico apunta abajo a
/// la derecha (el Tama queda a ese lado).
class KoenBubblePainter extends CustomPainter {
  KoenBubblePainter({
    required this.mood,
    required this.tint,
    required this.age,
    required this.life,
    required this.tailRight,
  });

  final KoenMood mood;
  final Color tint;
  final double age;
  final double life;
  final bool tailRight;

  static const Color _ink = Color(0xFF3A3340);
  static const Color _blush = Color(0xFFFF8FA8);

  @override
  void paint(Canvas canvas, Size size) {
    final pop = age < .22 ? Curves.easeOutBack.transform((age / .22).clamp(0.0, 1.0)) : 1.0;
    final fade = ((life - age) / .25).clamp(0.0, 1.0);
    if (pop <= 0 || fade <= 0) return;
    final tailTip = Offset(tailRight ? size.width * .78 : size.width * .22, size.height);
    canvas.save();
    canvas.translate(tailTip.dx, tailTip.dy);
    canvas.scale(pop);
    canvas.translate(-tailTip.dx, -tailTip.dy);
    canvas.saveLayer(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, fade));

    // El globo y su pico.
    final body = Rect.fromLTWH(0, 0, size.width, size.height * .82);
    final shape = Path()
      ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(size.height * .32)))
      ..moveTo(tailTip.dx + (tailRight ? -size.width * .2 : size.width * .06), body.bottom - 1)
      ..lineTo(tailTip.dx, tailTip.dy)
      ..lineTo(tailTip.dx + (tailRight ? -size.width * .06 : size.width * .2), body.bottom - 1)
      ..close();
    canvas.drawShadow(shape, const Color(0x55000000), 2, false);
    canvas.drawPath(shape, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(
      shape,
      Paint()
        ..color = const Color(0x22000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final r = body.height * .34;
    final c = body.center;
    switch (mood) {
      case KoenMood.love:
        // Carita con ojos de corazón y un corazón que late al lado.
        _face(canvas, c + Offset(-r * .35, 0), r * .9);
        final f = c + Offset(-r * .35, 0);
        for (final dx in [-.36, .36]) {
          canvas.drawPath(_heart(f + Offset(r * .9 * dx, -r * .12), r * .3), Paint()..color = const Color(0xFFFF4F79));
        }
        _smile(canvas, f + Offset(0, r * .3), r * .3, open: false);
        final beat = 1 + .12 * math.sin(age * 9).abs();
        canvas.drawPath(_heart(c + Offset(r * 1.15, -r * .45), r * .42 * beat), Paint()..color = const Color(0xFFFF4F79));
      case KoenMood.sing:
        final f = c + Offset(-r * .35, 0);
        _face(canvas, f, r * .9);
        _closedEyes(canvas, f, r * .9, happy: true);
        canvas.drawOval(Rect.fromCenter(center: f + Offset(0, r * .38), width: r * .32, height: r * .4), Paint()..color = _ink);
        _note(canvas, c + Offset(r * 1.15, -r * .2 - math.sin(age * 5) * r * .12), r * .5);
      case KoenMood.sleepy:
        final f = c + Offset(-r * .35, r * .1);
        _face(canvas, f, r * .9);
        _closedEyes(canvas, f, r * .9, happy: false);
        canvas.drawCircle(f + Offset(0, r * .42), r * .1, _stroke(r * .08));
        for (var i = 0; i < 2; i++) {
          final rise = (age * .8 + i * .5) % 1;
          _zee(canvas, c + Offset(r * (.9 + i * .45), -r * (.1 + rise * .7 + i * .2)), r * (.34 - i * .1));
        }
      default:
        _face(canvas, c, r);
        _expression(canvas, c, r);
    }
    canvas.restore();
    canvas.restore();
  }

  void _expression(Canvas canvas, Offset c, double r) {
    final ink = Paint()..color = _ink;
    final eyeL = c + Offset(-r * .36, -r * .12);
    final eyeR = c + Offset(r * .36, -r * .12);
    switch (mood) {
      case KoenMood.greet:
        canvas.drawCircle(eyeL, r * .1, ink);
        canvas.drawCircle(eyeR, r * .1, ink);
        _smile(canvas, c + Offset(0, r * .28), r * .34, open: false);
        // La manita que saluda, con dos rayitas de movimiento.
        final wave = math.sin(age * 10) * .25;
        final hand = c + Offset(r * 1.15, -r * .55) + Offset(math.cos(wave) * r * .1, math.sin(wave) * r * .3);
        canvas.drawCircle(hand, r * .28, Paint()..color = _light);
        canvas.drawCircle(hand, r * .28, _stroke(r * .07, Art.deep(tint, .45)));
        for (final a in [-.5, .2]) {
          canvas.drawArc(Rect.fromCircle(center: hand, radius: r * .52), a, .5, false, _stroke(r * .07));
        }
      case KoenMood.happy:
        _closedEyes(canvas, c, r, happy: true);
        _smile(canvas, c + Offset(0, r * .25), r * .42, open: false);
        _cheeks(canvas, c, r, .45);
      case KoenMood.laugh:
        // Ojos > < y la boca muy abierta.
        final eye = _stroke(r * .1);
        for (final (e, d) in [(eyeL, 1.0), (eyeR, -1.0)]) {
          canvas.drawPath(
            Path()
              ..moveTo(e.dx - d * r * .14, e.dy - r * .13)
              ..lineTo(e.dx + d * r * .1, e.dy)
              ..lineTo(e.dx - d * r * .14, e.dy + r * .13),
            eye,
          );
        }
        _smile(canvas, c + Offset(0, r * .2), r * .5, open: true);
        _cheeks(canvas, c, r, .4);
      case KoenMood.surprise:
        for (final e in [eyeL, eyeR]) {
          canvas.drawCircle(e, r * .16, Paint()..color = const Color(0xFFFFFFFF));
          canvas.drawCircle(e, r * .16, _stroke(r * .06));
          canvas.drawCircle(e, r * .07, ink);
          canvas.drawArc(Rect.fromCircle(center: e + Offset(0, -r * .1), radius: r * .22), math.pi * 1.2, math.pi * .6, false, _stroke(r * .07));
        }
        canvas.drawOval(Rect.fromCenter(center: c + Offset(0, r * .42), width: r * .3, height: r * .36), ink);
      case KoenMood.shy:
        // Mira al suelo, con los mofletes rojos y una gotita.
        canvas.drawCircle(eyeL + Offset(0, r * .12), r * .09, ink);
        canvas.drawCircle(eyeR + Offset(0, r * .12), r * .09, ink);
        final mouth = c + Offset(0, r * .42);
        canvas.drawPath(
          Path()
            ..moveTo(mouth.dx - r * .2, mouth.dy)
            ..quadraticBezierTo(mouth.dx - r * .1, mouth.dy - r * .08, mouth.dx, mouth.dy)
            ..quadraticBezierTo(mouth.dx + r * .1, mouth.dy + r * .08, mouth.dx + r * .2, mouth.dy),
          _stroke(r * .07),
        );
        _cheeks(canvas, c, r, .75);
        final lines = _stroke(r * .05, const Color(0xFFE0566F));
        for (final s in [-1.0, 1.0]) {
          final b = c + Offset(s * r * .55, r * .2);
          for (var i = -1; i <= 1; i++) {
            canvas.drawLine(b + Offset(i * r * .1 - r * .04, r * .05), b + Offset(i * r * .1 + r * .04, -r * .05), lines);
          }
        }
        final drop = c + Offset(r * .95, -r * .55);
        canvas.drawPath(
          Path()
            ..moveTo(drop.dx, drop.dy - r * .28)
            ..quadraticBezierTo(drop.dx + r * .2, drop.dy, drop.dx, drop.dy + r * .1)
            ..quadraticBezierTo(drop.dx - r * .2, drop.dy, drop.dx, drop.dy - r * .28),
          Paint()..color = const Color(0xFF8FD3FF),
        );
      case KoenMood.pout:
        // Enfado de broma: cejas fruncidas, morritos y un moflete hinchado.
        final brow = _stroke(r * .08);
        canvas.drawLine(eyeL + Offset(-r * .16, -r * .26), eyeL + Offset(r * .12, -r * .16), brow);
        canvas.drawLine(eyeR + Offset(r * .16, -r * .26), eyeR + Offset(-r * .12, -r * .16), brow);
        canvas.drawCircle(eyeL, r * .09, ink);
        canvas.drawCircle(eyeR, r * .09, ink);
        final puff = 1 + .08 * math.sin(age * 6);
        canvas.drawCircle(c + Offset(r * .62, r * .3), r * .26 * puff, Paint()..color = Art.deep(tint, .12));
        canvas.drawCircle(c + Offset(r * .62, r * .3), r * .14, Paint()..color = _blush.withValues(alpha: .7));
        canvas.drawArc(Rect.fromCenter(center: c + Offset(-r * .05, r * .5), width: r * .3, height: r * .22), math.pi * 1.1, math.pi * .8, false, _stroke(r * .08));
      case KoenMood.curious:
        // Mira hacia arriba de lado, con un interrogante dibujado.
        canvas.drawCircle(eyeL + Offset(r * .06, -r * .06), r * .11, ink);
        canvas.drawCircle(eyeR + Offset(r * .06, -r * .06), r * .13, ink);
        canvas.drawLine(c + Offset(-r * .12, r * .4), c + Offset(r * .16, r * .36), _stroke(r * .08));
        final q = c + Offset(r * 1.12, -r * .5);
        canvas.drawPath(
          Path()
            ..moveTo(q.dx - r * .18, q.dy - r * .12)
            ..cubicTo(q.dx - r * .18, q.dy - r * .45, q.dx + r * .26, q.dy - r * .45, q.dx + r * .2, q.dy - r * .12)
            ..quadraticBezierTo(q.dx + r * .15, q.dy + r * .04, q.dx, q.dy + r * .12)
            ..lineTo(q.dx, q.dy + r * .24),
          _stroke(r * .1, const Color(0xFF6B8CFF)),
        );
        canvas.drawCircle(q + Offset(0, r * .44), r * .07, Paint()..color = const Color(0xFF6B8CFF));
      default:
        break;
    }
  }

  Color get _light => Color.lerp(tint, const Color(0xFFFFFFFF), .25)!;

  Paint _stroke(double width, [Color color = _ink]) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _face(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = _light);
    canvas.drawCircle(c, r, _stroke(r * .08, Art.deep(tint, .45)));
    canvas.drawCircle(c + Offset(-r * .4, -r * .45), r * .16, Paint()..color = const Color(0x88FFFFFF));
  }

  void _closedEyes(Canvas canvas, Offset c, double r, {required bool happy}) {
    for (final dx in [-.36, .36]) {
      final e = c + Offset(r * dx, -r * .1);
      canvas.drawArc(
        Rect.fromCenter(center: e + Offset(0, happy ? r * .06 : -r * .04), width: r * .3, height: r * .24),
        happy ? math.pi : 0,
        math.pi,
        false,
        _stroke(r * .08),
      );
    }
  }

  void _smile(Canvas canvas, Offset c, double w, {required bool open}) {
    final rect = Rect.fromCenter(center: c, width: w, height: w * .8);
    if (!open) {
      canvas.drawArc(rect, .25, math.pi - .5, false, _stroke(w * .2));
      return;
    }
    final mouth = Path()
      ..moveTo(rect.left, c.dy)
      ..arcTo(rect, math.pi, -math.pi, false)
      ..close();
    canvas.drawPath(mouth, Paint()..color = _ink);
    canvas.save();
    canvas.clipPath(mouth);
    canvas.drawCircle(c + Offset(0, w * .42), w * .26, Paint()..color = _blush);
    canvas.restore();
  }

  void _cheeks(Canvas canvas, Offset c, double r, double alpha) {
    final p = Paint()..color = _blush.withValues(alpha: alpha);
    for (final dx in [-.58, .58]) {
      canvas.drawOval(Rect.fromCenter(center: c + Offset(r * dx, r * .22), width: r * .32, height: r * .2), p);
    }
  }

  Path _heart(Offset c, double s) => Path()
    ..moveTo(c.dx, c.dy + s * .8)
    ..cubicTo(c.dx - s * 1.3, c.dy - s * .1, c.dx - s * .6, c.dy - s * 1.1, c.dx, c.dy - s * .35)
    ..cubicTo(c.dx + s * .6, c.dy - s * 1.1, c.dx + s * 1.3, c.dy - s * .1, c.dx, c.dy + s * .8)
    ..close();

  void _note(Canvas canvas, Offset c, double s) {
    final p = Paint()..color = const Color(0xFF7A5CFF);
    final head = c + Offset(-s * .25, s * .5);
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(-.4);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: s * .62, height: s * .44), p);
    canvas.restore();
    final top = head + Offset(s * .27, -s * 1.1);
    canvas.drawLine(head + Offset(s * .27, -s * .05), top, _stroke(s * .13, p.color));
    canvas.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(top.dx + s * .5, top.dy + s * .2, top.dx + s * .35, top.dy + s * .6),
      _stroke(s * .13, p.color),
    );
  }

  void _zee(Canvas canvas, Offset c, double s) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - s * .5, c.dy - s * .5)
        ..lineTo(c.dx + s * .5, c.dy - s * .5)
        ..lineTo(c.dx - s * .5, c.dy + s * .5)
        ..lineTo(c.dx + s * .5, c.dy + s * .5),
      _stroke(s * .22, const Color(0xFF6B8CFF)),
    );
  }

  @override
  bool shouldRepaint(KoenBubblePainter old) =>
      old.mood != mood || old.tint != tint || old.age != age || old.tailRight != tailRight || old.life != life;
}
