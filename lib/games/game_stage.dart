// Ibasho — piezas comunes de los juegos: el foco y el bocadillo del Tama, la
// cara de reserva, los marcadores, las monedas del dia y las chapas de los
// resultados.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../state/providers.dart';
import '../state/rewards.dart';
import '../theme/menu_theme.dart';
import '../theme/skin.dart';
import '../theme/tokens.dart';
import '../theme/type.dart';
import '../ui/widgets/channel_art.dart';
import '../ui/widgets/glyphs.dart';
import '../ui/widgets/gloss.dart';
import '../ui/widgets/pressable.dart';

// --- Escenario del Tama -----------------------------------------------------

/// Un foco suave detras del Tama: un disco de luz del acento que se funde con
/// el fondo, como el suelo iluminado del escaparate de la Wii.
class StageLight extends StatelessWidget {
  const StageLight({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return CustomPaint(painter: _StageLightPainter(skin.accent), child: child);
  }
}

class _StageLightPainter extends CustomPainter {
  _StageLightPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .62);
    final r = size.shortestSide * .62;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: .26), accent.withValues(alpha: .08), accent.withValues(alpha: 0)],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // Rayos muy tenues, como el fondo de los canales de la Wii.
    final rays = Paint()..color = T.glintSoft;
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + (i - 4.5) * .2;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - .05) * r * 1.2, c.dy + math.sin(a - .05) * r * 1.2)
        ..lineTo(c.dx + math.cos(a + .05) * r * 1.2, c.dy + math.sin(a + .05) * r * 1.2)
        ..close();
      canvas.drawPath(path, rays);
    }
  }

  @override
  bool shouldRepaint(_StageLightPainter old) => old.accent != accent;
}

/// Bocadillo de lo que dice el Tama. Aparece con un rebote cada vez que
/// cambia el texto y apunta hacia abajo, al Tama.
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.text, this.maxWidth = 220});

  final String? text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final t = text;
    return AnimatedSwitcher(
      duration: skin.motion(const Duration(milliseconds: 260)),
      switchInCurve: skin.curve(Curves.easeOutBack),
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .6, end: 1).animate(animation),
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: t == null
          ? const SizedBox(key: ValueKey<String>('bubble.none'), height: 1)
          : ConstrainedBox(
              key: ValueKey<String>('bubble.$t'),
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: CustomPaint(
                painter: _BubblePainter(IbashoSkin.of(context).surfaces),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 7, 14, 15),
                  child: Text(
                    t,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Ty.body.copyWith(fontWeight: FontWeight.w600, height: 1.2),
                  ),
                ),
              ),
            ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.surfaces);

  final Surfaces surfaces;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 8),
      const Radius.circular(16),
    );
    final path = Path()
      ..addRRect(body)
      ..moveTo(size.width / 2 - 8, size.height - 9)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 8, size.height - 9)
      ..close();
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      Paint()
        ..color = T.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [surfaces.shellTop, surfaces.cardBottom],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = surfaces.hairline,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.surfaces != surfaces;
}

/// La cara de reserva, para una cuenta sin Tamas: una gota de plastico
/// lacado con ojos brillantes, mofletes y boca segun el humor.
class GlossyFace extends StatelessWidget {
  const GlossyFace({super.key, required this.joy, required this.size});

  final double joy;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _GlossyFacePainter(joy, IbashoSkin.of(context).accent)),
      );
}

class _GlossyFacePainter extends CustomPainter {
  _GlossyFacePainter(this.joy, this.accent);

