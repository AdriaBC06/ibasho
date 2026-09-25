// Ibasho — Odori: las tarjetas de la partida (pausa y resultados) y el
// cartel del juicio.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../game_stage.dart';
import 'odori_board.dart';
import 'odori_chart.dart';
import 'odori_engine.dart';

/// Nombre de cada dificultad: se dejan en ingles en los dos idiomas.
extension OdoriDifficultyLabel on OdoriDifficulty {
  String get label => switch (this) {
        OdoriDifficulty.easy => 'Easy',
        OdoriDifficulty.normal => 'Normal',
        OdoriDifficulty.hard => 'Hard',
        OdoriDifficulty.extreme => 'Extreme',
        OdoriDifficulty.impossible => 'Impossible',
      };

  /// Un color por dificultad, del verde facil al violeta imposible.
  Color get color => switch (this) {
        OdoriDifficulty.easy => const Color(0xFF4CC38A),
        OdoriDifficulty.normal => const Color(0xFF3FA9E8),
        OdoriDifficulty.hard => const Color(0xFFF2A33A),
        OdoriDifficulty.extreme => const Color(0xFFEF5B6B),
        OdoriDifficulty.impossible => const Color(0xFF9B5CE0),
      };
}

String judgmentText(L l, Judgment j) => switch (j) {
      Judgment.brillo => l.odoriBrillo,
      Judgment.bien => l.odoriBien,
      Judgment.vale => l.odoriVale,
      Judgment.miss => l.odoriUy,
    };

Color judgmentColor(Judgment j, Color accentDeep) => switch (j) {
      Judgment.brillo => const Color(0xFFE89A1C),
      Judgment.bien => accentDeep,
      Judgment.vale => T.inkSoft,
      Judgment.miss => T.wrong,
    };

/// Color de cada rango.
Color rankColor(OdoriRank r) => switch (r) {
      OdoriRank.sPlusPlus => const Color(0xFFE89A1C),
      OdoriRank.sPlus => const Color(0xFFF2B43A),
      OdoriRank.s => const Color(0xFFF2B43A),
      OdoriRank.a => const Color(0xFFEF6B8A),
      OdoriRank.b => const Color(0xFF3FA9E8),
      OdoriRank.c => const Color(0xFF4CC38A),
      OdoriRank.d => T.inkSoft,
    };

/// La etiqueta de la dificultad: una pastilla de su color.
class DifficultyTag extends StatelessWidget {
  const DifficultyTag({super.key, required this.difficulty, this.small = false});

  final OdoriDifficulty difficulty;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = difficulty.color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 12, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(c, const Color(0xFFFFFFFF), .3)!, c],
        ),
        border: Border.all(color: Color.lerp(c, const Color(0xFF000000), .2)!, width: 1.2),
      ),
      child: Text(
        difficulty.label,
        style: Ty.numeral(small ? 12 : 14, color: const Color(0xFFFFFFFF), weight: FontWeight.w700),
      ),
    );
  }
}

/// El juicio que acaba de pasar, que sube y se apaga.
class JudgmentPop extends StatelessWidget {
  const JudgmentPop({super.key, required this.judgment, required this.age, required this.combo});

  final Judgment? judgment;

  /// Segundos desde que se juzgo.
  final double age;
  final int combo;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final j = judgment;
    if (j == null || age > .6) return const SizedBox.shrink();
    final k = (age / .6).clamp(0.0, 1.0);
    final pop = age < .08 ? 1 + (.08 - age) * 3 : 1.0;
    return Opacity(
      opacity: 1 - k * k,
      child: Transform.translate(
        offset: Offset(0, -10 * k),
        child: Transform.scale(
          scale: pop,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                judgmentText(l, j),
                style: Ty.numeral(26, color: judgmentColor(j, skin.accentDeep), weight: FontWeight.w700).copyWith(
                  shadows: const [Shadow(color: Color(0xCCFFFFFF), blurRadius: 6)],
                ),
              ),
              if (combo >= 4)
                Text(
                  '$combo',
                  style: Ty.numeral(18, color: skin.accentDeep, weight: FontWeight.w700).copyWith(
                    shadows: const [Shadow(color: Color(0xCCFFFFFF), blurRadius: 6)],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class OdoriPauseCard extends StatelessWidget {
  const OdoriPauseCard({super.key, required this.onResume, required this.onRestart, required this.onLeave});

  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: GlossSurface(
          key: const ValueKey<String>('odori.paused'),
          radius: 28,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.odoriPause, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('odori.resume'),
                label: l.odoriResume,
                glyph: Glyph.play,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onResume,
              ),
              const SizedBox(height: 6),
              IbashoButton(
                label: l.odoriRestart,
                glyph: Glyph.refresh,
                tone: ButtonTone.quiet,
                expand: true,
                onPressed: onRestart,
              ),
              const SizedBox(height: 2),
              IbashoButton(
                label: l.odoriLeave,
                tone: ButtonTone.quiet,
                height: 40,
                cue: Sfx.back,
                expand: true,
                onPressed: onLeave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La letra del rango, grande y lacada.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank, this.size = 92});

  final OdoriRank rank;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = rankColor(rank);
    final label = rank.label;
    final fontSize = size * (label.length > 2 ? .42 : (label.length > 1 ? .5 : .62));
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-.3, -.45),
            colors: [Color.lerp(c, const Color(0xFFFFFFFF), .55)!, c],
          ),
          border: Border.all(color: Color.lerp(c, const Color(0xFF000000), .22)!, width: 3),
          boxShadow: [BoxShadow(color: c.withValues(alpha: .4), blurRadius: 18, offset: const Offset(0, 4))],
        ),
        child: Center(
          child: Text(
            label,
            style: Ty.numeral(fontSize, color: const Color(0xFFFFFFFF), weight: FontWeight.w700).copyWith(
              shadows: [Shadow(color: Color.lerp(c, const Color(0xFF000000), .4)!, blurRadius: 3, offset: const Offset(0, 1.5))],
            ),
          ),
        ),
      ),
    );
  }
}

