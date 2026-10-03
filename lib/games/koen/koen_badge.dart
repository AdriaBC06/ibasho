// Ibasho — Tama Kōen: la insignia de amistad entre jugadores.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../backend/koen_bonds.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/type.dart';
import '../../ui/widgets/gloss.dart';
import 'koen_charm.dart' show koenHeartPath;

/// El color de cada nivel: de un verde suave (conocidos) al oro
/// (inseparables).
Color koenFriendColor(KoenFriendLevel level) => switch (level) {
  KoenFriendLevel.none => const Color(0xFFDDE7EF),
  KoenFriendLevel.acquainted => const Color(0xFFA6DE92),
  KoenFriendLevel.friends => const Color(0xFF7FD4F5),
  KoenFriendLevel.good => const Color(0xFFF08FB0),
  KoenFriendLevel.inseparable => const Color(0xFFF6C43A),
};

/// La insignia redonda: un corazón sobre un disco del color del nivel y, a
/// su alrededor, un anillo de cuatro tramos que se encienden uno por nivel.
class KoenFriendBadge extends StatelessWidget {
  const KoenFriendBadge({super.key, required this.level, this.size = 22});

  final KoenFriendLevel level;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: L.of(context)!.koenFriendBadge(L.of(context)!.koenFriendLevel(level.name)),
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: KoenFriendBadgePainter(level)),
      ),
    ),
  );
}

/// El dibujo de [KoenFriendBadge], para pintarlo también en un lienzo.
class KoenFriendBadgePainter extends CustomPainter {
  const KoenFriendBadgePainter(this.level);

  final KoenFriendLevel level;

  static Color deep(KoenFriendLevel level) {
    final hsl = HSLColor.fromColor(koenFriendColor(level));
    return hsl.withLightness(.36).withSaturation(math.min(1, hsl.saturation * .9)).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final color = koenFriendColor(level);
    final ink = level == KoenFriendLevel.none ? const Color(0xFF9AAAB8) : deep(level);

    // El anillo: un tramo por nivel, de arriba en el sentido del reloj.
    final ring = s * .13;
    final r = s / 2 - ring / 2 - s * .02;
    final track = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, s / 2 - s * .01, Paint()..color = const Color(0x1F0A2A44));
    const steps = 4;
    const gap = .34;
    for (var i = 0; i < steps; i++) {
      final lit = i < level.index;
      canvas.drawArc(
        track,
        -math.pi / 2 + i * math.pi / 2 + gap / 2,
        math.pi / 2 - gap,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ring
          ..strokeCap = StrokeCap.round
          ..color = lit ? ink : const Color(0xFFFFFFFF).withValues(alpha: .75),
      );
    }

    // El disco, con brillo arriba como el resto de plásticos.
    final disc = r - ring / 2 - s * .035;
    final rect = Rect.fromCircle(center: c, radius: disc);
    canvas.drawCircle(
      c,
      disc,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.3, -.5),
          radius: 1.1,
          colors: [Color.lerp(color, const Color(0xFFFFFFFF), .55)!, color],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      disc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, s * .025)
        ..color = ink.withValues(alpha: .35),
    );

    // El corazón: lleno desde «conocidos», solo el contorno si aún no hay nada.
    final h = disc * 1.05;
    final heart = koenHeartPath(c + Offset(0, disc * .04), h);
    if (level == KoenFriendLevel.none) {
      canvas.drawPath(
        heart,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, s * .05)
          ..strokeJoin = StrokeJoin.round
          ..color = ink,
      );
      return;
    }
    canvas.drawPath(heart, Paint()..color = ink);
    canvas.drawCircle(
      c + Offset(-h * .22, -h * .1),
      math.max(.8, h * .09),
      Paint()..color = const Color(0xD9FFFFFF),
    );
  }

  @override
  bool shouldRepaint(KoenFriendBadgePainter old) => old.level != level;
}

/// La pastilla del perfil de un amigo: la insignia y el nombre del nivel.
class KoenFriendChip extends StatelessWidget {
  const KoenFriendChip({super.key, required this.level});

  final KoenFriendLevel level;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return SizedBox(
      height: 30,
      child: GlossSurface(
        radius: 15,
        recessed: true,
        tint: koenFriendColor(level),
        padding: const EdgeInsets.only(left: 4, right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KoenFriendBadge(level: level, size: 22),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l.koenFriendBadge(l.koenFriendLevel(level.name)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ty.caption.copyWith(color: Ty.ink, height: 1.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
