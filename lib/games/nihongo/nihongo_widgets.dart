// Ibasho — piezas de Nihongo: la tarjeta de papel con su sello, los puntos
// de la ronda, las respuestas, las categorias y los resultados.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/rewards.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/pressable.dart';
import '../game_stage.dart';
import 'kana.dart';

/// El kana, grande, en gotica de libro de texto: es la forma que se aprende.
TextStyle kanaStyle(double size, {Color color = Art.brush}) =>
    Ty.display.copyWith(fontSize: size, height: 1.05, color: color, fontWeight: FontWeight.w500);

// --- Tarjeta ----------------------------------------------------------------

/// La tarjeta de estudiar: papel lacado con el kana. Cada tarjeta nueva entra
/// dandose la vuelta; al acertar cae el sello rojo (el «maru» de los
/// maestros japoneses) y al fallar tiembla y enseña la lectura buena.
class KanaCard extends StatelessWidget {
  const KanaCard({
    super.key,
    required this.char,
    required this.size,
    required this.correct,
    required this.reading,
  });

  final String char;
  final double size;

  /// `null` sin responder.
  final bool? correct;
  final String reading;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final combo = char.runes.length > 1;
    Widget card = SizedBox(
      width: size * (combo ? 1.2 : 1),
      height: size,
      child: GlossSurface(
        radius: size * .12,
        tint: Art.paper,
        elevation: 3,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Las lineas de guia de un cuaderno de caligrafia.
            Positioned.fill(child: CustomPaint(painter: _GuidePainter(skin.accent))),
            Padding(
              padding: EdgeInsets.only(bottom: correct == null ? 0 : size * .14),
              child: FittedBox(child: Text(char, style: kanaStyle(size * .56))),
            ),
            if (correct != null)
              Positioned(
                bottom: size * .07,
                child: PopIn(
                  child: GlossSurface(
                    radius: size * .06,
                    tint: correct! ? T.correct : T.wrong,
                    elevation: 1,
                    padding: EdgeInsets.symmetric(horizontal: size * .07, vertical: size * .012),
                    child: Text(reading, style: Ty.numeral(size * .1, color: T.onAccent, weight: FontWeight.w700)),
                  ),
                ),
              ),
            if (correct == true)
              Positioned(
                top: size * .05,
                right: size * .05,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: skin.motion(const Duration(milliseconds: 420)),
                  curve: skin.curve(Curves.easeOutBack),
                  builder: (context, t, child) => Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: (1 - t) * .6 - .2,
                      child: Transform.scale(scale: 1.8 - .8 * t, child: child),
                    ),
                  ),
                  child: SizedBox.square(dimension: size * .3, child: const CustomPaint(painter: MaruPainter())),
                ),
              ),
          ],
        ),
      ),
    );
    if (correct == false) {
      card = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: skin.motion(const Duration(milliseconds: 460)),
        builder: (context, t, child) => Transform.translate(
          offset: Offset(math.sin(t * math.pi * 6) * (1 - t) * 12, 0),
          child: Transform.rotate(angle: -.03 * t, child: child),
        ),
        child: card,
      );
    }
    return card;
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = accent.withValues(alpha: .16)
      ..strokeWidth = 1.2;
    final inset = size.shortestSide * .12;
    // Cruz discontinua del cuadrado de practica.
    for (var i = inset; i < size.width - inset; i += 8) {
      canvas.drawLine(Offset(i, size.height / 2), Offset(math.min(i + 4, size.width - inset), size.height / 2), p);
    }
    for (var i = inset; i < size.height - inset; i += 8) {
      canvas.drawLine(Offset(size.width / 2, i), Offset(size.width / 2, math.min(i + 4, size.height - inset)), p);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.accent != accent;
}

/// El «maru» rojo de acierto: un circulo a pincel, mas grueso donde empieza.
/// Con [hana] es el «hanamaru», el circulo con petalos de un trabajo perfecto.
class MaruPainter extends CustomPainter {
  const MaruPainter({this.hana = false});