  final double joy;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height * .52);
    paintGroundShadow(canvas, Offset(c.dx, size.height * .94), s * .7, .18);
    final body = Path()..addOval(Rect.fromCenter(center: c, width: s * .86, height: s * .8));
    paintPlastic(canvas, body, accent, edge: s * .018, shine: .9);

    final ko = joy < -.5;
    final eyeY = c.dy - s * .04;
    for (final dx in [-s * .16, s * .16]) {
      final e = Offset(c.dx + dx, eyeY);
      if (ko) {
        final p = Paint()
          ..color = T.tamaInk
          ..strokeWidth = s * .03
          ..strokeCap = StrokeCap.round;
        final r = s * .045;
        canvas.drawLine(e + Offset(-r, -r), e + Offset(r, r), p);
        canvas.drawLine(e + Offset(-r, r), e + Offset(r, -r), p);
      } else if (joy > .7) {
        // Ojos felices: arcos hacia arriba.
        canvas.drawArc(Rect.fromCircle(center: e.translate(0, s * .02), radius: s * .05), math.pi * 1.1, math.pi * .8, false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * .03
              ..strokeCap = StrokeCap.round
              ..color = T.tamaInk);
      } else {
        canvas.drawOval(Rect.fromCenter(center: e, width: s * .09, height: s * .12), Paint()..color = T.tamaInk);
        canvas.drawCircle(e + Offset(-s * .015, -s * .025), s * .018, Paint()..color = T.shellTop);
      }
    }
    final blush = Paint()..color = T.tamaBlush.withValues(alpha: .5);
    canvas.drawOval(Rect.fromCenter(center: Offset(c.dx - s * .26, c.dy + s * .06), width: s * .1, height: s * .055), blush);
    canvas.drawOval(Rect.fromCenter(center: Offset(c.dx + s * .26, c.dy + s * .06), width: s * .1, height: s * .055), blush);

    final mouthY = c.dy + s * .11;
    if (ko || joy < -.2) {
      canvas.drawOval(Rect.fromCenter(center: Offset(c.dx, mouthY + s * .01), width: s * .07, height: s * .08),
          Paint()..color = T.tamaMouth);
    } else {
      final curve = joy.clamp(-1.0, 1.0) * s * .07;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s * .08, mouthY)
          ..quadraticBezierTo(c.dx, mouthY + curve, c.dx + s * .08, mouthY),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * .028
          ..strokeCap = StrokeCap.round
          ..color = T.tamaInk,
      );
    }
  }

  @override
  bool shouldRepaint(_GlossyFacePainter old) => old.joy != joy || old.accent != accent;
}

// --- Marcadores -------------------------------------------------------------

/// Un marcador hundido: icono, cifra grande y etiqueta pequeña.
class Readout extends StatelessWidget {
  const Readout({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.height = 58,
  });