class OdoriResultsCard extends StatelessWidget {
  const OdoriResultsCard({
    super.key,
    required this.result,
    required this.title,
    required this.difficulty,
    required this.keys,
    required this.onAgain,
    required this.onLeave,
    this.best,
    this.newRecord = false,
    this.assisted = false,
    this.coins,
    this.coinsGranted = false,
  });

  /// La linea de las monedas cobradas (o por que no), si toca.
  final String? coins;
  final bool coinsGranted;

  final OdoriResult result;
  final String title;
  final OdoriDifficulty difficulty;
  final int keys;

  /// Mejor puntuacion guardada antes de esta partida, si la hay.
  final int? best;

  /// Esta partida bate el récord.
  final bool newRecord;

  /// Se ha jugado con la ayuda del Tama.
  final bool assisted;
  final VoidCallback onAgain;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final r = result;

    Widget stat(String value, String label, {Color? color}) => Expanded(
          child: Column(
            children: [
              Text(value, style: Ty.numeral(20, color: color ?? skin.accentDeep, weight: FontWeight.w700)),
              Text(label, style: Ty.micro, textAlign: TextAlign.center),
            ],
          ),
        );

    final percent = (r.accuracy * 100).toStringAsFixed(2);
    final newBest = newRecord;
    return PopIn(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: GlossSurface(
          key: const ValueKey<String>('odori.results'),
          radius: 30,
          elevation: 3,
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Ty.title.copyWith(color: skin.accentDeep), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  DifficultyTag(difficulty: difficulty, small: true),
                  const SizedBox(width: 8),
                  Text(l.odoriKeysCount(keys), style: Ty.caption),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RankBadge(rank: r.rank),
                  const SizedBox(width: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: r.score.toDouble()),
                        duration: skin.motion(Duration(milliseconds: math.min(1600, 500 + r.score ~/ 1000))),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Text(
                          '${v.round()}',
                          style: Ty.numeral(38, color: Ty.ink, weight: FontWeight.w700),
                        ),
                      ),
                      Text('${l.odoriAccuracy} $percent %', style: Ty.body.copyWith(color: skin.accentDeep)),
                      if (best != null) Text('${l.gameBest} ${math.max(best!, r.score)}', style: Ty.caption),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GlossSurface(
                radius: 18,
                recessed: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    stat('${r.brillo}', l.odoriBrillo, color: judgmentColor(Judgment.brillo, skin.accentDeep)),
                    stat('${r.bien}', l.odoriBien),
                    stat('${r.vale}', l.odoriVale, color: T.inkSoft),
                    stat('${r.misses}', l.odoriMisses, color: r.misses == 0 ? T.correct : T.wrong),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              GlossSurface(
                radius: 18,
                recessed: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    stat('${r.maxCombo}/${r.total}', l.odoriMaxCombo),
                    stat('${r.early}', l.odoriEarly),
                    stat('${r.late}', l.odoriLate),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (newBest) ResultChip(text: l.gameNewRecord, accent: true),
                  if (assisted) ResultChip(text: l.odoriAssisted),
                  if (r.rank == OdoriRank.sPlusPlus)
                    ResultChip(text: l.odoriAllBrillo, accent: !newBest)
                  else if (r.fullCombo)
                    ResultChip(text: l.odoriFullCombo, accent: !newBest),
                ],
              ),
              if (coins != null) ...[
                const SizedBox(height: 10),
                CoinLine(text: coins!, granted: coinsGranted),
              ],
              const SizedBox(height: 14),
              IbashoButton(
                key: const ValueKey<String>('odori.again'),
                label: l.odoriAgain,
                glyph: Glyph.refresh,
                tone: ButtonTone.accent,
                expand: true,
                onPressed: onAgain,
              ),
              const SizedBox(height: 4),
              IbashoButton(
                label: l.odoriLeave,
                tone: ButtonTone.quiet,
                height: 40,
                cue: Sfx.back,
                onPressed: onLeave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra fina de lo que llevas de cancion.
class SongProgress extends StatelessWidget {
  const SongProgress({super.key, required this.value, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return SizedBox(
      height: 6,
      child: CustomPaint(painter: _ProgressPainter(value.clamp(0, 1), color ?? skin.accent, skin.hairline)),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.value, this.color, this.track);

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track.withValues(alpha: .6));
    if (value <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width * value, size.height), r),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => old.value != value || old.color != color;
}


/// Etiqueta corta del modo de juego (Taki y su direccion).
String flowLabel(TakiFlow f) => switch (f) {
      TakiFlow.down => '↓',
      TakiFlow.up => '↑',
      TakiFlow.right => '→',
      TakiFlow.left => '←',
    };