  final bool hana;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * .38;
    final ink = Paint()
      ..color = Art.hanko
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    // Trazo en espiral con el grosor bajando, como una pincelada.
    final turns = hana ? 1.7 : 1.08;
    const steps = 48;
    for (var i = 0; i < steps; i++) {
      final a0 = -math.pi * .6 + i / steps * turns * math.pi * 2;
      final a1 = -math.pi * .6 + (i + 1) / steps * turns * math.pi * 2;
      final shrink = hana ? 1 - i / steps * .45 : 1 - i / steps * .06;
      final w = r * (.36 - i / steps * .16);
      canvas.drawLine(
        c + Offset(math.cos(a0), math.sin(a0)) * r * shrink,
        c + Offset(math.cos(a1), math.sin(a1)) * r * shrink,
        ink..strokeWidth = w,
      );
    }
    if (hana) {
      // Los petalos alrededor.
      for (var i = 0; i < 7; i++) {
        final a = i / 7 * math.pi * 2 - math.pi / 2;
        canvas.drawArc(
          Rect.fromCircle(center: c + Offset(math.cos(a), math.sin(a)) * r * 1.12, radius: r * .3),
          a - math.pi * .75,
          math.pi * 1.5,
          false,
          ink..strokeWidth = r * .1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MaruPainter old) => old.hana != hana;
}

// --- Progreso -----------------------------------------------------------------

/// Una bolita por tarjeta: hundida si falta, verde o roja si ya se ha
/// respondido, y la actual un poco mas grande con el filo del acento.
class RoundDots extends StatelessWidget {
  const RoundDots({super.key, required this.round, this.dot = 14});

  final KanaRound round;
  final double dot;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < round.questions.length; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dot * .18),
            child: AnimatedContainer(
              duration: skin.motion(const Duration(milliseconds: 220)),
              curve: skin.curve(Curves.easeOutBack),
              width: i == round.index ? dot * 1.35 : dot,
              height: i == round.index ? dot * 1.35 : dot,
              child: switch (round.questions[i].correct) {
                null => GlossSurface(
                    radius: dot,
                    recessed: i != round.index,
                    borderColor: i == round.index ? skin.accentDeep : null,
                    borderWidth: 1.6,
                  ),
                final ok => GlossSurface(radius: dot, tint: ok ? T.correct : T.wrong, elevation: .8),
              },
            ),
          ),
      ],
    );
  }
}

// --- Respuestas ---------------------------------------------------------------

enum AnswerLook { idle, right, wrong, dim }

/// Una de las cuatro lecturas: plastico blanco grande. Al responder la buena
/// se pone verde con un visto, la elegida mala roja con un aspa, y el resto se
/// apaga.
class AnswerTile extends StatelessWidget {
  const AnswerTile({
    super.key,
    required this.label,
    required this.look,
    required this.onPressed,
    this.height = 64,
    this.hint,
  });

  final String label;
  final AnswerLook look;
  final VoidCallback? onPressed;
  final double height;