  final Widget icon;
  final String value;
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return SizedBox(
      height: height,
      child: GlossSurface(
        radius: height / 2,
        recessed: true,
        padding: EdgeInsets.symmetric(horizontal: height * .22),
        child: Row(
          children: [
            SizedBox(width: height * .56, height: height * .56, child: icon),
            SizedBox(width: height * .14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: Ty.numeral(height * .4, color: skin.accentDeep, weight: FontWeight.w700)),
                  ),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(height: 1.1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las monedas que quedan hoy en este juego: la moneda, «8/20 hoy» y una
/// barrita dorada que se llena. Cada juego tiene su tope de
/// [dailyRewardCap] al dia, y esto es lo que lo deja a la vista en su menu.
/// Lleno, lo dice y se queda en verde.
class DailyCoinsMeter extends ConsumerWidget {
  const DailyCoinsMeter({super.key, required this.game, this.height = 44});

  final String game;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final earned = ref.watch(rewardsProvider.select((r) => r.earnedToday(game)));
    final full = earned >= dailyRewardCap;
    final t = (earned / dailyRewardCap).clamp(0.0, 1.0);
    return SizedBox(
      key: ValueKey<String>('game.coins.$game'),
      height: height,
      child: GlossSurface(
        radius: height / 2,
        recessed: true,
        padding: EdgeInsets.symmetric(horizontal: height * .28),
        child: Row(
          children: [
            ArtIconView(ArtIcon.coin, size: height * .52),
            SizedBox(width: height * .18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '$earned/$dailyRewardCap',
                        style: Ty.numeral(height * .34, color: full ? T.correct : Art.goldDark, weight: FontWeight.w700),
                      ),
                      SizedBox(width: height * .14),
                      Expanded(
                        child: Text(
                          full ? l.gameCoinsTodayFull : l.gameCoinsToday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.micro,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: height * .08),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(height),
                    child: SizedBox(
                      height: math.max(4, height * .14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: skin.hairline),
                          // Crece hasta lo cobrado al abrir el menu.
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: t),
                            duration: skin.motion(const Duration(milliseconds: 700)),
                            curve: skin.curve(Curves.easeOutCubic),
                            builder: (context, v, _) => FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: v,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: full ? [T.correct, T.correct] : [Art.gold, Art.goldDark],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Resultados -------------------------------------------------------------

/// Una chapa de los resultados: «nuevo récord», un sello, una racha.
class ResultChip extends StatelessWidget {
  const ResultChip({super.key, required this.text, this.accent = false, this.icon});

  final String text;
  final bool accent;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 14,
      tint: accent ? skin.accent : null,
      elevation: .6,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[SizedBox(width: 16, height: 16, child: icon), const SizedBox(width: 6)],
          Text(text,
              style: Ty.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: accent ? T.onAccent : Ty.ink,
              )),
        ],
      ),
    );
  }
}

// --- Selector -----------------------------------------------------------------

/// Una opcion de un raíl hundido ([SegmentRail]). Elegida lleva `accentWash`
/// y filo `accentDeep`, nunca el acento lleno: ese es del boton que sigue.
class SegmentPill extends StatelessWidget {
  const SegmentPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.glyph,
    this.height = 44,
    this.caption,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final Glyph? glyph;
  final double height;

  /// Linea pequeña debajo (por ejemplo, cuantos kana tiene un grupo).
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => SizedBox(
        height: height,
        child: GlossSurface(
          radius: height / 2,
          tint: selected ? skin.accentWash : null,
          borderColor: selected ? skin.accentDeep : null,
          borderWidth: selected ? 1.6 : 1,
          elevation: selected ? 1.2 : (state.hover > 0 ? .8 : 0),
          specular: selected || state.hover > 0 ? 1 : 0,
          sink: state.press,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (glyph != null) ...[
                  GlyphIcon(glyph!, size: 18, color: selected ? skin.accentDeep : Ty.inkSoft, strokeWidth: 2.2),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                        label,
                        maxLines: 1,
                        style: Ty.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected ? skin.accentDeep : Ty.ink,
                          height: 1.1,
                        ),
                      ),
                      ),
                      if (caption != null)
                        Text(caption!, maxLines: 1, style: Ty.micro.copyWith(height: 1.1)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El raíl hundido donde van las [SegmentPill], repartidas a partes iguales.
class SegmentRail extends StatelessWidget {
  const SegmentRail({super.key, required this.children, this.height = 44});

  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) => GlossSurface(
        radius: height / 2 + 4,
        recessed: true,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );
}

// --- Entradas y monedas ----------------------------------------------------------

/// Entra con un rebote desde pequeño, como un dialogo de la consola.
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: skin.motion(const Duration(milliseconds: 480)),
      curve: skin.curve(Curves.easeOutBack),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: .7 + .3 * t, child: child),
      ),
      child: child,
    );
  }
}

String rewardText(L l, RewardOutcome? reward, bool pending) => pending
    ? l.gameCoinsPending
    : switch (reward?.status) {
        RewardStatus.granted => l.gameCoinsWon(reward!.coins),
        RewardStatus.capped => l.gameCoinsCapped,
        _ => l.gameCoinsFailed,
      };

/// La linea de monedas de unos resultados: la moneda pintada y el texto.
class CoinLine extends StatelessWidget {
  const CoinLine({super.key, required this.text, required this.granted});

  final String text;
  final bool granted;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ArtIconView(ArtIcon.coin, size: 26),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              key: const ValueKey<String>('game.results.coins'),
              textAlign: TextAlign.center,
              style: Ty.body.copyWith(fontWeight: FontWeight.w600, color: granted ? Art.goldDark : Ty.inkSoft),
            ),
          ),
        ],
      );
}

