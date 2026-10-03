// Ibasho — Tama Kōen: el accesorio de pareja, cuando los dos están juntos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/koen_duo.dart';
import '../../backend/prizes.dart';
import '../../backend/tama.dart';
import '../../ui/tama/tama_outfit.dart' show koenCharmColor;
import '../../ui/tama/tama_painter.dart';

/// Lo que lleva puesto [look], por clave.
Iterable<String> koenWornKeys(TamaLook look) => [?look.outfit.hat, ...look.outfit.accessories];

/// Si [a] y [b] llevan cada uno una mitad del mismo accesorio de pareja.
KoenCharmChoice? koenCharmLink(TamaLook a, TamaLook b) => koenCharmMatch(koenWornKeys(a), koenWornKeys(b));

/// [look] con la mitad [key] puesta en lugar de cualquier otra mitad que
/// llevara. Si no le cabe (tres accesorios en otros sitios), `null`.
TamaLook? koenWithCharm(TamaLook look, String key) {
  final item = prizeItem(key);
  if (item == null) return null;
  final next = koenWithoutCharm(look).outfit.toggle(item);
  return next == null ? null : look.withOutfit(next);
}

/// [look] sin ninguna mitad de accesorio de pareja.
TamaLook koenWithoutCharm(TamaLook look) {
  final o = look.outfit;
  return look.withOutfit(TamaOutfit(
    hat: koenCharmOf(o.hat) == null ? o.hat : null,
    accessories: [for (final k in o.accessories) if (koenCharmOf(k) == null) k],
  ));
}

/// Dónde se ata el hilo de un Tama de [size] puesto con su lienzo en
/// [topLeft]: el costado que mira al otro ([towardRight]), a la altura de la
/// mano.
Offset koenCharmAnchor(TamaLook look, Offset topLeft, double size, {required bool towardRight}) {
  final body = TamaBody.of(look);
  final r = body.bounds;
  final y = r.top + r.height * .62;
  final x = TamaPainter.centreX + (towardRight ? 1 : -1) * body.halfWidthAt(y);
  return topLeft + Offset(x, y) * (size / 100);
}

/// Lo que se ve cuando los dos llevan su mitad y están juntos: el hilo rojo
/// va de uno a otro y, con las otras formas, entre los dos flota un corazón
/// entero del color de la pareja.
class KoenCharmLinkPainter extends CustomPainter {
  KoenCharmLinkPainter({required this.charm, required this.from, required this.to, required this.scale});

  final KoenCharmChoice charm;

  /// El costado del Tama de la izquierda y el del de la derecha.
  final Offset from;
  final Offset to;

  /// Lo que mide un Tama, para el grosor.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final span = to - from;
    if (charm.shape == KoenCharm.thread) {
      // Cuelga un poco, más cuanto más lejos están.
      final sag = math.min(span.distance * .22, scale * .3);
      final mid = Offset((from.dx + to.dx) / 2, math.max(from.dy, to.dy) + sag);
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, to.dx, to.dy);
      final w = math.max(1.6, scale * .028);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w + 1.6
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFA82633),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFFE8414E),
      );
      return;
    }
    final color = koenCharmColor(charm.code);
    final h = math.max(10.0, scale * .2);
    final at = Offset((from.dx + to.dx) / 2, math.min(from.dy, to.dy) - scale * .68);
    canvas.drawCircle(at, h * .9, Paint()..color = color.withValues(alpha: .28)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    final heart = koenHeartPath(at, h);
    canvas.drawPath(heart, Paint()..color = color);
    canvas.drawPath(
      heart,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, h * .1)
        ..strokeJoin = StrokeJoin.round
        ..color = HSLColor.fromColor(color).withLightness(.38).toColor(),
    );
    canvas.drawCircle(at + Offset(-h * .2, -h * .12), h * .1, Paint()..color = const Color(0xCCFFFFFF));
  }

  @override
  bool shouldRepaint(KoenCharmLinkPainter old) =>
      old.from != from || old.to != to || old.scale != scale || old.charm.shape != charm.shape || old.charm.code != charm.code;
}

/// Un corazón de alto [h] con el centro en [c].
Path koenHeartPath(Offset c, double h) {
  final w = h * 1.1;
  final top = c.dy - h * .38;
  return Path()
    ..moveTo(c.dx, c.dy + h * .5)
    ..cubicTo(c.dx - w * .55, c.dy + h * .1, c.dx - w * .55, top - h * .2, c.dx - w * .22, top - h * .12)
    ..cubicTo(c.dx - w * .08, top - h * .08, c.dx, top + h * .02, c.dx, top + h * .1)
    ..cubicTo(c.dx, top + h * .02, c.dx + w * .08, top - h * .08, c.dx + w * .22, top - h * .12)
    ..cubicTo(c.dx + w * .55, top - h * .2, c.dx + w * .55, c.dy + h * .1, c.dx, c.dy + h * .5)
    ..close();
}

/// [look] con las mitades del accesorio cambiadas de lado: es lo que se
/// pinta cuando el Tama mira a la izquierda (se dibuja en espejo), para que
/// la mitad siga mirando hacia el otro.
TamaLook koenMirrorCharm(TamaLook look) {
  String flip(String key) {
    final half = koenCharmOf(key);
    return half == null ? key : koenCharmKey(half.shape, left: !half.left, code: half.code);
  }

  final o = look.outfit;
  if (![?o.hat, ...o.accessories].any((k) => koenCharmOf(k) != null)) return look;
  return look.withOutfit(TamaOutfit(
    hat: o.hat == null ? null : flip(o.hat!),
    accessories: [for (final k in o.accessories) flip(k)],
  ));
}