  /// Tecla que la elige, en pequeño (en escritorio).
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tint = switch (look) {
      AnswerLook.right => T.correct,
      AnswerLook.wrong => T.wrong,
      _ => null,
    };
    final ink = tint != null ? T.onAccent : Ty.ink;
    return AnimatedOpacity(
      opacity: look == AnswerLook.dim ? .5 : 1,
      duration: skin.motion(const Duration(milliseconds: 180)),
      child: Pressable(
        onPressed: onPressed,
        cue: null,
        semanticLabel: label,
        builder: (context, state) => Transform.translate(
          offset: Offset(0, -3 * state.hover),
          child: SizedBox(
            height: height,
            child: GlossSurface(
              radius: height * .36,
              tint: tint,
              elevation: 1.4 + state.hover,
              sink: state.press,
              padding: EdgeInsets.symmetric(horizontal: height * .3),
              child: Row(
                children: [
                  SizedBox(
                    width: height * .34,
                    child: look == AnswerLook.right || look == AnswerLook.wrong
                        ? GlyphIcon(look == AnswerLook.right ? Glyph.check : Glyph.cross,
                            size: height * .34, color: ink, strokeWidth: 2.6)
                        : (hint == null ? null : Text(hint!, style: Ty.micro)),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label, style: Ty.numeral(height * .42, color: ink, weight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  SizedBox(width: height * .34),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Tabla ----------------------------------------------------------------------

/// La tabla para leer: los kana de un grupo en su cuadricula, cada uno en su
/// tarjetita de papel con la lectura debajo. Los dominados llevan el sello
/// rojo pequeño en la esquina, y el que se toca se enciende con el acento.
class KanaChartView extends StatelessWidget {
  const KanaChartView({
    super.key,
    required this.rows,
    required this.mastered,
    required this.selected,
    required this.onPressed,
    this.gap = 8,
  });

  final List<List<Kana?>> rows;
  final bool Function(Kana) mastered;
  final Kana? selected;
  final ValueChanged<Kana> onPressed;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final width = rows.first.length;
    return LayoutBuilder(
      builder: (context, box) {
        // Las de tres columnas no se estiran hasta ser enormes.
        final cell = math.min(96.0, (box.maxWidth - gap * (width - 1)) / width);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (r, row) in rows.indexed) ...[
              if (r > 0) SizedBox(height: gap),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (c, k) in row.indexed) ...[
                    if (c > 0) SizedBox(width: gap),
                    SizedBox(
                      width: cell,
                      height: cell * 1.08,
                      child: k == null
                          ? null
                          : _ChartCell(
                              key: ValueKey<String>('nihongo.chart.${k.char}'),
                              kana: k,
                              size: cell,
                              mastered: mastered(k),
                              selected: identical(k, selected),
                              onPressed: () => onPressed(k),
                            ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ChartCell extends StatelessWidget {
  const _ChartCell({
    super.key,
    required this.kana,
    required this.size,
    required this.mastered,
    required this.selected,
    required this.onPressed,
  });

  final Kana kana;
  final double size;
  final bool mastered;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final combo = kana.char.runes.length > 1;
    return Pressable(
      onPressed: onPressed,
      cue: null,
      semanticLabel: '${kana.char} ${kana.romaji}',
      builder: (context, state) => Transform.translate(
        offset: Offset(0, -2 * state.hover),
        child: GlossSurface(
          radius: size * .16,
          tint: selected ? skin.accent : Art.paper,
          elevation: 1.2 + state.hover,
          sink: state.press,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(size * .08, size * .06, size * .08, size * .08),
                  child: Column(
                    children: [
                      Expanded(
                        child: FittedBox(
                          child: Text(kana.char,
                              style: kanaStyle(size * (combo ? .42 : .5), color: selected ? T.onAccent : Art.brush)),
                        ),
                      ),
                      Text(
                        kana.romaji,
                        maxLines: 1,
                        style: Ty.numeral(size * .19, color: selected ? T.onAccent : Ty.inkSoft, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              if (mastered)
                Positioned(
                  top: size * .04,
                  right: size * .04,
                  child: SizedBox.square(dimension: size * .24, child: const CustomPaint(painter: MaruPainter())),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Categorias ---------------------------------------------------------------

/// Una categoria: su caracter sobre una tarjetita de papel, el nombre y el
/// progreso (o «próximamente» con un candado).
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.char,
    required this.name,
    required this.caption,
    required this.selected,
    required this.onPressed,
    this.locked = false,
    this.progress = 0,
    this.height = 112,
    this.compact = false,
  });

  final String char;
  final String name;
  final String caption;
  final bool selected;
  final bool locked;
  final double progress;
  final VoidCallback onPressed;
  final double height;

  /// En un movil estrecho: tarjetita y nombre mas pequeños.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tile = height * (compact ? .5 : .62);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: name,
      builder: (context, state) => Transform.translate(
        offset: Offset(0, selected ? -3 : -3 * state.hover),
        child: SizedBox(
          height: height,
          child: GlossSurface(
            radius: 22,
            tint: selected ? skin.accentWash : null,
            borderColor: selected ? skin.accentDeep : null,
            borderWidth: selected ? 1.8 : 1,
            elevation: selected ? 2 : 1 + state.hover,
            sink: state.press,
            padding: EdgeInsets.all(height * (compact ? .1 : .12)),
            child: Row(
              children: [
                SizedBox(
                  width: tile,
                  height: tile,
                  child: GlossSurface(
                    radius: tile * .2,
                    tint: locked ? skin.shellBottom : Art.paper,
                    elevation: .8,
                    child: Center(
                      child: Text(char, style: kanaStyle(tile * .6, color: locked ? Ty.inkSoft : Art.brush)),
                    ),
                  ),
                ),
                SizedBox(width: height * (compact ? .09 : .12)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (compact ? Ty.body : Ty.lead).copyWith(
                            fontWeight: FontWeight.w600,
                            color: locked ? Ty.inkSoft : (selected ? skin.accentDeep : Ty.ink),
                          )),
                      const SizedBox(height: 4),
                      if (locked)
                        Row(
                          children: [
                            GlyphIcon(Glyph.lock, size: 14, color: Ty.inkSoft, strokeWidth: 2),
                            const SizedBox(width: 4),
                            Flexible(child: Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro)),
                          ],
                        )
                      else ...[
                        Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro),
                        const SizedBox(height: 5),
                        MasteryBar(value: progress, height: 8),
                      ],
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

/// Barra de cristal con reflejo, llena con el acento.
class MasteryBar extends StatelessWidget {
  const MasteryBar({super.key, required this.value, this.height = 10});

  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return SizedBox(
      height: height,
      child: GlossSurface(
        radius: height,
        recessed: true,
        child: LayoutBuilder(
          builder: (context, box) => Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
              duration: skin.motion(const Duration(milliseconds: 700)),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => v <= 0
                  ? const SizedBox.shrink()
                  : SizedBox(
                      width: math.max(height, box.maxWidth * v),
                      child: GlossSurface(radius: height, tint: skin.accent, elevation: 0),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Resultados -----------------------------------------------------------------

class NihongoResultsCard extends StatelessWidget {
  const NihongoResultsCard({
    super.key,
    required this.round,
    required this.newBest,
    required this.reward,
    required this.rewardPending,
    required this.onAgain,
    required this.onReview,
    required this.onMenu,
  });

  final KanaRound round;
  final bool newBest;
  final RewardOutcome? reward;
  final bool rewardPending;
  final VoidCallback onAgain;
  final VoidCallback? onReview;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final perfect = round.perfect;
    final coins = nihongoRewardFor(round);
    final coinText = round.review
        ? l.nihongoReviewNoCoins
        : coins > 0
            ? rewardText(l, reward, rewardPending)
            : l.nihongoCoinsHint;
    final missed = round.missed;
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GlossSurface(
          key: const ValueKey<String>('nihongo.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(perfect ? l.nihongoPerfect : l.nihongoResultsTitle,
                  style: Ty.title.copyWith(color: skin.accentDeep), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              if (perfect)
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: skin.motion(const Duration(milliseconds: 900)),
                  curve: skin.curve(Curves.elasticOut),
                  builder: (context, t, child) => Transform.scale(scale: t.clamp(0.0, 2.0), child: child),
                  child: const SizedBox.square(dimension: 84, child: CustomPaint(painter: MaruPainter(hana: true))),
                ),
              Text(l.nihongoScore(round.right, round.questions.length),
                  style: Ty.numeral(36, color: Ty.ink, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              RoundDots(round: round, dot: 12),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (newBest) ResultChip(text: l.gameNewRecord, accent: true),
                  if (round.bestStreak >= 3) ResultChip(text: l.nihongoStreak(round.bestStreak)),
                ],
              ),
              if (missed.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(l.nihongoMissed, style: Ty.micro.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in missed)
                      GlossSurface(
                        radius: 12,
                        tint: Art.paper,
                        elevation: .8,
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(k.char, style: kanaStyle(22)),
                            const SizedBox(width: 6),
                            Text(k.romaji, style: Ty.numeral(15, color: skin.accentDeep, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              CoinLine(text: coinText, granted: reward?.status == RewardStatus.granted),
              const SizedBox(height: 16),
              IbashoButton(
                key: const ValueKey<String>('nihongo.again'),
                label: l.nihongoAgain,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onAgain,
              ),
              if (onReview != null) ...[
                const SizedBox(height: 6),
                IbashoButton(
                  key: const ValueKey<String>('nihongo.review'),
                  label: l.nihongoReview,
                  glyph: Glyph.undo,
                  expand: true,
                  onPressed: onReview,
                ),
              ],
              const SizedBox(height: 4),
              IbashoButton(
                label: l.nihongoMenu,
                tone: ButtonTone.quiet,
                height: 40,
                cue: Sfx.back,
                onPressed: onMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
